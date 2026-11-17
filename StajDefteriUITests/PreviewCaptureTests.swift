import XCTest

final class PreviewCaptureTests: XCTestCase {
    @MainActor
    func testCaptureJournalScreens() {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Henüz staj yok"].waitForExistence(timeout: 15))
        capture("01-staj-listesi-bos")

        let addInternship = app.buttons.matching(identifier: "Staj ekle").firstMatch
        XCTAssertTrue(addInternship.waitForExistence(timeout: 5))
        addInternship.tap()

        XCTAssertTrue(app.navigationBars["Yeni staj"].waitForExistence(timeout: 5))
        capture("02-yeni-staj-formu")

        enter("Deniz Kaya", into: app.textFields["Ad soyad"], in: app)
        enter("Mavi Lab", into: app.textFields["Staj yeri"], in: app)
        app.navigationBars["Yeni staj"].buttons["Kaydet"].tap()

        let internshipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mavi Lab")).firstMatch
        let internshipText = app.staticTexts["Mavi Lab"]
        let internship = internshipButton.waitForExistence(timeout: 6) ? internshipButton : internshipText
        XCTAssertTrue(internship.waitForExistence(timeout: 6))
        capture("03-staj-listesi")

        internship.tap()
        let addEntry = app.buttons["Günlük kayıt ekle"]
        XCTAssertTrue(addEntry.waitForExistence(timeout: 8))
        capture("04-staj-ayrintilari")

        addEntry.tap()
        XCTAssertTrue(app.navigationBars["Yeni günlük kayıt"].waitForExistence(timeout: 5))
        capture("05-gunluk-kayit-formu")
    }

    @MainActor
    private func enter(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 where !field.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
