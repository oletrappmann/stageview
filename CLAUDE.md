# StageView App (iPhone)

Das StageView Admin Dashboard (https://videos.stagecraft.media/admin) als eigene iPhone App für das Team, mit eigenem Player. Seit 22.11.2026 im Bau (Ole: „über die App alles verwalten“). Bundle `media.stagecraft.stageview`, Team 9ZM98AMD7M, iOS 26+, nur iPhone.

**Stand 22.11.2026 spät:** Anmeldung, Startseite, Player, Kundenansicht gebaut und auf Oles iPhone (`scripts/iphone.sh`). Review der Bedienbarkeit in `docs/review-2026-11-22.md`, Quick wins und „Neu seit dem letzten Blick“ (`Model/Seen.swift`) umgesetzt. Griff im Player größer (Ole: „für den Daumen“), Zeitleiste zieht senkrecht das Blatt. Offen bei Ole (Artifact https://claude.ai/artifact/Se633A2p7WZionUBHrxnJi): Widgets oben auf der Seite Links (`SV_WIDGET` zahlen, woche, zutun, freigabe, stapel; ohne Wahl nichts), ob ein Tipp auf eine Zeile der Startseite direkt die Kundenansicht öffnet. Noch offen: Oles Test der Links aus WhatsApp, Notizen, TESS App.

## Oles Vorgaben

- **Designsprache wie die TESS App** (Glasknöpfe, Glas, Haptik, Schriften), **aber nie deren Anordnung und Struktur** (Ole, 22.11.2026: „die Startseite viel zu sehr wie die TESS App, das muss niemals“)
- **Immer dunkel**, das ist das CI von StageView (Ole, 22.11.2026). Farben wie die Videoseite im Web (`Design/Palette.swift`: Grund #121211, Flächen #1E1E1C / #2A2A27, Text #F3F2EE). Keine Darstellungsauswahl
- **Anmeldung:** nur die Profile, oben das Schriftlogo, ein grüner Verlauf, kein App Symbol in der Mitte. Gewählt: dunkle Bühne (Ole, 22.11.2026)
- **Startseite:** die neuesten Links ganz oben, kompakte Zeilen wie Konzept 2, keine großen Kacheln (Ole, 22.11.2026)
- **Seiten unten als Leiste wie iOS**, dazwischen wischen wie in der TESS App (Ole, 22.11.2026: „unbedingt die verschiedenen Seiten unten als iOS Menübar“). Neuer Link nur als Plus
- **Player wie die Videoseite am Handy** (Ole, 22.11.2026: „unbedingt so wie beim Web“, Vorlage `engine/seite/projekt.html` und `references/seite.md` im Skill `stagecraft-stageview`): Video oben mit Ambient Licht (Storyboard, 1,25 fach, weich, Deckkraft .5), darunter ein Blatt mit Griff in drei Stufen (zu: Steuerung; mitte: dazu einzeiliges Kommentarfeld, Standard; offen: Freigabe als Zeile mit Pille, Kommentare mit Alle/Offen/Erledigt, „Mehr aus …“). Griff antippen: mitte und offen hin und her, von zu auf die Mitte. Neues Video: offen geht auf mitte. Feld antippen hält das Video an. Steuerung wie im Web (Abspielen, Ton, Zeit, Zahnrad mit Tempo und Qualität, Vollbild). Vollbild ist Apples eigener Player (`Fullscreen` in `PlayerPool.swift`), auch beim Querdrehen, die App selbst bleibt hochkant (`AppDelegate.orientations`). Vorteile der App sind erwünscht (Ole: „Vorteile, die eine App hat, voll ausnutzen“): Haptik an den Stufen und Marken, Standbild beim Spulen, Nachbarn vorgeladen
- **Kundenansicht wie im Web** (22.11.2026, Ole: „Projektlinks mit mehreren Videos in der App in der Client View öffnen, nicht nur in der Admin View, auch wenn man den Link aus dem Web öffnet“): `Views/ClientPage.swift` baut die Übersicht von videos.stagecraft.media/<code> nach (Vorlage `projekt.html`, `uebersichtZeichnen`, `references/seite.md`): grüner Verlauf, Kunde · Firma, Titel, Freigabe als Striche, Hinweis, Sortierung (gemerkt pro Gerät), Kacheln 3:4, nur Querformat 16:9 eine pro Reihe, Querformat in der Hochkant Kachel ganz mit weichem Hintergrund, Kategorien zum Einklappen, Darstellung YouTube. Kategorien und ihre Reihenfolge stehen nur in der öffentlichen `projekt.json` (`Model/ClientLayout.swift` lädt sie), Videos, Status und Kommentare aus der Übersicht bzw. dem ReviewStore. Links von außen und „Ansehen“ bzw. der Link auf der Seite eines Links öffnen die Kundenansicht (Route `.client`), oben rechts „Verwalten“ führt zur Seite des Links. Tipp auf eine Zeile der Startseite öffnet weiter die Verwaltung, langes Drücken bietet „Kundenansicht“
- **Verknüpft mit StageView im Web** (22.11.2026, Ole: „StageView Links in der App öffnen wie im Web“): Universal Links für `/admin`, `/<code>` (Kundenansicht), `/<code>/<nr>?t=…` (Player über der Kundenansicht) und die alte Form `/<name>-<code>` (nginx liefert `/.well-known/apple-app-site-association`, siehe Skill `stagecraft-stageview`, `references/technik.md`). Gleiche Form als `stageview://<code>/<nr>?t=…`. `Store.open(_:)` wartet bis nach der Anmeldung und bis die Übersicht da ist. In der App: ein Link in der Suche öffnet direkt (`Store.openLink(in:)`), Links in Kommentaren sind antippbar, StageView Links darin öffnen in der App (`LinkedText`, `Store.isStageViewLink`). Geht nur signiert auf dem iPhone, nicht im Simulator. Tippt man einen Link in Safari auf videos.stagecraft.media selbst, bleibt iOS in Safari (lange drücken: „In StageView öffnen“)
- **Feedback statt Freigabe Zahl** (Ole, 22.11.2026: „in der App und im Admin die Zahl entfernen, wie viele Videos freigegeben sind, was Brauchbares hin“): Zeilen zeigen rechts offene Kommentare, „erledigt“ oder „kein Feedback“ (`FeedbackMark`), die Seite eines Links „x von y Kommentaren erledigt“. Die Kundenansicht bleibt wie die Kundenseite im Web (dort steht die Freigabe weiter)
- **Seitenüberschrift auf jeder Seite** („Alle Links“, „Kommentare“, „Kunden“, `PageHeading`), oben ein grüner Verlauf hinter dem Kopf (`StartTopBar`, `HeroGlow`)
- **Videos per Wischen entfernen** auf der Seite eines Links (`SwipeReveal` in GlassParts, mit Rückfrage)
- **Mitteilungen bei neuen Kommentaren** (Ole, 22.11.2026: „10 Minuten warten, alles innerhalb gebündelt als eine Mitteilung“): Bündelung im Server (`videos_api.py`, `push_runde`, siehe Skill `references/technik.md`), die App fragt nach der Erlaubnis, meldet ihre Kennung (`App/Push.swift`, `POST /api/admin/push`, Umgebung aus `embedded.mobileprovision`), Abmelden meldet ab, Antippen öffnet `/<code>/<nr>?k=<id>&t=<s>` (Player mit dem Kommentar). Entitlement `aps-environment: development` für `scripts/iphone.sh`
- **Ein Video groß** (Ole, 22.11.2026: „wenn es ein einzelnes Video in einem Projekt ist, oben das Video Thumbnail in groß, dann Link öffnen, in Safari etc“): Links mit genau einem Video zeigen auf ihrer Seite das Video groß in der Link Karte (Hochkant im 4:5 Rahmen mit Licht aus der Bildmitte), Tipp spielt, ⋯ und langes Drücken haben alles aus der Videozeile, darunter „Link öffnen“ (Kundenansicht), Kopieren, Teilen, Safari. Die Videoliste fällt dann weg
- **Rückfragen in der Mitte** (Ole, 22.11.2026: „nicht so komisch auf dem Bildschirm verteilt“): nie `confirmationDialog`, immer `.centerConfirm` (`Views/ConfirmDialog.swift`, Stil wie das Teilen Fenster, durchsichtiges Vollbild ohne Apples Hochfahren, `fullScreenCover(item:)`, mit `isPresented` blieb es schwarz). Titel ändern bleibt Apples Alert
- **Drive abgleichen** (Ole, 22.11.2026): Knopf auf der Seite eines Links und im Menü jedes Links (`Store.syncDrive`, Auftrag `POST admin/projekt/<code>/drive`, Ergebnis als Hinweis, wenn er fertig ist). Was nicht mehr im Drive liegt, blendet der Server alle 5 Minuten selbst aus (Skill `references/technik.md`, Drive Abgleich), die Seite zeigt die ausgeblendeten Titel und `drive_hinweis`
- **Meldungen oben wie iOS Mitteilungen** (Ole, 22.11.2026, aus drei Entwürfen Nummer 2): `Views/JobsPanel.swift`. Glas Karten mit App Symbol, Titel, Zeit, einem Satz; mehrere als Stapel, Tipp fächert auf, aufgefächert höchstens 5, „Mehr anzeigen“ holt je 5 weitere (Ole). Nach links wischen zeigt Löschen, ganz durchwischen löscht. Wischen ist eine kleine waagerechte Scrollfläche pro Karte (ein DragGesture verlor gegen das Blättern der Startseite), Einrasten mit `RevealSnap`. Fertige bleiben 24 Std (vorher 2), bis man sie wegwischt
- **Player schließt nur über den Knopf oben links** (Ole, 22.11.2026: „nicht möglich machen, dass man durch starkes Wischen nach unten oder oben aus dem Player kommt, das ist für die Kommentare, nur übers Kreuz“): `.interactiveDismissDisabled()` am fullScreenCover, sonst macht Apples Zoom Übergang beim kräftigen Wischen zu. Knopf bleibt der Pfeil wie im Web
- **Teilen wie im Web** (Ole, 22.11.2026: „beim Video kopieren Button im Videoplayer wie im Web das Popup“): `Views/ShareDialog.swift` baut das Teilen Fenster der Videoseite nach (Link ganz, „Ab 0:12 starten“, weißer Knopf „Link kopieren“, danach grün „Kopiert“, kein Teilen über Apps). Link Knopf im Player und „Teilen“ in der Kundenansicht („Alle Videos teilen“) öffnen es über `Store.share`. Link zur ganzen Seite und Safari stehen im Menü Mehr des Players
- „Made by Stagecraft“ unten auf den Seiten (Asset `MadeBy`, zugeschnitten wie in `02_Figma/Stagecraft/ci/ui-elements.md`)
- TestFlight nur auf Oles Ja

## Server

Keine eigene Schnittstelle: die App spricht dieselben Wege wie das Dashboard (`engine/server/videos_api.py` im Skill `stagecraft-stageview`):
- Anmeldung `POST /api/admin/anmelden` (Brücke der TESS App prüft Name und Passwort, Gerät heißt dort „Browser StageView iPhone App“, Telegram Hinweis an Ole). Das Token kommt als Cookie `sv_sitzung`, die App legt es in den Schlüsselbund und schickt es als Cookie Kopf mit (`Model/API.swift`)
- Verwaltung `api/admin/…` (Übersicht, Projekt, Video Titel, entfernen, löschen, dazu, neu, vorbereiten, Auftrag, Kunden)
- Kommentare und Freigabe `api/<code>/…` als Stagecraft (Rolle team), eigener Geräteschlüssel `X-Autor` aus dem Schlüsselbund
- Videos von Mux (`stream.mux.com/<id>.m3u8`, Standbilder `image.mux.com`), Qualitätsstufen aus der HLS Liste

## Aufbau

```
app/
  project.yml            xcodegen, nie die .xcodeproj von Hand
  StageView/
    App/                 Start, Navigation (Route), Haptik, AppDelegate (Drehen nur im Vollbild)
    Design/              Palette, Glas Bausteine (wie TESS), Logo, Bilder mit eigenem Speicher
    Model/               Daten (nachsichtig gelesen), API, Store (Übersicht, Filter, Aktionen, Links von außen), ReviewStore (Kommentare)
    Views/               Anmeldung, Startseite (StartPage mit Leiste und Blätterer, StartFeeds, StartParts), LinkMenu, Seite eines Links, Neuer Link, Fenster
    Player/              PlayerPool (aktuelles Video und Nachbarn vorgeladen), PlayerScreen, Zeitleiste mit Marken, Kommentare
    Demo/                Vorführung ohne Server (nur Testbuild)
  StageViewUITests/      BilderTests (Screenshots aller Seiten)
  scripts/
    demo_daten.py        echter Datenstand aus den öffentlichen Videoseiten nach build/demo.json (nicht ins Paket)
    bilder.sh            Screenshots auf dem eigenen Simulator „StageView Test“ (TEST=testAlles, testStart, testWidgets, testTeilen, testFeedback, testMitteilungsLink, testNeu, testGriff, testMeldungen, testKunde, testPlayer, testAnmeldung, testLinks, DUNKEL=1; SV_BLATT=zu|offen für den Player)
    icon.js              App Symbol aus dem StageView Zeichen
    iphone.sh            Release signiert direkt aufs verbundene iPhone (ohne TestFlight), wie bei der Regie App
```

## Arbeiten

- Bauen: `cd app && xcodegen && xcodebuild build -project StageView.xcodeproj -scheme StageView -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO`
- Screenshots: `scripts/bilder.sh <ordner>` (Vorführmodus `SV_DEMO`, redet nie mit dem Server). Nur der eigene Simulator „StageView Test“, nie Oles Simulatoren, danach wieder aus
- Vorführmodus: `SV_DEMO` = liste, anmeldung, kunde:<id>, filter:<…>, suche:<…>, projekt:<code>, bearbeiten:<code>, kundenseite:<id>, kundenansicht:<code>, player:<code>:<nr>[:<s>], neu, neu-lauf, kunden, meldungen; `SV_DEMO_DATEI` = build/demo.json
- Echter Test ohne Anmeldung im Simulator: Token per `SV_TESTTOKEN` (nur Testbuild), danach das Gerät abmelden
- Git lokal, Versionen als Commits
