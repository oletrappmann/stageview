#!/bin/sh
# StageView Spiegel auf GitHub (seit 16.11.2026, Ole: „StageView als Backup bei GitHub speichern, spiegeln“).
# Läuft auf VPS 2 als hermes, jede Nacht 03:40 per Cron (nach tess-backup 03:15, vor der Wartung 04:00), von Hand: stageview-sichern
#
# Lesbar im Repo: Code (Engine, Seiten, Kommentar Dienst, Befehl) und Server Einstellungen (nginx, systemd).
# Nur verschlüsselt (age, derselbe Schlüssel wie das TESS Backup, privat nur im Mac Schlüsselbund TESS_BACKUP_AGE_SCHLUESSEL):
#   die Daten aus ~/.hermes/data/stageview (Projekte, Link Codes, Nummern, Kunden, Archiv, Transkripte).
# Nie dabei: Schlüssel (stageview.env mit Mux, videos-api.env mit Team Schlüssel) und die Kommentar Datenbank
#   (Oles Regel vom 13.11.2026: nie auf GitHub, auch nicht verschlüsselt. Die sichert tess-backup.sh jede Nacht lokal, 7 Tage).
# Commit nur, wenn sich etwas geändert hat. Die verschlüsselte Datei wird nur neu geschrieben, wenn sich die Daten ändern.
set -eu
H=/home/hermes
REPO=$(cat "$H/.hermes/stageview-backup-repo.txt" 2>/dev/null || echo "git@gh-stageview:oletrappmann/stageview.git")
EMPFAENGER=$(cat "$H/.hermes/stageview-backup-empfaenger.txt")
ARBEIT="$H/.hermes/data/stageview-spiegel"
LOG="$H/.hermes/logs/stageview-sichern.log"
mkdir -p "$H/.hermes/logs"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
fehler() { log "FEHLER: $*"; echo "FEHLER: $*" >&2; exit 1; }

if [ ! -d "$ARBEIT/.git" ]; then
  rm -rf "$ARBEIT"
  git clone -q "$REPO" "$ARBEIT" 2>>"$LOG" || fehler "Repo nicht erreichbar ($REPO). Deploy Key mit Schreibrecht eingetragen?"
fi
cd "$ARBEIT"
git config user.name "VPS 2 StageView"
git config user.email "stageview@vps2.invalid"
git pull -q --rebase 2>>"$LOG" || true

# ---- Code und Server, lesbar
rm -rf code server
mkdir -p code server daten
rsync -a --delete --exclude __pycache__ --exclude '*.tmp' "$H/.hermes/scripts/stageview/" code/engine/
cp -p "$H/.hermes/scripts/videos-api.py" code/videos_api.py
cp -p "$H/.local/bin/stageview" code/stageview-befehl.sh
cp -p "$H/.config/systemd/user/videos-api.service" server/videos-api.service
cp -p /etc/nginx/sites-available/videos server/nginx-videos.conf 2>/dev/null || true
crontab -l 2>/dev/null | grep -i stageview > server/crontab-stageview.txt || true
cat > README.md <<'TEXT'
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
TEXT

# ---- Daten, verschlüsselt. Feste Reihenfolge und Zeiten im Archiv, damit gleiche Daten denselben Fingerabdruck haben
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -C "$H/.hermes/data" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --exclude=stageview/kontext --exclude=stageview/auftraege --exclude=stageview/.sperre --exclude='stageview/*.log' \
  -cf "$TMP/daten.tar" stageview
STAND=$(sha256sum "$TMP/daten.tar" | cut -d' ' -f1)
if [ "$(cat daten/stand.sha256 2>/dev/null || true)" != "$STAND" ] || [ ! -f daten/stageview-daten.tar.gz.age ]; then
  gzip -n -c "$TMP/daten.tar" | age -r "$EMPFAENGER" > daten/stageview-daten.tar.gz.age
  echo "$STAND" > daten/stand.sha256
fi

# ---- Nichts Geheimes im lesbaren Teil: die echten Schlüsselwerte dürfen nirgends stehen
for datei in "$H/.hermes/stageview.env" "$H/.hermes/videos-api.env"; do
  [ -f "$datei" ] || continue
  sed -n 's/^[A-Z_]*=//p' "$datei" | tr -d '"'"'" | while read -r wert; do
    [ ${#wert} -ge 12 ] || continue
    if grep -rqF -- "$wert" code server README.md 2>/dev/null; then echo GEFUNDEN; fi
  done
done | grep -q GEFUNDEN && fehler "Schlüssel im lesbaren Teil gefunden, nichts gepusht"
# Muster zerteilt, damit dieses Skript (liegt selbst im Spiegel) sich nicht selbst findet
grep -rqE "BEGIN (OPENSSH|RSA|EC) PRIVATE"" KEY|AGE-SECRET-""KEY-1" code server 2>/dev/null && fehler "privater Schlüssel im lesbaren Teil, nichts gepusht"
[ -e code/engine/kommentare.db ] && fehler "Kommentar Datenbank im Spiegel, nichts gepusht"

# Leeres neues Repo: Zweig main
git rev-parse -q --verify HEAD >/dev/null || git symbolic-ref HEAD refs/heads/main
git add -A
if git diff --cached --quiet; then
  log "unverändert"
  exit 0
fi
git commit -q -m "StageView Stand $(date '+%F %H:%M')"
git push -q origin HEAD 2>>"$LOG" || fehler "Push fehlgeschlagen"
log "gesichert $(git rev-parse --short HEAD)"
echo "StageView gespiegelt: $(git rev-parse --short HEAD)"
