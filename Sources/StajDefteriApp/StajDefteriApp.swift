import Observation
import StajDefteriCore
import SwiftUI

@main
@MainActor
struct StajDefteriApp: App {
    @State private var journal = JournalModel()

    var body: some Scene {
        WindowGroup {
            InternshipList(journal: journal)
                .tint(Color(red: 0.05, green: 0.48, blue: 0.46))
        }
    }
}

@MainActor
@Observable
final class JournalModel {
    private(set) var internships: [Internship] = []
    private(set) var isLoading = true
    private(set) var loadError: String?
    private var store: JournalStore?
    @ObservationIgnored private var isOpening = false

    func open() async {
        guard store == nil, !isOpening else { return }
        isOpening = true
        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            isOpening = false
        }

        do {
            let files = FileManager.default
            var directory = try files.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("StajDefteri", isDirectory: true)
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try directory.setResourceValues(resources)

            let localStore = JournalStore(directory: directory)
            internships = try await localStore.load()
            try? files.removeItem(at: ExportLocation.root)
            store = localStore
        } catch {
            loadError = error.localizedDescription
        }
    }

    func save(_ internship: Internship) async throws {
        let store = try requireStore()
        internships = try await store.saveInternship(internship)
    }

    func save(_ entry: JournalEntry, in internshipID: UUID, photos: [UUID: Data]) async throws {
        let store = try requireStore()
        internships = try await store.saveEntry(entry, internshipID: internshipID, newPhotos: photos)
    }

    func deleteInternship(_ id: UUID) async throws {
        let store = try requireStore()
        internships = try await store.deleteInternship(id: id)
    }

    func deleteEntry(_ id: UUID, in internshipID: UUID) async throws {
        let store = try requireStore()
        internships = try await store.deleteEntry(id: id, internshipID: internshipID)
    }

    func photoData(for id: UUID) async throws -> Data {
        let store = try requireStore()
        return try await store.photoData(id: id)
    }

    func export(_ id: UUID) async throws -> URL {
        let store = try requireStore()
        let snapshot = try await store.exportSnapshot(internshipID: id)
        return try await Task.detached(priority: .userInitiated) {
            try ExportLocation.write(internship: snapshot.internship, photos: snapshot.photoData)
        }.value
    }

    private func requireStore() throws -> JournalStore {
        guard let store else { throw JournalUnavailable() }
        return store
    }
}

private struct JournalUnavailable: LocalizedError {
    var errorDescription: String? { "Staj defteri henüz açılmadı." }
}

extension LocalDate {
    var displayText: String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR")))
    }
}
