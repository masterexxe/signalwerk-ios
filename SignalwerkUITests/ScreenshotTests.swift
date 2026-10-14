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
        // Systemhinweise im Simulator (Diktierfunktion, Berechtigungen) wegklicken, statt sie
        // den Rundgang verdecken zu lassen.
        addUIInterruptionMonitor(withDescription: "Systemhinweis") { alert in
            for label in ["Not Now", "Nicht jetzt", "Don’t Allow", "Nicht erlauben", "Later", "Später"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
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

    /// Reiter unter dem Player im Arbeitsbereich (Segmente).
    private func segment(_ label: String) {
        let button = app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            snap("fehlt-reiter-\(label)")
            XCTFail("Reiter \(label) nicht gefunden")
        }
    }

    /// Menü des Players: Kanal und Anmeldung bei Twitch; dann die Anmeldeseite öffnen und wieder
    /// schließen. Die Seite kommt von twitch.tv und braucht Netz.
    private func openTwitchLogin() {
        tap("desk-player-menu")
        sleep(1)
        snap("01b-player-menue")
        let login = app.buttons["Bei Twitch anmelden"].firstMatch
        if login.waitForExistence(timeout: 3) {
            login.tap()
            twitchLoginReport()
            tap("twitch-login-cancel")
            sleep(1)
        } else {
            XCTFail("Bei Twitch anmelden fehlt im Menü")
            dismissMenu()
        }
    }

    /// Anmeldeseite von twitch.tv im Blatt: bis zu 45 Sekunden auf ein Eingabefeld warten, dann
    /// Bild, Adresse und Inhalt der Web-Ansicht festhalten. Zeigt, ob Twitch die Seite in der
    /// App anzeigt (der Cloud-Build hat Netz, aber eine Rechenzentrums-Adresse).
    private func twitchLoginReport() {
        let web = app.webViews.firstMatch
        let field = web.descendants(matching: .textField).firstMatch
        let secure = web.descendants(matching: .secureTextField).firstMatch
        let started = Date()
        var seconds = 0
        var early = false
        while seconds < 45 {
            if field.exists || secure.exists { break }
            sleep(3)
            seconds = Int(Date().timeIntervalSince(started))
            if !early && seconds >= 9 {
                early = true
                snap("01c-twitch-anmeldung-10s")
            }
        }
        snap("01c-twitch-anmeldung")
        let address = element("twitch-login-address")
        var lines = [
            "Wartezeit: \(Int(Date().timeIntervalSince(started))) s",
            "Adresse: \(address.exists ? address.label : "–")",
            "Eingabefeld: \(field.exists ? "ja" : "nein"), Passwortfeld: \(secure.exists ? "ja" : "nein")",
            "",
        ]
        lines.append(web.exists ? web.debugDescription : "Keine Web-Ansicht gefunden.")
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = (isPad ? "ipad-" : "iphone-") + "01c-twitch-anmeldung.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Offenes Menü schließen: links neben das Menü tippen (in den Player).
    private func dismissMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.22)).tap()
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

    /// Antwortet die App? Dauer einer einfachen Abfrage in Abständen, als Anhang. Bleibt die App
    /// hängen, sieht man hier, ab wann.
    private func probe(_ name: String, rounds: Int, pause: UInt32) {
        var lines: [String] = []
        let start = Date()
        for round in 0..<rounds {
            let started = Date()
            let found = app.buttons["notbremse"].exists
            let millis = Int(Date().timeIntervalSince(started) * 1000)
            lines.append("t+\(Int(started.timeIntervalSince(start)))s: \(millis) ms, Notbremse \(found ? "da" : "fehlt")")
            if round < rounds - 1 { sleep(pause) }
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = (isPad ? "ipad-" : "iphone-") + name + ".txt"
        attachment.lifetime = .keepAlways
        add(attachment)
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
            snap("01-arbeitsbereich")
            segment("Sounds")
            sleep(1)
            snap("01b-arbeitsbereich-sounds")
            openTwitchLogin()
            open(sidebar: "nav-pult")
            sleep(2)
            snap("02-pult")
            probe("antwortzeiten-pult", rounds: 4, pause: 5)
            open(sidebar: "nav-queue")
            sleep(1)
            snap("03-spenden")
            open(sidebar: "nav-sounds")
            sleep(1)
            snap("04-sounds")
            open(sidebar: "nav-speech")
            sleep(1)
            snap("05-sprache")
            open(sidebar: "nav-chat")
            sleep(3)
            snap("06-chat")
            open(sidebar: "nav-overview")
            sleep(2)
            snap("07-uebersicht")
            open(sidebar: "nav-stats")
            sleep(2)
            snap("08-statistik")
            open(sidebar: "nav-settings")
            sleep(1)
            snap("09-einstellungen")
        } else {
            // Arbeitsbereich: Player oben (in der Demo ein Hinweis), darunter die Reiter.
            snap("01-arbeitsbereich")
            openTwitchLogin()
            // Oberste Spende per Wischen annehmen.
            let first = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-row-")).firstMatch
            if first.waitForExistence(timeout: 5) {
                first.swipeRight()
                sleep(1)
                snap("02-angenommen")
            }
            segment("Sounds")
            sleep(1)
            snap("03-sounds")
            let pad = app.buttons["Applaus"].firstMatch
            if pad.waitForExistence(timeout: 3) {
                pad.tap()
                sleep(1)
            }
            segment("TTS")
            sleep(1)
            // Kein Tippen: Die Tastatur ruft im Simulator den Hinweis zur Diktierfunktion auf.
            snap("04-tts")
            segment("Live-Voice")
            sleep(1)
            snap("05-live-voice")
            tap("desk-player-toggle")
            sleep(1)
            snap("06-player-eingeklappt")
            tap("desk-player-toggle")
            open(tab: "Chat")
            sleep(3)
            snap("07-chat")
            open(tab: "Übersicht")
            sleep(2)
            snap("08-uebersicht")
            open(tab: "Mehr")
            sleep(1)
            tap("more-stats")
            sleep(2)
            snap("09-statistik")
            // Zurück zu „Mehr“ und in die Einstellungen (Twitch im Player).
            let back = app.navigationBars["Statistik"].buttons["BackButton"]
            if back.waitForExistence(timeout: 3) { back.tap() }
            sleep(1)
            tap("more-settings")
            sleep(1)
            snap("09b-einstellungen")
        }

        // Notbremse in der Demo: Rückmeldung erscheint.
        element("notbremse").tap()
        XCTAssertTrue(element("toast").waitForExistence(timeout: 5), "Keine Rückmeldung nach der Notbremse")
        snap("10-notbremse")
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
