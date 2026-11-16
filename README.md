# StageView Spiegel

Automatischer Spiegel von StageView (videos.stagecraft.media) von VPS 2, jede Nacht 03:40 per `stageview-sichern`.
Die Quelle für Änderungen bleibt Stagecraft OS (`plugins/stagecraft-team/skills/stagecraft-stageview`), hier nie von Hand ändern.

- `code/` Engine mit Seiten (`code/engine`), Kommentar Dienst (`videos_api.py`), Befehl `stageview`
- `server/` nginx Seite, systemd Dienst, Cron Zeile
- `daten/stageview-daten.tar.gz.age` Projekte, Link Codes, Nummern, Kunden, Archiv, Transkripte, nur verschlüsselt.
  `daten/stand.sha256` ist der Fingerabdruck des unverschlüsselten Archivs

Nicht hier, mit Absicht: die Schlüssel (Mux, Team Schlüssel) und die Kommentar Datenbank (nur lokale Sicherung auf VPS 2).

## Wiederherstellen

Entschlüsseln geht nur mit dem privaten Schlüssel aus dem Mac Schlüsselbund (`TESS_BACKUP_AGE_SCHLUESSEL`, derselbe wie beim TESS Backup):

    security find-generic-password -s TESS_BACKUP_AGE_SCHLUESSEL -w > /tmp/k.txt
    age -d -i /tmp/k.txt daten/stageview-daten.tar.gz.age | tar -xz -C /ziel && rm /tmp/k.txt

Dann `stageview` mit `engine/installieren.sh` aus Stagecraft OS einspielen, die Daten nach `~/.hermes/data/stageview/` legen,
Schlüssel neu eintragen (`~/.hermes/stageview.env`, `~/.hermes/videos-api.env`) und `stageview bauen`.
