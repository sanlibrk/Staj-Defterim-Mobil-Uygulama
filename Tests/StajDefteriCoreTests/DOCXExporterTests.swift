import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
import StajDefteriCore

final class DOCXExporterTests: XCTestCase {
    func testDOCXContainsEditableTextDayBreaksAndEmbeddedPhotos() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstDay = try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 6))
        let secondDay = try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 7))
        let firstPhoto = JournalPhoto(caption: "Örnek grafik <A> & \"B\"")
        let secondPhoto = JournalPhoto(caption: "Örnek karşılaştırma grafiği")
        let firstEntry = JournalEntry(
            date: firstDay,
            work: "Görevleri A & B olarak grupladım.\r\nÖlçümler <örnek>\t1–2",
            method: "Değerleri bir çizelgeye kaydettim.",
            result: "Çizelgeyi ekip sorumlusuyla paylaştım.",
            learning: "Ölçüm birimini her sütunda belirtmeyi öğrendim.",
            photos: [firstPhoto]
        )
        let secondEntry = JournalEntry(
            date: secondDay,
            work: "Çizelgedeki değerleri karşılaştırdım.",
            method: "Sonuçları iki gruba ayırdım.",
            result: "Grup farklarını grafikte gösterdim.",
            learning: "Grafiği açıklayıcı eksen adlarıyla etiketledim.",
            photos: [secondPhoto]
        )
        let internship = Internship(
            studentName: "Deniz Çelik & Ece Öztürk",
            school: "Örnek Meslek Yüksekokulu",
            department: "Bilişim",
            studentNumber: "000123",
            workplace: "Örnek Atölye",
            startDate: firstDay,
            endDate: secondDay,
            entries: [secondEntry, firstEntry]
        )
        let image = try XCTUnwrap(Data(base64Encoded: Self.exampleJPEG, options: .ignoreUnknownCharacters))
        let destination = folder.appendingPathComponent("Staj Defteri.docx")
        try DOCXExporter.export(internship: internship, photoData: [firstPhoto.id: image, secondPhoto.id: image], to: destination)

        let parts = try storedParts(in: destination)
        XCTAssertEqual(Set(parts.keys), [
            "[Content_Types].xml", "_rels/.rels", "word/styles.xml", "word/document.xml",
            "word/_rels/document.xml.rels", "word/media/foto-1.jpg", "word/media/foto-2.jpg",
        ])
        XCTAssertEqual(parts["word/media/foto-1.jpg"], image)
        XCTAssertEqual(parts["word/media/foto-2.jpg"], image)

        let document = try XMLDocument(data: XCTUnwrap(parts["word/document.xml"]), options: [])
        let dayHeadings = try document.nodes(forXPath: "//*[local-name()='p'][*[local-name()='pPr']/*[local-name()='pageBreakBefore']]")
        XCTAssertEqual(dayHeadings.compactMap(\.stringValue), ["06.07.2026", "07.07.2026"])

        let text = try document.nodes(forXPath: "//*[local-name()='r']/*[local-name()='t']").compactMap(\.stringValue)
        let requiredText = [
            "Staj Defteri", internship.studentName, "000123", "Ne yaptım", "Nasıl yaptım", "Sonuç", "Öğrendiklerim",
            "Görevleri A & B olarak grupladım.", "Ölçümler <örnek>", "1–2", firstEntry.method, firstEntry.result,
            firstEntry.learning, firstPhoto.caption, secondEntry.work, secondPhoto.caption,
        ]
        for value in requiredText {
            XCTAssertTrue(text.contains(value), "Missing editable paragraph content: \(value)")
        }
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='br']").count, 1)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tab']").count, 1)
        let imageLinks = try document.nodes(forXPath: "//*[local-name()='blip']/@*[local-name()='embed']")
        XCTAssertEqual(imageLinks.compactMap(\.stringValue), ["rId2", "rId3"])

        let relationships = try XMLDocument(data: XCTUnwrap(parts["word/_rels/document.xml.rels"]), options: [])
        let imageTargets = try relationships.nodes(forXPath: "//*[local-name()='Relationship']/@Target")
        XCTAssertEqual(imageTargets.compactMap(\.stringValue), ["styles.xml", "media/foto-1.jpg", "media/foto-2.jpg"])

        if let fixturePath = ProcessInfo.processInfo.environment["STAJ_DOCX_FIXTURE"], !fixturePath.isEmpty {
            try Data(contentsOf: destination).write(to: URL(fileURLWithPath: fixturePath), options: .atomic)
        }
    }

    func testBadPhotoLeavesNoPartialOutputOrStagingFile() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = JournalPhoto(caption: "Fotoğraf")
        let internship = Internship(entries: [JournalEntry(photos: [photo])])
        let destination = folder.appendingPathComponent("Staj Defteri.docx")

        XCTAssertThrowsError(try DOCXExporter.export(internship: internship, photoData: [:], to: destination)) {
            XCTAssertEqual($0 as? DOCXExportError, .missingPhoto)
        }
        XCTAssertThrowsError(try DOCXExporter.export(internship: internship, photoData: [photo.id: Data([0xFF, 0xD8])], to: destination)) {
            XCTAssertEqual($0 as? DOCXExportError, .invalidPhoto)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testExportUsesSavedEditsAndOmitsDeletedEntriesAndPhotos() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appendingPathComponent("journal", isDirectory: true)
        let store = JournalStore(directory: storage)
        let internship = Internship(studentName: "İpek Çelik", workplace: "Atölye")
        let image = try XCTUnwrap(Data(base64Encoded: Self.exampleJPEG, options: .ignoreUnknownCharacters))
        let first = JournalPhoto(caption: "İlk açıklama")
        let removed = JournalPhoto(caption: "Silinen fotoğraf")
        let firstDay = try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 6))
        let secondDay = try XCTUnwrap(LocalDate(year: 2026, month: 7, day: 7))
        var keptEntry = JournalEntry(date: firstDay, work: "İlk çalışma", photos: [first])
        let removedEntry = JournalEntry(date: secondDay, work: "Silinen çalışma", photos: [removed])
        try await store.saveInternship(internship)
        try await store.saveEntry(keptEntry, internshipID: internship.id, newPhotos: [first.id: image])
        try await store.saveEntry(removedEntry, internshipID: internship.id, newPhotos: [removed.id: image])
        keptEntry.photos[0].caption = "Düzenlenen açıklama"
        try await store.saveEntry(keptEntry, internshipID: internship.id)
        try await store.deleteEntry(id: removedEntry.id, internshipID: internship.id)

        let reopened = JournalStore(directory: storage)
        let snapshot = try await reopened.exportSnapshot(internshipID: internship.id)
        let destination = folder.appendingPathComponent("Staj Defteri.docx")
        try DOCXExporter.export(internship: snapshot.internship, photoData: snapshot.photoData, to: destination)

        let parts = try storedParts(in: destination)
        let xml = try XCTUnwrap(String(data: XCTUnwrap(parts["word/document.xml"]), encoding: .utf8))
        XCTAssertTrue(xml.contains("Düzenlenen açıklama"))
        XCTAssertFalse(xml.contains("İlk açıklama"))
        XCTAssertFalse(xml.contains("Silinen çalışma"))
        XCTAssertFalse(xml.contains("Silinen fotoğraf"))
        XCTAssertEqual(parts["word/media/foto-1.jpg"], image)
        XCTAssertNil(parts["word/media/foto-2.jpg"])
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func storedParts(in url: URL) throws -> [String: Data] {
        let archive = try Data(contentsOf: url)
        let end = try XCTUnwrap(archive.count >= 22 ? archive.count - 22 : nil)
        XCTAssertEqual(littleEndian(in: archive, at: end, count: 4), 0x06054B50)
        let directoryOffset = littleEndian(in: archive, at: end + 16, count: 4)
        let directoryLength = littleEndian(in: archive, at: end + 12, count: 4)
        _ = try XCTUnwrap(directoryOffset + directoryLength == end ? true : nil)
        XCTAssertEqual(littleEndian(in: archive, at: directoryOffset, count: 4), 0x02014B50)

        var parts: [String: Data] = [:]
        var offset = 0
        while offset < directoryOffset {
            _ = try XCTUnwrap(offset + 30 <= directoryOffset ? true : nil)
            XCTAssertEqual(littleEndian(in: archive, at: offset, count: 4), 0x04034B50)
            XCTAssertEqual(littleEndian(in: archive, at: offset + 8, count: 2), 0)
            let length = littleEndian(in: archive, at: offset + 18, count: 4)
            let nameLength = littleEndian(in: archive, at: offset + 26, count: 2)
            let extraLength = littleEndian(in: archive, at: offset + 28, count: 2)
            let nameStart = offset + 30
            let contentStart = nameStart + nameLength + extraLength
            let contentEnd = contentStart + length
            _ = try XCTUnwrap(contentEnd <= directoryOffset ? true : nil)
            let name = try XCTUnwrap(String(data: archive[nameStart..<(nameStart + nameLength)], encoding: .utf8))
            XCTAssertNil(parts.updateValue(archive[contentStart..<contentEnd], forKey: name))
            offset = contentEnd
        }
        XCTAssertEqual(parts.count, littleEndian(in: archive, at: end + 10, count: 2))
        return parts
    }

    private func littleEndian(in data: Data, at offset: Int, count: Int) -> Int {
        (0..<count).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
    }

    // A 48 × 32 synthetic graph for testing package extraction and inline drawing.
    private static let exampleJPEG = """
    /9j/4AAQSkZJRgABAQEAYABgAAD/2wBDABwTFRgVERwYFhgfHRwhKUUtKSYmKVQ8QDJFZFhpZ2JY
    YF9ufJ6GbnWWd19giruLlqOpsbOxa4TC0MGszp6usar/2wBDAR0fHykkKVEtLVGqcmByqqqqqqqq
    qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqr/wAARCAAgADADASIA
    AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA
    AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3
    ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm
    p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA
    AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx
    BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK
    U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3
    uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDoKKKK
    YgorN1f/AJY/j/SjSP8Alt+H9arl0uTza2H/ANo/9Mv/AB7/AOtV+sKt2kxQbe4VSq7RQnYtozdX
    /wCWP4/0o0j/AJbfh/WtKinzaWJ5dbmFW7RRSCMbH//Z
    """
}
