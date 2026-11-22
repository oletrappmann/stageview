import XCTest

/// Screenshots aller Seiten und Menüs für die Abnahme. Läuft nur mit TEST_RUNNER_BILDER_ORDNER (scripts/bilder.sh) und dem
/// Vorführmodus der App (SV_DEMO, SV_DEMO_DATEI), redet also nie mit dem Server.
final class BilderTests: XCTestCase {
    private var ordner: String!
    private var daten: String!
    private var hell = true

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let ordner = env["BILDER_ORDNER"] else { throw XCTSkip("nur für scripts/bilder.sh") }
        self.ordner = ordner
        daten = env["DEMO_DATEI"] ?? ""
        hell = env["BILDER_DUNKEL"] != "1"
        continueAfterFailure = true
    }

    private func app(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SV_DEMO"] = mode
        app.launchEnvironment["SV_DEMO_DATEI"] = daten
        app.launchArguments += ["-sv.darstellung", hell ? "hell" : "dunkel", "-sv.ansicht", "alle", "-sv.sortierung", "aktiv"]
        app.launch()
        return app
    }

    private func bild(_ name: String, warten: Double = 1.2) {
        Thread.sleep(forTimeInterval: warten)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: ordner).appendingPathComponent((hell ? "" : "dunkel-") + name + ".png"))
    }

    func testBilder() {
        // Anmeldung
        var a = app("anmeldung")
        bild("01-anmeldung")
        a.buttons["zugang-tess"].tap()
        bild("02-anmeldung-passwort")
        a.terminate()

        // Startseite, Menüs
        a = app("liste")
        bild("03-links", warten: 3)
        a.swipeUp()
        bild("04-links-weiter", warten: 1.5)
        a.swipeDown(); a.swipeDown()
        a.buttons["konto"].tap()
        bild("05-menue-konto")
        a.tap(); Thread.sleep(forTimeInterval: 0.6)
        a.buttons["sortieren"].tap()
        bild("06-menue-sortieren")
        a.tap(); Thread.sleep(forTimeInterval: 0.6)
        let karte = a.otherElements.matching(identifier: "link-zskz92").firstMatch
        if karte.waitForExistence(timeout: 3) {
            karte.press(forDuration: 1.0)
            bild("07-menue-link")
        }
        a.terminate()

        a = app("kunde:lukas-doberenz")
        bild("08-kunde-gewaehlt", warten: 3)
        a.terminate()

        a = app("filter:kommentare")
        bild("09-ansicht-kommentare", warten: 3)
        a.terminate()

        a = app("meldungen")
        bild("10-meldungen", warten: 3)
        a.terminate()

        a = app("suche:penthouse")
        a.buttons["suchen"].tap()
        bild("11-suche", warten: 1.5)
        a.terminate()

        // Seite eines Links
        a = app("projekt:zskz92")
        bild("12-projekt", warten: 3)
        a.swipeUp()
        bild("13-projekt-videos", warten: 1.5)
        a.swipeUp()
        bild("14-projekt-dazu-kommentare", warten: 1.5)
        a.swipeUp(); a.swipeUp()
        bild("15-projekt-ende", warten: 1.5)
        a.terminate()

        a = app("bearbeiten:zskz92")
        bild("16-link-bearbeiten", warten: 3)
        a.terminate()

        // Player
        a = app("player:8fykkr:1:12")
        bild("17-player", warten: 5)
        a.buttons["freigabe"].firstMatch.tap()
        bild("18-player-freigabe")
        a.tap(); Thread.sleep(forTimeInterval: 0.6)
        a.buttons["player-mehr"].tap()
        bild("19-player-menue")
        a.terminate()

        a = app("player:zskz92:2")
        bild("20-player-hoch", warten: 5)
        a.swipeLeft()
        bild("21-player-gewischt", warten: 3)
        a.terminate()

        a = app("player:bh7abm:1")
        bild("22-player-quer-video", warten: 5)
        XCUIDevice.shared.orientation = .landscapeLeft
        bild("23-player-quer-gehalten", warten: 3)
        XCUIDevice.shared.orientation = .portrait
        a.terminate()

        // Neuer Link, Kunden
        a = app("neu")
        bild("24-neu-drive", warten: 2)
        a.terminate()
        a = app("neu-lauf")
        bild("25-neu-lauf", warten: 2)
        a.terminate()
        a = app("kunden")
        bild("26-kunden", warten: 2)
        a.terminate()
    }
}
