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

    private func app(_ mode: String, plus: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SV_DEMO"] = mode
        if let plus { app.launchEnvironment["SV_PLUS"] = plus }
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

    /// Startseite (22.11.2026): Links, Kommentare, Kunden mit Leiste unten und Wischen, drei Plätze für das Plus
    func testStart() {
        var a = app("liste", plus: "daneben")
        bild("t-daneben-links", warten: 3.5)
        a.swipeUp()
        bild("t-daneben-gescrollt", warten: 1.5)
        a.swipeDown(); a.swipeDown()
        Thread.sleep(forTimeInterval: 0.8)
        a.swipeLeft()
        bild("t-daneben-kommentare", warten: 1.5)
        a.swipeLeft()
        bild("t-daneben-kunden", warten: 1.5)
        a.buttons["leiste-links"].firstMatch.tap()
        bild("t-daneben-zurueck", warten: 1.5)
        a.buttons["filter-menue"].firstMatch.tap()
        bild("t-daneben-filter")
        a.terminate()
        a = app("liste", plus: "daneben")
        Thread.sleep(forTimeInterval: 3)
        for _ in 0..<6 { a.swipeUp() }
        bild("t-daneben-ende", warten: 2)
        a.terminate()

        for plus in ["oben", "darueber"] {
            a = app("liste", plus: plus)
            bild("t-\(plus)-links", warten: 3.5)
            a.buttons["leiste-kommentare"].firstMatch.tap()
            bild("t-\(plus)-kommentare", warten: 1.5)
            a.terminate()
        }

        // Seite eines Kunden
        a = app("kundenseite:lukas-doberenz")
        bild("t-kundenseite", warten: 3.5)
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
        let a = app("liste")
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
