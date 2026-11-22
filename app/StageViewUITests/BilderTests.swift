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

    private func app(_ mode: String, env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SV_DEMO"] = mode
        for (key, value) in env { app.launchEnvironment[key] = value }
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

    /// Seiten, die gleich bleiben: Seite eines Links, Neuer Link, Kunden (Startseite, Player, Anmeldung: eigene Tests)
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

    /// Startseite (22.11.2026): Links, Kommentare, Kunden mit Leiste unten und Wischen, Plus neben der Leiste
    func testStart() {
        var a = app("liste")
        bild("t-daneben-links", warten: 3.5)
        a.swipeLeft()
        bild("t-daneben-kommentare", warten: 1.5)
        a.swipeLeft()
        bild("t-daneben-kunden", warten: 1.5)
        a.terminate()
        a = app("kundenseite:lukas-doberenz")
        bild("t-kundenseite", warten: 3.5)
        a.terminate()
    }

    /// Player wie die Videoseite am Handy (22.11.2026): Blatt in drei Stufen, Ambient Licht, Feld, Mehr aus, Zahnrad, Vollbild
    func testPlayer() {
        // Hochkant Video, Blatt auf der Mitte
        var a = app("player:zskz92:2:8")
        bild("v1-mitte", warten: 6)
        let griff = a.descendants(matching: .any)["griff"].firstMatch
        // Am Griff nach oben ziehen: offen
        griff.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        bild("v2-offen", warten: 1.5)
        // Ganz nach unten ziehen: zu, Video am größten
        griff.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        bild("v3-zu", warten: 1.5)
        // Griff antippen: von zu zurück auf die Mitte. Dann Feld antippen: groß mit Zeitmarke und Senden, Video hält an
        griff.tap()
        bild("v3b-griff-mitte", warten: 1.2)
        a.descendants(matching: .any)["kommentar-feld"].firstMatch.tap()
        bild("v4-feld", warten: 1.5)
        a.terminate()

        // Querformat Video mit Kommentaren
        a = app("player:8fykkr:1:12")
        bild("v5-quer", warten: 6)
        a.terminate()
        a = app("player:8fykkr:1:12", env: ["SV_BLATT": "offen"])
        bild("v6-quer-offen", warten: 6)
        a.swipeUp(); a.swipeUp(); a.swipeUp(); a.swipeUp()
        bild("v7-mehr-aus", warten: 1.5)
        a.terminate()

        // Zahnrad und Vollbild
        a = app("player:8fykkr:1:70")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["einstellungen"].firstMatch.tap()
        bild("v8-zahnrad")
        a.terminate()
        a = app("player:8fykkr:1:12")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["vollbild"].firstMatch.tap()
        bild("v9-vollbild", warten: 4)
        XCUIDevice.shared.orientation = .landscapeLeft
        bild("v10-vollbild-quer", warten: 3)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        let zu = a.buttons.matching(NSPredicate(format: "label IN %@", ["Schließen", "Close", "Fertig", "Done"])).firstMatch
        if zu.waitForExistence(timeout: 3) { zu.tap() }
        bild("v11-nach-vollbild", warten: 2)
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
