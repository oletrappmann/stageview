# StageView App (iPhone)

Das StageView Admin Dashboard (https://videos.stagecraft.media/admin) als eigene iPhone App für das Team, mit eigenem Player. Seit 22.11.2026 im Bau (Ole: „über die App alles verwalten“). Bundle `media.stagecraft.stageview`, Team 9ZM98AMD7M, iOS 26+, nur iPhone.

**Stand 22.11.2026 (Runde 5):** Anmeldung „Dunkle Bühne“, Startseite mit Leiste unten, Wischen und Plus neben der Leiste sind abgenommen (Ole: „mir gefällt alles bisher“). Player neu wie die Videoseite am Handy (`Player/PlayerScreen.swift`: Blatt `SheetStop` zu, mitte, offen mit Höhen aus dem Inhalt, Schwung 220 ms, Gummi wie `gummi` im Web; `Player/AmbientLight.swift`: Licht aus dem Mux Storyboard). Wartet auf Oles Blick (Artifact https://claude.ai/artifact/Se633A2p7WZionUBHrxnJi). Noch nicht getestet: echte Anmeldung gegen den Server, iPhone.

## Oles Vorgaben

- **Designsprache wie die TESS App** (Glasknöpfe, Glas, Haptik, Schriften), **aber nie deren Anordnung und Struktur** (Ole, 22.11.2026: „die Startseite viel zu sehr wie die TESS App, das muss niemals“)
- **Immer dunkel**, das ist das CI von StageView (Ole, 22.11.2026). Farben wie die Videoseite im Web (`Design/Palette.swift`: Grund #121211, Flächen #1E1E1C / #2A2A27, Text #F3F2EE). Keine Darstellungsauswahl
- **Anmeldung:** nur die Profile, oben das Schriftlogo, ein grüner Verlauf, kein App Symbol in der Mitte. Gewählt: dunkle Bühne (Ole, 22.11.2026)
- **Startseite:** die neuesten Links ganz oben, kompakte Zeilen wie Konzept 2, keine großen Kacheln (Ole, 22.11.2026)
- **Seiten unten als Leiste wie iOS**, dazwischen wischen wie in der TESS App (Ole, 22.11.2026: „unbedingt die verschiedenen Seiten unten als iOS Menübar“). Neuer Link nur als Plus
- **Player wie die Videoseite am Handy** (Ole, 22.11.2026: „unbedingt so wie beim Web“, Vorlage `engine/seite/projekt.html` und `references/seite.md` im Skill `stagecraft-stageview`): Video oben mit Ambient Licht (Storyboard, 1,25 fach, weich, Deckkraft .5), darunter ein Blatt mit Griff in drei Stufen (zu: Steuerung; mitte: dazu einzeiliges Kommentarfeld, Standard; offen: Freigabe als Zeile mit Pille, Kommentare mit Alle/Offen/Erledigt, „Mehr aus …“). Griff antippen: mitte und offen hin und her, von zu auf die Mitte. Neues Video: offen geht auf mitte. Feld antippen hält das Video an. Steuerung wie im Web (Abspielen, Ton, Zeit, Zahnrad mit Tempo und Qualität, Vollbild). Vollbild ist Apples eigener Player (`Fullscreen` in `PlayerPool.swift`), auch beim Querdrehen, die App selbst bleibt hochkant (`AppDelegate.orientations`). Vorteile der App sind erwünscht (Ole: „Vorteile, die eine App hat, voll ausnutzen“): Haptik an den Stufen und Marken, Standbild beim Spulen, Nachbarn vorgeladen
- **Verknüpft mit StageView im Web** (22.11.2026): Universal Links für `/admin`, `/<code>`, `/<code>/<nr>?t=…` (nginx liefert `/.well-known/apple-app-site-association`, siehe Skill `stagecraft-stageview`, `references/technik.md`). Gleiche Form als `stageview://<code>/<nr>?t=…`. `Store.open(_:)` wartet bis nach der Anmeldung und bis die Übersicht da ist
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
    bilder.sh            Screenshots auf dem eigenen Simulator „StageView Test“ (TEST=testAlles, testStart, testPlayer, testAnmeldung, testLinks, DUNKEL=1; SV_BLATT=zu|offen für den Player)
    icon.js              App Symbol aus dem StageView Zeichen
```

## Arbeiten

- Bauen: `cd app && xcodegen && xcodebuild build -project StageView.xcodeproj -scheme StageView -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO`
- Screenshots: `scripts/bilder.sh <ordner>` (Vorführmodus `SV_DEMO`, redet nie mit dem Server). Nur der eigene Simulator „StageView Test“, nie Oles Simulatoren, danach wieder aus
- Vorführmodus: `SV_DEMO` = liste, anmeldung, kunde:<id>, filter:<…>, suche:<…>, projekt:<code>, bearbeiten:<code>, kundenseite:<id>, player:<code>:<nr>[:<s>], neu, neu-lauf, kunden, meldungen; `SV_DEMO_DATEI` = build/demo.json
- Echter Test ohne Anmeldung im Simulator: Token per `SV_TESTTOKEN` (nur Testbuild), danach das Gerät abmelden
- Git lokal, Versionen als Commits
