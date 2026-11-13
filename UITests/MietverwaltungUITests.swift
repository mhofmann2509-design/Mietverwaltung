import XCTest

/// Rauchtests der Oberfläche auf dem iPhone-Simulator. Die App startet mit `-uiTesting` und
/// nutzt dann eine temporäre In-Memory-Datenbank mit Demodaten – echte Daten und iCloud bleiben
/// unberührt. Auf dem iPhone öffnet die App direkt das Dashboard („Übersicht“).
final class MietverwaltungUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testDashboardShowsKeyFiguresFromDemoData() {
        XCTAssertTrue(app.navigationBars["Übersicht"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Kaltmiete (monat)"].exists)
        XCTAssertTrue(app.buttons["1, Immobilien"].exists, "Demodaten: eine Immobilie")
    }

    func testPeriodSwitchUpdatesKeyFigures() {
        XCTAssertTrue(app.staticTexts["Kaltmiete (monat)"].waitForExistence(timeout: 15))
        app.buttons["Jahr"].tap()
        XCTAssertTrue(app.staticTexts["Kaltmiete (jahr)"].waitForExistence(timeout: 5))
        app.buttons["Quartal"].tap()
        XCTAssertTrue(app.staticTexts["Kaltmiete (quartal)"].waitForExistence(timeout: 5))
    }

    func testSidebarOpensPropertyDetail() {
        XCTAssertTrue(app.navigationBars["Übersicht"].waitForExistence(timeout: 15))
        app.navigationBars["Übersicht"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Mietverwaltung"].waitForExistence(timeout: 5), "Seitenleiste")
        XCTAssertTrue(app.staticTexts["Alle Mieter"].exists)
        app.staticTexts["Musterstraße 1"].tap()
        XCTAssertTrue(app.navigationBars["Musterstraße 1"].waitForExistence(timeout: 5), "Detailansicht der Immobilie")
    }
}
