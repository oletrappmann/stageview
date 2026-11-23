#!/bin/sh
# StageView Spiegel auf GitHub (seit 16.11.2026, Ole: „StageView als Backup bei GitHub speichern, spiegeln“,
# dazu „ein Backup Ordner, dass da verschiedene Versionen drin sein können“).
# Läuft auf VPS 2 als hermes, jede Nacht 03:40 per Cron (nach tess-backup 03:15, vor der Wartung 04:00), von Hand: stageview-sichern
#
# Im Repo:
#   aktuell/                 der neueste Stand. code/ und server/ lesbar, daten/ nur verschlüsselt
#   versionen/<Datum_Zeit>/  eine Version pro Änderung: daten.tar.gz.age (verschlüsselt) und code.tar.gz (Code und Server)
#   VERSIONEN.md             Liste aller Versionen, was sich geändert hat
#   aktuell/app/             seit 23.11.2026 die StageView iPhone App, lesbar (Ole: „Spiegel mit verschiedenen Backups wie bei der
#                            Web Version“). Quelle ist Oles Mac (STAGECRAFT_STAGEVIEW_APP), app/scripts/sichern.sh schiebt sie ins
#                            nackte Repo ~/.hermes/data/stageview-app.git und ruft dieses Skript sofort auf. Dazu Zweig app mit dem
#                            vollen Verlauf und den Tags testflight-<Build>
# Eine neue Version entsteht nur, wenn sich Daten oder Code wirklich geändert haben (Fingerabdruck), nicht jede Nacht.
#
# Verschlüsselt mit age (derselbe Schlüssel wie das TESS Backup, privat nur im Mac Schlüsselbund TESS_BACKUP_AGE_SCHLUESSEL):
#   die Daten aus ~/.hermes/data/stageview (Projekte, Link Codes, Nummern, Kunden, Archiv, Transkripte).
# Nie dabei: Schlüssel (stageview.env mit Mux, videos-api.env mit Team Schlüssel) und die Kommentar Datenbank
#   (Oles Regel vom 13.11.2026: nie auf GitHub, auch nicht verschlüsselt. Die sichert tess-backup.sh jede Nacht lokal, 7 Tage).
set -eu
H=/home/hermes
REPO=$(cat "$H/.hermes/stageview-backup-repo.txt" 2>/dev/null || echo "git@gh-stageview:oletrappmann/stageview.git")
EMPFAENGER=$(cat "$H/.hermes/stageview-backup-empfaenger.txt")
ARBEIT="$H/.hermes/data/stageview-spiegel"
LOG="$H/.hermes/logs/stageview-sichern.log"
mkdir -p "$H/.hermes/logs"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
fehler() { log "FEHLER: $*"; echo "FEHLER: $*" >&2; exit 1; }
# Feste Reihenfolge, Zeiten und Besitzer im Archiv: gleicher Inhalt gibt denselben Fingerabdruck und dieselben Bytes
packen() { ziel=$1; shift; tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf "$ziel" "$@"; }

if [ ! -d "$ARBEIT/.git" ]; then
  rm -rf "$ARBEIT"
  git clone -q "$REPO" "$ARBEIT" 2>>"$LOG" || fehler "Repo nicht erreichbar ($REPO). Deploy Key mit Schreibrecht eingetragen?"
fi
cd "$ARBEIT"
git config user.name "VPS 2 StageView"
git config user.email "stageview@vps2.invalid"
git pull -q --rebase 2>>"$LOG" || true
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Alte Ablage vor den Versionen (16.11.2026 mittags) lag direkt im Hauptordner
rm -rf code server daten

# ---- App: lesbar nach aktuell/app/ (nur was in Git steht, in der App steckt kein Schlüssel)
APP_GIT="$H/.hermes/data/stageview-app.git"
APP=""
if [ -d "$APP_GIT" ] && git --git-dir="$APP_GIT" rev-parse -q --verify refs/heads/main >/dev/null; then
  APP=$(git --git-dir="$APP_GIT" rev-parse refs/heads/main)
  rm -rf aktuell/app
  mkdir -p aktuell/app
  git --git-dir="$APP_GIT" archive refs/heads/main | tar -x -C aktuell/app
fi

# ---- aktuell: Code und Server, lesbar
rm -rf aktuell/code aktuell/server
mkdir -p aktuell/code aktuell/server aktuell/daten versionen
rsync -a --delete --exclude __pycache__ --exclude '*.tmp' "$H/.hermes/scripts/stageview/" aktuell/code/engine/
cp -p "$H/.hermes/scripts/videos-api.py" aktuell/code/videos_api.py
cp -p "$H/.local/bin/stageview" aktuell/code/stageview-befehl.sh
cp -p "$H/.config/systemd/user/videos-api.service" aktuell/server/videos-api.service
cp -p /etc/nginx/sites-available/videos aktuell/server/nginx-videos.conf 2>/dev/null || true
crontab -l 2>/dev/null | grep -i stageview > aktuell/server/crontab-stageview.txt || true

# ---- aktuell: Daten, verschlüsselt. Neu verschlüsselt wird nur, wenn sich die Daten ändern
tar -C "$H/.hermes/data" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --exclude=stageview/kontext --exclude=stageview/auftraege --exclude=stageview/.sperre --exclude='stageview/*.log' \
  -cf "$TMP/daten.tar" stageview
DATEN=$(sha256sum "$TMP/daten.tar" | cut -d' ' -f1)
if [ "$(cat aktuell/daten/stand.sha256 2>/dev/null || true)" != "$DATEN" ] || [ ! -f aktuell/daten/stageview-daten.tar.gz.age ]; then
  gzip -n -c "$TMP/daten.tar" | age -r "$EMPFAENGER" > aktuell/daten/stageview-daten.tar.gz.age
  echo "$DATEN" > aktuell/daten/stand.sha256
fi

# ---- Nichts Geheimes im lesbaren Teil: die echten Schlüsselwerte dürfen nirgends stehen
for datei in "$H/.hermes/stageview.env" "$H/.hermes/videos-api.env"; do
  [ -f "$datei" ] || continue
  sed -n 's/^[A-Z_]*=//p' "$datei" | tr -d '"'"'" | while read -r wert; do
    [ ${#wert} -ge 12 ] || continue
    if grep -rqF -- "$wert" aktuell/code aktuell/server aktuell/app 2>/dev/null; then echo GEFUNDEN; fi
  done
done | grep -q GEFUNDEN && fehler "Schlüssel im lesbaren Teil gefunden, nichts gepusht"
# Muster zerteilt, damit dieses Skript (liegt selbst im Spiegel) sich nicht selbst findet
grep -rqE "BEGIN (OPENSSH|RSA|EC) PRIVATE"" KEY|AGE-SECRET-""KEY-1" aktuell/code aktuell/server aktuell/app 2>/dev/null && fehler "privater Schlüssel im lesbaren Teil, nichts gepusht"
find aktuell -name 'kommentare.db*' | grep -q . && fehler "Kommentar Datenbank im Spiegel, nichts gepusht"

# ---- Version: nur wenn sich Daten oder Code seit der letzten Version geändert haben
packen "$TMP/code.tar" -C aktuell code server
CODE=$(sha256sum "$TMP/code.tar" | cut -d' ' -f1)
LETZTE_DATEN=$(sed -n 's/^daten=//p' versionen/letzte.txt 2>/dev/null || true)
LETZTE_CODE=$(sed -n 's/^code=//p' versionen/letzte.txt 2>/dev/null || true)
LETZTE_APP=$(sed -n 's/^app=//p' versionen/letzte.txt 2>/dev/null || true)
WAS=""
[ "$DATEN" != "$LETZTE_DATEN" ] && WAS="Daten"
[ "$CODE" != "$LETZTE_CODE" ] && WAS="${WAS:+$WAS, }Code"
if [ -n "$APP" ] && [ "$APP" != "$LETZTE_APP" ]; then
  WAS="${WAS:+$WAS, }App ($(git --git-dir="$APP_GIT" log -1 --format=%s refs/heads/main | cut -c1-80 | tr '|' '/'))"
fi
if [ -n "$WAS" ]; then
  STEMPEL=$(date '+%Y-%m-%d_%H%M')
  V="versionen/$STEMPEL"
  mkdir -p "$V"
  cp aktuell/daten/stageview-daten.tar.gz.age "$V/daten.tar.gz.age"
  gzip -n -c "$TMP/code.tar" > "$V/code.tar.gz"
  [ -n "$APP" ] && git --git-dir="$APP_GIT" archive --format=tar.gz -o "$V/app.tar.gz" refs/heads/main
  printf 'daten=%s\ncode=%s\napp=%s\n' "$DATEN" "$CODE" "$APP" > "$V/stand.txt"
  cp "$V/stand.txt" versionen/letzte.txt
  [ -n "$LETZTE_CODE" ] || WAS="erster Stand"
  if [ ! -f VERSIONEN.md ]; then
    printf '# StageView Versionen\n\nEine Zeile pro Version, neueste unten. Ordner in `versionen/`, Wiederherstellen siehe README.\n\n| Version | Was hat sich geändert |\n|---|---|\n' > VERSIONEN.md
  fi
  printf '| %s | %s |\n' "$STEMPEL" "$WAS" >> VERSIONEN.md
  log "neue Version $STEMPEL ($WAS)"
fi

cat > README.md <<'TEXT'
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
TEXT

# ---- App: voller Verlauf als Zweig app (eigener Verlauf neben main) und die Tags testflight-<Build>
if [ -n "$APP" ]; then
  git fetch -q "$APP_GIT" "+refs/heads/main:refs/app/main" "+refs/tags/*:refs/app-tags/*" 2>>"$LOG" || fehler "App Repo nicht lesbar"
  if [ "$(git ls-remote origin refs/heads/app 2>/dev/null | cut -f1)" != "$APP" ]; then
    git push -q origin "+refs/app/main:refs/heads/app" 2>>"$LOG" || fehler "Push des App Zweigs fehlgeschlagen"
    log "App Zweig $(echo "$APP" | cut -c1-7)"
  fi
  git push -q origin "refs/app-tags/*:refs/tags/*" 2>>"$LOG" || log "App Tags nicht alle gepusht"
fi

git add -A
if git diff --cached --quiet; then
  log "unverändert"
  exit 0
fi
git commit -q -m "StageView Stand $(date '+%F %H:%M')${WAS:+ ($WAS)}"
git push -q origin HEAD 2>>"$LOG" || fehler "Push fehlgeschlagen"
log "gesichert $(git rev-parse --short HEAD)"
echo "StageView gespiegelt: $(git rev-parse --short HEAD)${WAS:+, neue Version: $WAS}"
