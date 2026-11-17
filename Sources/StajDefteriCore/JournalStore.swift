import Foundation

public enum JournalStoreError: LocalizedError, Equatable, Sendable {
    case invalidInternshipDates
    case internshipNotFound
    case entryNotFound
    case duplicateEntryDate
    case invalidPhotos
    case photoUnavailable
    case unreadableJournal
    case unsupportedJournalVersion
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .invalidInternshipDates: "Stajın bitiş tarihi başlangıç tarihinden önce olamaz."
        case .internshipNotFound: "Staj kaydı bulunamadı."
        case .entryNotFound: "Günlük kaydı bulunamadı."
        case .duplicateEntryDate: "Bu stajda seçilen tarihe ait bir günlük kaydı zaten var."
        case .invalidPhotos: "Fotoğraflardan biri kaydedilemedi. Fotoğrafı yeniden ekleyin."
        case .photoUnavailable: "Kaydedilen fotoğraf açılamadı."
        case .unreadableJournal: "Cihazdaki staj defteri açılamadı."
        case .unsupportedJournalVersion: "Staj defteri dosyası bu uygulama sürümüyle açılamıyor."
        case .writeFailed: "Değişiklikler cihaza kaydedilemedi. Yeniden deneyin."
        }
    }
}

/// Stores a journal in a private directory. Keep one instance for each open journal directory.
public actor JournalStore {
    private struct JournalFile: Codable {
        static let currentVersion = 1
        let version: Int
        let internships: [Internship]
    }

    private let directory: URL
    private let indexURL: URL
    private let photosDirectory: URL

    public init(directory: URL) {
        self.directory = directory
        indexURL = directory.appendingPathComponent("journal.json", isDirectory: false)
        photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
    }

    public func load() throws -> [Internship] {
        let internships = try readJournal()
        removeUnreferencedPhotos(in: internships)
        return internships
    }

    /// Saves internship details. Entry content is managed by the entry methods.
    @discardableResult
    public func saveInternship(_ internship: Internship) throws -> [Internship] {
        guard internship.startDate <= internship.endDate else { throw JournalStoreError.invalidInternshipDates }
        var internships = try readJournal()
        var updated = internship
        if let index = internships.firstIndex(where: { $0.id == internship.id }) {
            updated.entries = internships[index].entries
            internships[index] = updated
        } else {
            updated.entries = []
            internships.append(updated)
        }
        try commit(internships)
        return internships
    }

    @discardableResult
    public func deleteInternship(id: UUID) throws -> [Internship] {
        var internships = try readJournal()
        guard let index = internships.firstIndex(where: { $0.id == id }) else {
            throw JournalStoreError.internshipNotFound
        }
        internships.remove(at: index)
        try commit(internships)
        return internships
    }

    /// Provide JPEG data for each newly attached photo. Existing photos retain their original data.
    @discardableResult
    public func saveEntry(
        _ entry: JournalEntry,
        internshipID: UUID,
        newPhotos: [UUID: Data] = [:]
    ) throws -> [Internship] {
        var internships = try readJournal()
        guard let internshipIndex = internships.firstIndex(where: { $0.id == internshipID }) else {
            throw JournalStoreError.internshipNotFound
        }
        var entries = internships[internshipIndex].entries
        guard !entries.contains(where: { $0.id != entry.id && $0.date == entry.date }) else {
            throw JournalStoreError.duplicateEntryDate
        }

        let index = entries.firstIndex(where: { $0.id == entry.id })
        let previousIDs = index.map { Set(entries[$0].photos.map(\.id)) } ?? []
        let incomingIDs = Set(entry.photos.map(\.id))
        let newIDs = incomingIDs.subtracting(previousIDs)
        guard incomingIDs.count == entry.photos.count,
              newIDs == Set(newPhotos.keys), newPhotos.values.allSatisfy({ !$0.isEmpty }),
              newIDs.isDisjoint(with: photoIDs(in: internships)) else {
            throw JournalStoreError.invalidPhotos
        }

        if let index {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        internships[internshipIndex].entries = entries.sorted { $0.date < $1.date }
        try commit(internships, newPhotos: newPhotos)
        return internships
    }

    @discardableResult
    public func deleteEntry(id: UUID, internshipID: UUID) throws -> [Internship] {
        var internships = try readJournal()
        guard let internshipIndex = internships.firstIndex(where: { $0.id == internshipID }) else {
            throw JournalStoreError.internshipNotFound
        }
        guard let entryIndex = internships[internshipIndex].entries.firstIndex(where: { $0.id == id }) else {
            throw JournalStoreError.entryNotFound
        }
        internships[internshipIndex].entries.remove(at: entryIndex)
        try commit(internships)
        return internships
    }

    public func photoData(id: UUID) throws -> Data {
        do {
            return try Data(contentsOf: photoURL(id: id))
        } catch {
            throw JournalStoreError.photoUnavailable
        }
    }

    /// Reads entry details and their image data together while writes are isolated by the store.
    public func exportSnapshot(internshipID: UUID) throws -> (internship: Internship, photoData: [UUID: Data]) {
        guard let internship = try readJournal().first(where: { $0.id == internshipID }) else {
            throw JournalStoreError.internshipNotFound
        }
        var data: [UUID: Data] = [:]
        for entry in internship.entries {
            for photo in entry.photos {
                data[photo.id] = try photoData(id: photo.id)
            }
        }
        return (internship, data)
    }

    private func readJournal() throws -> [Internship] {
        let file: JournalFile
        do {
            let data = try Data(contentsOf: indexURL)
            file = try JSONDecoder().decode(JournalFile.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        } catch {
            throw JournalStoreError.unreadableJournal
        }
        guard file.version == JournalFile.currentVersion else { throw JournalStoreError.unsupportedJournalVersion }
        return file.internships
    }

    private func commit(_ internships: [Internship], newPhotos: [UUID: Data] = [:]) throws {
        let fileManager = FileManager.default
        var writtenPhotos: [URL] = []
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !newPhotos.isEmpty {
                try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            }
            for (id, data) in newPhotos {
                let url = photoURL(id: id)
                try data.write(to: url, options: .atomic)
                writtenPhotos.append(url)
            }
            let file = JournalFile(version: JournalFile.currentVersion, internships: internships)
            let data = try JSONEncoder().encode(file)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            for url in writtenPhotos { try? fileManager.removeItem(at: url) }
            throw JournalStoreError.writeFailed
        }
        // Remove old files only after the new index has been committed. `load` retries cleanup if interrupted.
        removeUnreferencedPhotos(in: internships)
    }

    private func removeUnreferencedPhotos(in internships: [Internship]) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: photosDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let referencedIDs = photoIDs(in: internships)
        for url in files where url.pathExtension == "jpg" {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
               !referencedIDs.contains(id) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func photoIDs(in internships: [Internship]) -> Set<UUID> {
        Set(internships.flatMap(\.entries).flatMap(\.photos).map(\.id))
    }

    private func photoURL(id: UUID) -> URL {
        photosDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
    }
}
