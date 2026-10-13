import UIKit
import XCTest

/// Rundgang durch die Demo: jede Ansicht einmal öffnen, ein paar Tasten drücken und Bilder
/// festhalten. Läuft im Cloud-Build auf iPhone- und iPad-Simulator; die Bilder landen im Zweig
/// ci-results.
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-demo", "-uiTesting"]
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = (isPad ? "ipad-" : "iphone-") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func open(tab label: String) {
        let button = app.tabBars.buttons[label].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            // Neuere Systeme zeigen Reiter teils ohne klassische Tab-Bar.
            app.buttons[label].firstMatch.tap()
        }
    }

    private func open(sidebar identifier: String) {
        let item = element(identifier)
        if !item.waitForExistence(timeout: 5) {
            // Hochformat: Seitenleiste ist eingeklappt.
            snap("fehlt-\(identifier)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        if item.waitForExistence(timeout: 5) { item.tap() }
    }

    /// Tippen über die Kennung; fehlt das Element, ein Bild davon, wie es aussah.
    private func tap(_ identifier: String) {
        let item = element(identifier)
        if item.waitForExistence(timeout: 5) {
            item.tap()
        } else {
            snap("fehlt-\(identifier)")
            XCTFail("\(identifier) nicht gefunden")
        }
    }

    /// Baum der Bedienelemente als Text, zum Nachsehen im Ergebnis (Zweig ci-results).
    private func dumpTree(_ name: String) {
        let started = Date()
        let tree = app.debugDescription
        let attachment = XCTAttachment(string: "Dauer \(Int(Date().timeIntervalSince(started) * 1000)) ms, \(tree.count) Zeichen\n\n" + tree)
        attachment.name = (isPad ? "ipad-" : "iphone-") + name + ".txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDemoTour() throws {
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launch()
        XCTAssertTrue(element("notbremse").waitForExistence(timeout: 20), "App startet nicht in der Demo")
        sleep(2)

        if isPad {
            snap("01-pult")
            dumpTree("baum-pult")
            open(sidebar: "nav-queue")
            sleep(1)
            snap("02-spenden")
            open(sidebar: "nav-sounds")
            sleep(1)
            snap("03-sounds")
            open(sidebar: "nav-speech")
            sleep(1)
            snap("04-sprache")
            open(sidebar: "nav-chat")
            sleep(3)
            snap("05-chat")
            open(sidebar: "nav-overview")
            sleep(2)
            snap("06-uebersicht")
            open(sidebar: "nav-stats")
            sleep(2)
            snap("07-statistik")
            open(sidebar: "nav-settings")
            sleep(1)
            snap("08-einstellungen")
        } else {
            snap("01-spenden")
            // Oberste Spende per Wischen annehmen.
            let first = app.cells.firstMatch
            if first.waitForExistence(timeout: 5) {
                first.swipeRight()
                sleep(1)
                snap("02-angenommen")
            }
            open(tab: "Sounds")
            sleep(1)
            snap("03-sounds")
            let pad = app.buttons["Applaus"].firstMatch
            if pad.waitForExistence(timeout: 3) {
                pad.tap()
                sleep(1)
            }
            open(tab: "Sprache")
            sleep(1)
            let editor = element("tts-text")
            if editor.waitForExistence(timeout: 3) {
                editor.tap()
                editor.typeText("Danke für die Spende, MaxPower!")
            }
            snap("04-sprache")
            open(tab: "Chat")
            sleep(3)
            snap("05-chat")
            open(tab: "Mehr")
            sleep(1)
            snap("06-mehr")
            tap("more-overview")
            sleep(2)
            snap("06-uebersicht")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
            tap("more-stats")
            sleep(2)
            snap("07-statistik")
        }

        // Notbremse in der Demo: Rückmeldung erscheint.
        element("notbremse").tap()
        XCTAssertTrue(element("toast").waitForExistence(timeout: 5), "Keine Rückmeldung nach der Notbremse")
        snap("09-notbremse")
    }

    func testLoginScreen() throws {
        let fresh = XCUIApplication()
        fresh.launchArguments += ["-uiTesting"]
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        fresh.launch()
        let field = fresh.descendants(matching: .any).matching(identifier: "server-field").firstMatch
        if field.waitForExistence(timeout: 10) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = (isPad ? "ipad-" : "iphone-") + "00-anmeldung"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        // Wer im Simulator schon angemeldet ist, landet direkt in der App; dann gibt es nichts zu prüfen.
    }
}
