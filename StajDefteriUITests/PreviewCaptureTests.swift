import XCTest

final class PreviewCaptureTests: XCTestCase {
    @MainActor
    func test01CaptureHomeAndNewInternship() {
        let app = launchApp()
        if app.staticTexts["Henüz staj yok"].waitForExistence(timeout: 5) {
            capture("01-staj-listesi-bos")
        }
        openNewInternship(in: app)
        capture("02-yeni-staj-formu")
    }

    @MainActor
    func test02CapturePrivacy() {
        let app = launchApp()
        tap(button("Gizlilik", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Gizlilik"].waitForExistence(timeout: 8))
        capture("03-gizlilik")
    }

    @MainActor
    func test03CaptureInternshipListDetailAndEdit() {
        let app = launchApp()
        let internship = createInternship("Mavi Lab", in: app)
        capture("04-staj-listesi")
        internship.tap()
        let edit = button("Staj bilgilerini düzenle", in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        capture("05-staj-ayrintilari")
        tap(edit, in: app)
        XCTAssertTrue(app.navigationBars["Stajı düzenle"].waitForExistence(timeout: 8))
        capture("06-staji-duzenle")
    }

    @MainActor
    func test04CaptureNewDailyEntry() {
        let app = launchApp()
        createInternship("Ada Teknik", in: app).tap()
        openNewEntry(in: app)
        capture("07-yeni-gunluk-kayit")
        app.swipeUp()
        if button("Fotoğraf seç", in: app).exists {
            capture("08-gunluk-fotograf-alanlari")
        }
    }

    @MainActor
    func test05CaptureEditDailyEntry() {
        let app = launchApp()
        createInternship("Kuzey Studio", in: app).tap()
        openNewEntry(in: app)
        let sample = "Proje planlama raporunu okudum."
        enter(sample, into: app.textViews.firstMatch, in: app)
        app.navigationBars["Yeni günlük kayıt"].buttons["Kaydet"].tap()

        let entry = row(containing: "Proje planlama", in: app)
        tap(entry, in: app)
        XCTAssertTrue(app.navigationBars["Günlüğü düzenle"].waitForExistence(timeout: 8))
        capture("09-gunlugu-duzenle")
    }

    @MainActor
    func test06CaptureDOCXReady() {
        let app = launchApp()
        createInternship("Deniz Lab", in: app).tap()
        tap(button("Word belgesi oluştur", in: app), in: app)
        XCTAssertTrue(app.staticTexts["Word belgesi hazır"].waitForExistence(timeout: 12))
        capture("10-word-belgesi-hazir")
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(tr)", "-AppleLocale", "tr_TR"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Staj Defteri"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func openNewInternship(in app: XCUIApplication) {
        tap(button("Staj ekle", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Yeni staj"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func createInternship(_ workplace: String, in app: XCUIApplication) -> XCUIElement {
        openNewInternship(in: app)
        enter("Deniz Kaya", into: app.textFields["Ad soyad"], in: app)
        enter(workplace, into: app.textFields["Staj yeri"], in: app)
        app.navigationBars["Yeni staj"].buttons["Kaydet"].tap()
        return row(containing: workplace, in: app)
    }

    @MainActor
    private func openNewEntry(in app: XCUIApplication) {
        tap(button("Günlük kayıt ekle", in: app), in: app)
        XCTAssertTrue(app.navigationBars["Yeni günlük kayıt"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func button(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: title).firstMatch
    }

    @MainActor
    private func row(containing text: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let matchingButton = app.buttons.matching(predicate).firstMatch
        if matchingButton.waitForExistence(timeout: 4) { return matchingButton }
        let matchingText = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(matchingText.waitForExistence(timeout: 6))
        return matchingText
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }

    @MainActor
    private func enter(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        tap(field, in: app)
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
