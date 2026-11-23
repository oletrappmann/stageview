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

    /// Kundenansicht wie videos.stagecraft.media/<code> (22.11.2026): Kategorien, YouTube Darstellung, Raster, Querformat, Hinweis
    func testKunde() {
        var a = app("kundenansicht:zskz92")
        bild("c-zskz92-1", warten: 4)
        a.swipeUp()
        bild("c-zskz92-2", warten: 1.5)
        a.swipeUp(); a.swipeUp()
        bild("c-zskz92-3", warten: 1.5)
        a.swipeDown(); a.swipeDown(); a.swipeDown(); a.swipeDown()
        Thread.sleep(forTimeInterval: 0.8)
        a.buttons["kunde-sortierung"].firstMatch.tap()
        bild("c-sortierung")
        a.terminate()

        a = app("kundenansicht:zskz92")
        Thread.sleep(forTimeInterval: 3)
        a.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        let kategorie = a.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kategorie-Hook'")).firstMatch
        if kategorie.waitForExistence(timeout: 3) { kategorie.tap() }
        bild("c-zskz92-zu", warten: 1.2)
        a.terminate()

        for code in ["bh7abm", "pcujkd", "8fykkr", "7zn3a4"] {
            a = app("kundenansicht:\(code)")
            bild("c-\(code)-1", warten: 4)
            a.swipeUp()
            bild("c-\(code)-2", warten: 1.5)
            if code == "bh7abm" { a.swipeUp(); a.swipeUp(); bild("c-\(code)-3", warten: 1.5) }
            a.terminate()
        }

        // Kachel antippen: Player über der Kundenansicht, schließen führt zurück
        a = app("kundenansicht:pcujkd")
        Thread.sleep(forTimeInterval: 3)
        a.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kachel-'")).firstMatch.tap()
        bild("c-player", warten: 4)
        a.buttons["player-schliessen"].firstMatch.tap()
        bild("c-zurueck", warten: 1.5)
        a.terminate()

        // Seite des Links (Verwaltung): der Link öffnet die Kundenansicht
        a = app("projekt:zskz92")
        Thread.sleep(forTimeInterval: 3)
        a.buttons["link-kundenansicht"].firstMatch.tap()
        bild("c-aus-verwaltung", warten: 3)
        a.terminate()
    }

    /// Widgets oben auf der Seite Links (22.11.2026): fünf Entwürfe, dazu Kommentar antippen und „Projekt anzeigen“
    func testWidgets() {
        var a: XCUIApplication
        for style in ["zahlen", "woche", "zutun", "freigabe", "stapel"] {
            a = app("liste", env: ["SV_WIDGET": style])
            bild("w-\(style)", warten: 3.5)
            if style == "stapel" {
                let stapel = a.descendants(matching: .any)["widget-stapel"].firstMatch
                stapel.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4))
                    .press(forDuration: 0.05, thenDragTo: stapel.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.4)))
                bild("w-stapel-2", warten: 1.2)
            }
            a.terminate()
        }

        // Kommentar antippen: Player mit offenem Blatt, der Kommentar hervorgehoben
        a = app("liste")
        Thread.sleep(forTimeInterval: 3)
        a.buttons["leiste-kommentare"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let kommentare = a.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'kommentar-'"))
        kommentare.element(boundBy: min(5, max(kommentare.count - 1, 0))).tap()
        bild("w-kommentar-offen", warten: 4)
        a.terminate()

        a = app("projekt:zskz92")
        bild("w-projekt-anzeigen", warten: 3)
        a.terminate()
    }

    /// Griff größer (22.11.2026): knapp über der Kante des Blatts ziehen, senkrecht auf der Zeitleiste wischen, Feld zum Bearbeiten
    func testGriff() {
        var a = app("player:zskz92:2:8")
        Thread.sleep(forTimeInterval: 5)
        let griff = a.descendants(matching: .any)["griff"].firstMatch
        let kante = griff.frame.minY
        // 10 pt über dem Griffstreifen, also über dem Blatt auf dem Video, nach oben ziehen
        let start = a.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: a.frame.midX, dy: kante - 10))
        start.press(forDuration: 0.05, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        bild("g1-ueber-kante-offen", warten: 1.5)
        // Senkrecht auf der Zeitleiste nach unten: zu
        let leiste = a.descendants(matching: .any)["zeitleiste"].firstMatch
        leiste.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        bild("g2-zeitleiste-zu", warten: 1.5)
        a.terminate()

        // Player mit Kopf (Status, offen), Menüs und Bearbeiten im Feld
        a = app("player:8fykkr:1:12", env: ["SV_BLATT": "offen"])
        bild("g3-kopf-status", warten: 5)
        a.buttons["player-link"].firstMatch.tap()
        bild("g4-link-menue", warten: 1)
        a.terminate()
        a = app("player:8fykkr:1:12")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["player-mehr"].firstMatch.tap()
        bild("g5-mehr-menue", warten: 1)
        a.terminate()
    }

    /// Nur die Startseite (grüner Verlauf prüfen)
    func testKopf() {
        let a = app("liste")
        bild("k-links", warten: 3.5)
        a.terminate()
    }

    /// Feedback statt Freigabe, Überschriften, grüner Verlauf, Wischen zum Entfernen (22.11.2026)
    func testFeedback() {
        var a = app("liste")
        bild("f1-links", warten: 3.5)
        a.swipeUp()
        bild("f1b-links-gescrollt", warten: 1.5)
        a.swipeDown()
        a.swipeLeft()
        bild("f2-kommentare", warten: 1.5)
        a.swipeLeft()
        bild("f3-kunden", warten: 1.5)
        a.terminate()
        a = app("liste", env: ["SV_WIDGET": "zahlen"])
        bild("f4-zahlen", warten: 3.5)
        a.terminate()
        a = app("projekt:u9kd8m")
        bild("f5-projekt", warten: 3)
        a.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        let zeile = a.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Makler ersetzen' AND label CONTAINS 'Zur Freigabe'")).firstMatch
        zeile.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: zeile.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)))
        bild("f6-wischen", warten: 1)
        a.terminate()
    }

    /// Timecode wie bei Frame.io (23.11.2026): im Zahnrad umstellen, Zeitmarken bildgenau, beim Schreiben ein Bild vor und zurück
    func testTimecode() {
        let a = app("player:8fykkr:1:42")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["einstellungen"].firstMatch.tap()
        bild("t1-zahnrad", warten: 0.8)
        a.buttons["e-zeit"].firstMatch.tap()
        bild("t2-zeit", warten: 0.8)
        a.buttons["zeit-timecode"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.5)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        Thread.sleep(forTimeInterval: 0.6)
        a.descendants(matching: .any)["griff"].firstMatch.tap()
        bild("t3-kommentare-timecode", warten: 1.5)
        a.textFields["kommentar-feld"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        bild("t4-schreiben", warten: 0.2)
        a.terminate()
    }

    /// Zeitmarke im offenen Kommentarfeld folgt der Abspielposition beim Spulen (23.11.2026)
    func testZeitFolgt() {
        let a = app("player:8fykkr:1:42")
        Thread.sleep(forTimeInterval: 4)
        a.textFields["kommentar-feld"].firstMatch.tap()
        bild("z1-feld-offen", warten: 1.5)
        let leiste = a.descendants(matching: .any)["zeitleiste"].firstMatch
        leiste.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: leiste.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.2)
        bild("z2-gespult", warten: 1.2)
        a.buttons["abspielen"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.3)
        a.buttons["abspielen"].firstMatch.tap()
        bild("z3-abgespielt-pausiert", warten: 1.2)
        a.terminate()
    }

    /// Freigabe pro Video und „Alle freigeben“ auf der Seite eines Links (23.11.2026)
    func testFreigabe() {
        let a = app("projekt:u9kd8m")
        Thread.sleep(forTimeInterval: 3)
        a.swipeUp()
        bild("f1-liste", warten: 1.2)
        a.buttons.matching(identifier: "freigabe-knopf").element(boundBy: 1).tap()
        bild("f2-auswahl", warten: 0.9)
        a.buttons["freigabe-freigegeben"].firstMatch.tap()
        bild("f3-geaendert", warten: 1.2)
        a.swipeDown()
        let schalter = a.switches["alle-freigeben"].firstMatch
        schalter.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        bild("f4-an", warten: 1.2)
        schalter.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        bild("f5-aus-wie-vorher", warten: 1.2)
        a.terminate()
    }

    /// Blatt im Player (23.11.2026): am Video hoch und runter wischen, an der Liste zuziehen, Kommentar schreiben
    func testBlattFilm() {
        let a = app("player:zskz92:2")
        Thread.sleep(forTimeInterval: 4)
        bild("b0-mitte", warten: 0.1)
        func zieh(_ von: CGFloat, _ nach: CGFloat, _ v: XCUIGestureVelocity = .slow) {
            a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: von))
                .press(forDuration: 0.05, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: nach)), withVelocity: v, thenHoldForDuration: 0)
        }
        zieh(0.45, 0.2)
        bild("b1-video-hoch", warten: 1.5)
        zieh(0.62, 0.95, .default)
        bild("b2-liste-runter", warten: 1.5)
        zieh(0.3, 0.55, .fast)
        bild("b3-video-runter", warten: 1.5)
        zieh(0.5, 0.3, .fast)
        bild("b4-video-hoch-schnell", warten: 1.5)
        a.textFields["kommentar-feld"].firstMatch.tap()
        bild("b5-schreiben", warten: 2)
        zieh(0.3, 0.6, .fast)
        bild("b6-nach-schreiben", warten: 1.5)
        a.terminate()
    }

    /// Zahnrad Menü wie im Web statt Apples Glasmenü (23.11.2026)
    func testZahnrad() {
        var a = app("player:zskz92:2")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["einstellungen"].firstMatch.tap()
        bild("z1-offen", warten: 0.8)
        a.buttons["e-tempo"].firstMatch.tap()
        bild("z2-tempo", warten: 0.8)
        a.buttons["tempo-1.5"].firstMatch.tap()
        bild("z3-gewaehlt", warten: 0.8)
        a.buttons["e-quali"].firstMatch.tap()
        bild("z4-qualitaet", warten: 0.8)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        bild("z5-zu", warten: 0.8)
        a.terminate()
        a = app("player:8fykkr:1")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["einstellungen"].firstMatch.tap()
        bild("z6-quer", warten: 0.8)
        a.terminate()
    }

    /// Offene Kommentare unter den Videos (23.11.2026)
    func testKommentareUnten() {
        let a = app("projekt:u9kd8m")
        bild("o1-oben", warten: 3.5)
        a.swipeUp()
        bild("o2-mitte", warten: 1.2)
        a.swipeUp()
        bild("o3-unten", warten: 1.2)
        a.terminate()
    }

    /// Grüner Verlauf ohne Kante an der Kopfleiste, „Alle gelesen“ immer über den Meldungen (23.11.2026)
    func testVerlauf() {
        var a = app("meldungen")
        bild("g1-meldungen", warten: 3.5)
        a.descendants(matching: .any)["ios-stapel"].firstMatch.tap()
        bild("g2-aufgefaechert", warten: 1.2)
        a.swipeUp()
        bild("g3-gescrollt", warten: 1.2)
        a.buttons["alle-gelesen"].firstMatch.tap()
        bild("g4-alle-gelesen", warten: 1.5)
        a.terminate()
        a = app("liste")
        bild("g5-ohne-meldungen", warten: 3.5)
        a.swipeUp()
        bild("g6-ohne-gescrollt", warten: 1.2)
        a.terminate()
    }

    /// Player geht nur übers Kreuz zu (22.11.2026, Ole): kräftig nach unten oder oben wischen bleibt im Player
    func testPlayerNurKreuz() {
        let a = app("projekt:zskz92")
        Thread.sleep(forTimeInterval: 3)
        a.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        a.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'video-'")).firstMatch.tap()
        bild("k1-player", warten: 2.5)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            .press(forDuration: 0.02, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)), withVelocity: .fast, thenHoldForDuration: 0)
        bild("k2-nach-unten-gewischt", warten: 1.5)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.02, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .fast, thenHoldForDuration: 0)
        bild("k3-von-oben-gewischt", warten: 1.5)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.02, thenDragTo: a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)), withVelocity: .fast, thenHoldForDuration: 0)
        bild("k4-nach-oben-gewischt", warten: 1.5)
        a.buttons["player-schliessen"].firstMatch.tap()
        bild("k5-kreuz", warten: 1.5)
        a.terminate()
    }

    /// Meldungen oben wie iOS Mitteilungen (22.11.2026, Ole wählte Entwurf 2): Stapel, auffächern (höchstens 5), Mehr anzeigen
    /// (je 5 mehr), wischen zeigt Löschen, ganz durchwischen löscht
    func testMeldungenIOS() {
        let a = app("meldungen")
        bild("i1-stapel", warten: 3.5)
        a.descendants(matching: .any)["ios-stapel"].firstMatch.tap()
        bild("i2-fuenf", warten: 1.2)
        a.swipeUp()
        bild("i3-mehr-knopf", warten: 1)
        a.buttons["ios-mehr"].firstMatch.tap()
        bild("i4-zehn", warten: 1.2)
        a.swipeUp()
        bild("i5-zehn-unten", warten: 1)
        a.buttons["ios-mehr"].firstMatch.tap()
        a.swipeUp()
        bild("i6-alle", warten: 1.2)
        a.swipeDown(); a.swipeDown(); a.swipeDown()
        Thread.sleep(forTimeInterval: 0.8)
        let karte = a.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Drive abgleichen: Content'")).firstMatch
        karte.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: karte.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        bild("i7-wischen", warten: 1)
        a.buttons["ios-weniger"].firstMatch.tap()
        bild("i8-wieder-stapel", warten: 1.2)
        a.terminate()
    }

    /// Ein Video groß oben, Drive abgleichen, Rückfragen in der Mitte (22.11.2026)
    func testDrive() {
        var a = app("projekt:r92rdb")
        bild("d1-einzeln", warten: 3.5)
        a.swipeUp()
        bild("d2-einzeln-unten", warten: 1.2)
        a.buttons["drive-abgleichen"].firstMatch.tap()
        bild("d3-drive-hinweis", warten: 0.9)
        a.buttons["link-loeschen"].firstMatch.tap()
        bild("d4-rueckfrage-link", warten: 0.8)
        a.buttons["rueckfrage-nein"].firstMatch.tap()
        bild("d4b-zu", warten: 0.8)
        a.swipeDown()
        Thread.sleep(forTimeInterval: 0.6)
        a.buttons["einzelvideo-mehr"].firstMatch.tap()
        bild("d4c-video-menue", warten: 1)
        a.terminate()
        a = app("projekt:edzwtd")
        Thread.sleep(forTimeInterval: 3)
        a.swipeUp()
        bild("d5-ausgeblendet", warten: 1.2)
        a.terminate()
        a = app("projekt:8s9f9t")
        bild("d6-hinweis", warten: 3.5)
        a.terminate()
        a = app("projekt:zskz92")
        Thread.sleep(forTimeInterval: 3)
        a.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        let zeile = a.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'video-'")).firstMatch
        zeile.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.8)
        a.buttons["Von der Seite nehmen"].firstMatch.tap()
        bild("d7-rueckfrage-video", warten: 0.8)
        a.terminate()
        a = app("liste")
        Thread.sleep(forTimeInterval: 3)
        let karte = a.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'zeile-'")).firstMatch
        karte.press(forDuration: 1.0)
        bild("d8-link-menue", warten: 1)
        a.terminate()
    }

    /// Link aus einer Mitteilung (22.11.2026): ?k= öffnet den Player mit dem Kommentar hervorgehoben
    func testMitteilungsLink() {
        let a = app("liste")
        Thread.sleep(forTimeInterval: 3)
        // Kommentar 10 im Vorführstand: Jonas bei 3:14
        a.open(URL(string: "stageview://8fykkr/1?k=10&t=194")!)
        bild("p-mitteilung-link", warten: 5)
        a.terminate()
    }

    /// Teilen Fenster wie im Web (22.11.2026): im Player mit „Ab 0:12 starten“, Kopiert, und in der Kundenansicht
    func testTeilen() {
        var a = app("player:8fykkr:1:12")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["player-link"].firstMatch.tap()
        bild("s1-teilen-player", warten: 1)
        a.buttons["teilen-ab-stelle"].firstMatch.tap()
        a.buttons["teilen-kopieren"].firstMatch.tap()
        bild("s2-kopiert", warten: 0.5)
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        bild("s3-geschlossen", warten: 1)
        a.terminate()
        a = app("kundenansicht:zskz92")
        Thread.sleep(forTimeInterval: 3)
        a.buttons["kunde-teilen"].firstMatch.tap()
        bild("s4-teilen-kunde", warten: 1)
        a.terminate()
    }

    /// Neu seit dem letzten Blick (22.11.2026): Punkte an Links und Kommentaren, Zahl am Tab nur Neues
    func testNeu() {
        var a = app("liste", env: ["SV_GESEHEN": "2026-11-16T12:00"])
        bild("n-links", warten: 3.5)
        a.terminate()
        a = app("liste", env: ["SV_GESEHEN": "2026-11-15"])
        Thread.sleep(forTimeInterval: 3)
        a.buttons.matching(NSPredicate(format: "identifier == 'leiste-kommentare'")).firstMatch.tap()
        bild("n-kommentare", warten: 1.5)
        a.terminate()
    }

    /// Meldungen oben auf der Startseite und Hinweis im Player (22.11.2026, aus dem Review)
    func testMeldungen() {
        var a = app("meldungen")
        bild("m-meldungen", warten: 3)
        a.terminate()
        a = app("player:zskz92:2:8")
        Thread.sleep(forTimeInterval: 4)
        a.buttons["player-link"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.8)
        a.buttons["Link kopieren"].firstMatch.tap()
        bild("m-hinweis-player", warten: 0.6)
        a.terminate()
    }

    /// Nur gemischte Formate (Querformat in der Hochkant Kachel)
    func testKundeGemischt() {
        let a = app("kundenansicht:7zn3a4")
        bild("c-7zn3a4-1", warten: 4)
        a.terminate()
    }

    /// Links von außen: stageview://<code> öffnet die Kundenansicht, stageview://<code>/<nr>?t=… den Player an der Stelle darüber
    /// (gleich wie videos.stagecraft.media/<code>/<nr>?t=… als Universal Link auf dem iPhone)
    func testLinks() {
        let a = app("liste")
        Thread.sleep(forTimeInterval: 2.5)
        a.open(URL(string: "stageview://zskz92")!)
        bild("l1-link-projekt", warten: 3)
        a.open(URL(string: "stageview://8fykkr/1?t=30")!)
        bild("l2-link-video-zeit", warten: 5)
        a.buttons["player-schliessen"].firstMatch.tap()
        bild("l3-nach-player", warten: 2)
        a.terminate()
    }

    func testAlles() {
        testAnmeldung()
        testStart()
        testKunde()
        testPlayer()
        testLinks()
        testBilder()
    }
}
