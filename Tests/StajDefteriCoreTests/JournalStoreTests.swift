import Foundation
import XCTest
@testable import StajDefteriCore

final class JournalStoreTests: XCTestCase {
    func testEditedEntriesAndPhotoCaptionsSurviveReopening() async throws {
        let directory = temporaryJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(directory: directory)
        let internship = Internship(studentName: "İpek Çelik", workplace: "Atölye")
        let originalPhoto = JournalPhoto(caption: "İlk açıklama")
        let originalPhotoData = Data([1, 2, 3])
        let entry = JournalEntry(work: "Ölçüm yaptım", method: "Cetvel kullandım", photos: [originalPhoto])
        try await store.saveInternship(internship)
        try await store.saveEntry(entry, internshipID: internship.id, newPhotos: [originalPhoto.id: originalPhotoData])

        let reopened = JournalStore(directory: directory)
        let original = try await reopened.exportSnapshot(internshipID: internship.id)
        XCTAssertEqual(original.internship.entries, [entry])
        XCTAssertEqual(original.photoData, [originalPhoto.id: originalPhotoData])

        var editedInternship = internship
        editedInternship.workplace = "İmalat Atölyesi"
        try await reopened.saveInternship(editedInternship)
        var edited = entry
        edited.date = try XCTUnwrap(LocalDate(year: 2026, month: 11, day: 17))
        edited.result = "Ölçüleri tabloya aldım"
        edited.learning = "Ölçüm hatasını hesapladım"
        edited.photos[0].caption = "Ölçüm tablosu"
        let removablePhoto = JournalPhoto(caption: "İkinci fotoğraf")
        edited.photos.append(removablePhoto)
        try await reopened.saveEntry(edited, internshipID: internship.id, newPhotos: [removablePhoto.id: Data([4, 5])])

        let reloaded = JournalStore(directory: directory)
        let updated = try await reloaded.exportSnapshot(internshipID: internship.id)
        XCTAssertEqual(updated.internship.workplace, "İmalat Atölyesi")
        XCTAssertEqual(updated.internship.entries, [edited])
        XCTAssertEqual(updated.photoData[originalPhoto.id], originalPhotoData)

        edited.photos.removeLast()
        try await reloaded.saveEntry(edited, internshipID: internship.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL(removablePhoto.id, in: directory).path))
        let retainedPhotoData = try await reloaded.photoData(id: originalPhoto.id)
        XCTAssertEqual(retainedPhotoData, originalPhotoData)
    }

    func testDeletingEntryAndInternshipRemovesDataAndOnlyTheirPhotos() async throws {
        let directory = temporaryJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(directory: directory)
        let first = Internship(workplace: "Birinci staj")
        let second = Internship(workplace: "İkinci staj")
        let photo = JournalPhoto()
        let otherPhoto = JournalPhoto()
        let firstEntry = JournalEntry(photos: [photo])
        let secondEntry = JournalEntry(photos: [otherPhoto])

        try await store.saveInternship(first)
        try await store.saveInternship(second)
        try await store.saveEntry(firstEntry, internshipID: first.id, newPhotos: [photo.id: Data([1])])
        try await store.saveEntry(secondEntry, internshipID: second.id, newPhotos: [otherPhoto.id: Data([2])])
        try await store.deleteEntry(id: firstEntry.id, internshipID: first.id)

        let reopened = JournalStore(directory: directory)
        let internships = try await reopened.load()
        XCTAssertTrue(internships[0].entries.isEmpty)
        XCTAssertEqual(internships[1].entries, [secondEntry])
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL(photo.id, in: directory).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoURL(otherPhoto.id, in: directory).path))

        try await reopened.deleteInternship(id: second.id)
        let remaining = try await JournalStore(directory: directory).load()
        XCTAssertEqual(remaining, [first])
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL(otherPhoto.id, in: directory).path))
    }

    func testCannotSaveTwoEntriesOnTheSameDayOrLoseDataOnAWriteFailure() async throws {
        let directory = temporaryJournalDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(directory: directory)
        let internship = Internship()
        let day = try XCTUnwrap(LocalDate(year: 2026, month: 11, day: 17))
        let first = JournalEntry(date: day, work: "İlk kayıt")
        let otherDay = try XCTUnwrap(LocalDate(year: 2026, month: 11, day: 18))
        let photo = JournalPhoto()
        let second = JournalEntry(date: otherDay, work: "Ertesi sabah", photos: [photo])
        try await store.saveInternship(internship)
        try await store.saveEntry(first, internshipID: internship.id)

        do {
            try await store.saveEntry(JournalEntry(date: day), internshipID: internship.id)
            XCTFail("A second entry for the same calendar day was accepted.")
        } catch {
            XCTAssertEqual(error as? JournalStoreError, .duplicateEntryDate)
        }

        let blockedPhotoDirectory = directory.appendingPathComponent("photos")
        try Data([0]).write(to: blockedPhotoDirectory)
        do {
            try await store.saveEntry(second, internshipID: internship.id, newPhotos: [photo.id: Data([8])])
            XCTFail("The photo could not have been written to the blocked location.")
        } catch {
            XCTAssertEqual(error as? JournalStoreError, .writeFailed)
        }
        let afterFailure = try await store.load()
        XCTAssertEqual(afterFailure.first?.entries, [first])

        try FileManager.default.removeItem(at: blockedPhotoDirectory)
        let afterRetry = try await store.saveEntry(second, internshipID: internship.id, newPhotos: [photo.id: Data([8])])
        XCTAssertEqual(afterRetry.first?.entries, [first, second])
    }

    func testCalendarDayRoundTripsWithoutDependingOnTimeZone() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-17T21:30:00Z"))
        let istanbul = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let day = LocalDate(instant, timeZone: istanbul)
        XCTAssertEqual(day.iso8601, "2026-11-18")
        XCTAssertEqual(LocalDate(day.date), day)
        let encoded = try JSONEncoder().encode(day)
        XCTAssertEqual(try JSONDecoder().decode(LocalDate.self, from: encoded), day)
        XCTAssertNil(LocalDate(year: 2026, month: 2, day: 29))
    }

    private func temporaryJournalDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func photoURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("photos").appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
    }
}
