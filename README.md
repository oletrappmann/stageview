# StageView Spiegel

Automatischer Spiegel von StageView (videos.stagecraft.media) von VPS 2, jede Nacht 03:40 per `stageview-sichern`.
Die Quelle für Änderungen bleibt Stagecraft OS (`plugins/stagecraft-team/skills/stagecraft-stageview`), hier nie von Hand ändern.

- `aktuell/` der neueste Stand: `code/` (Engine mit Seiten, Kommentar Dienst `videos_api.py`, Befehl `stageview`),
  `server/` (nginx, systemd, Cron), `daten/stageview-daten.tar.gz.age` (Projekte, Link Codes, Nummern, Kunden, Archiv,
  Transkripte, nur verschlüsselt)
- `versionen/<Datum_Uhrzeit>/` eine Version pro Änderung: `daten.tar.gz.age` (verschlüsselt), `code.tar.gz` (Code und Server
  zum Stand dieser Version), `stand.txt` (Fingerabdrücke). Eine neue Version entsteht nur, wenn sich Daten oder Code ändern
- `VERSIONEN.md` Liste aller Versionen
- `aktuell/app/` die StageView iPhone App (Quelltext, xcodegen Projekt `app/project.yml`), in jeder Version als `app.tar.gz`.
  Der volle Verlauf mit jedem Commit und den hochgeladenen Builds (`testflight-<Build>`) liegt im Zweig `app`.
  Quelle ist Oles Mac (`~/Documents/CLAUDE_CODE_PROJECTS/STAGECRAFT_STAGEVIEW_APP`), gespiegelt bei jedem TestFlight Upload und
  jeder Installation per Kabel

Nicht hier, mit Absicht: die Schlüssel (Mux, Team Schlüssel) und die Kommentar Datenbank (nur lokale Sicherung auf VPS 2).

## Wiederherstellen

Entschlüsseln geht nur mit dem privaten Schlüssel aus dem Mac Schlüsselbund (`TESS_BACKUP_AGE_SCHLUESSEL`, derselbe wie beim TESS Backup):

    security find-generic-password -s TESS_BACKUP_AGE_SCHLUESSEL -w > /tmp/k.txt
    age -d -i /tmp/k.txt versionen/<Version>/daten.tar.gz.age | tar -xz -C /ziel && rm /tmp/k.txt
    tar -xzf versionen/<Version>/code.tar.gz -C /ziel

Für den neuesten Stand `aktuell/daten/stageview-daten.tar.gz.age`. Dann `stageview` mit `engine/installieren.sh` aus
Stagecraft OS einspielen, die Daten nach `~/.hermes/data/stageview/` legen, Schlüssel neu eintragen
(`~/.hermes/stageview.env`, `~/.hermes/videos-api.env`) und `stageview bauen`.

App zurückholen: `git clone -b app <dieses Repo> stageview-app` (voller Verlauf), oder `tar -xzf versionen/<Version>/app.tar.gz`.
Dann im Ordner `app/`: `xcodegen`, bauen mit `scripts/iphone.sh` oder `scripts/testflight.sh` (Schlüssel aus dem Mac Schlüsselbund).
