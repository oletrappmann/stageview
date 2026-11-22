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

    private func app(_ mode: String, start: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SV_DEMO"] = mode
        if let start { app.launchEnvironment["SV_START"] = start }
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

    /// Seiten, die gleich bleiben: Seite eines Links, Player, Neuer Link, Kunden (Startseite und Anmeldung: testKonzepte, testAnmeldung)
    func testBilder() {
        var a: XCUIApplication
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

    /// Startseite Runde 3 (22.11.2026): vier Entwürfe auf Basis von Konzept 2, neueste Links oben, keine großen Kacheln
    func testStart() {
        // A: nur Links
        var a = app("liste", start: "liste")
        bild("s-a-liste", warten: 3.5)
        a.swipeUp()
        bild("s-a-liste-weiter", warten: 1.5)
        a.swipeDown(); a.swipeDown()
        Thread.sleep(forTimeInterval: 0.8)
        a.buttons["filter-menue"].firstMatch.tap()
        bild("s-a-filter")
        a.terminate()

        // B: Tabs oben
        a = app("liste", start: "tabs")
        bild("s-b-links", warten: 3.5)
        a.buttons["tab-kommentare"].firstMatch.tap()
        bild("s-b-kommentare", warten: 1.5)
        a.buttons["tab-kunden"].firstMatch.tap()
        bild("s-b-kunden", warten: 1.5)
        a.terminate()

        // C: Kurzwege, jeder öffnet eine eigene Seite
        a = app("liste", start: "kurzwege")
        bild("s-c-kurzwege", warten: 3.5)
        a.buttons["kurzweg-kommentare"].firstMatch.tap()
        bild("s-c-kommentare", warten: 2)
        a.terminate()
        a = app("liste", start: "kurzwege")
        Thread.sleep(forTimeInterval: 3)
        a.buttons["kurzweg-kunden"].firstMatch.tap()
        bild("s-c-kunden", warten: 2)
        a.terminate()
        a = app("liste", start: "kurzwege")
        Thread.sleep(forTimeInterval: 3)
        a.buttons["kurzweg-fertig"].firstMatch.tap()
        bild("s-c-freigegeben", warten: 2)
        a.terminate()

        // D: Leiste unten
        a = app("liste", start: "leiste")
        bild("s-d-links", warten: 3.5)
        a.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kommentare'")).firstMatch.tap()
        bild("s-d-kommentare", warten: 1.5)
        a.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kunden'")).firstMatch.tap()
        bild("s-d-kunden", warten: 1.5)
        a.terminate()

        // Seite eines Kunden, jetzt auch kompakt
        a = app("kundenseite:lukas-doberenz", start: "liste")
        bild("s-kundenseite", warten: 3.5)
        a.terminate()
    }

    /// Player mit Zahnrad und Vollbild (Runde 2, 22.11.2026)
    func testPlayer() {
        var a: XCUIApplication
        a = app("player:8fykkr:1:12")
        bild("p1-player", warten: 5)
        a.buttons["vollbild"].firstMatch.tap()
        bild("p3-vollbild", warten: 4)
        XCUIDevice.shared.orientation = .landscapeLeft
        bild("p4-vollbild-quer", warten: 3)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        let zu = a.buttons.matching(NSPredicate(format: "label IN %@", ["Schließen", "Close", "Fertig", "Done"])).firstMatch
        if zu.waitForExistence(timeout: 3) { zu.tap() }
        bild("p5-nach-vollbild", warten: 2)
        a.terminate()
        a = app("player:8fykkr:1:70")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["einstellungen"].firstMatch.tap()
        bild("p2-zahnrad")
        a.terminate()
    }

    /// Anmeldung, gewählt: dunkle Bühne (Ole, 22.11.2026)
    func testAnmeldung() {
        let a = XCUIApplication()
        a.launchEnvironment["SV_DEMO"] = "anmeldung"
        a.launch()
        bild("a-buehne", warten: 2)
        a.buttons["zugang-tess"].tap()
        bild("a-buehne-passwort", warten: 1.2)
        a.terminate()
    }

    /// Links von außen: stageview://<code> öffnet den Link, stageview://<code>/<nr>?t=… den Player an der Stelle (gleich wie
    /// videos.stagecraft.media/<code>/<nr>?t=… als Universal Link auf dem iPhone)
    func testLinks() {
        let a = app("liste", start: "liste")
        Thread.sleep(forTimeInterval: 2.5)
        a.open(URL(string: "stageview://zskz92")!)
        bild("l1-link-projekt", warten: 2.5)
        a.open(URL(string: "stageview://8fykkr/1?t=30")!)
        bild("l2-link-video-zeit", warten: 5)
        a.terminate()
    }

    func testAlles() {
        testAnmeldung()
        testStart()
        testPlayer()
        testLinks()
        testBilder()
    }
}
