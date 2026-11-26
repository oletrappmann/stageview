#!/bin/zsh
# Schickt dem Simulator „StageView Test“ Mitteilungen wie der Server (Titel, Text, link), für BilderTests/testMitteilungEcht.
# Aufruf im Ordner app/ parallel zum Test: scripts/mitteilungstest.sh [anzahl] [abstand]
cd "${0:A:h}/.."
DATEI=$(mktemp -t sv-push).json
cat > "$DATEI" <<'JSON'
{"aps": {"alert": {"title": "Content Day November", "body": "Jonas zu „Dating Fünf von Zehn“: Mitteilungstest"}, "sound": "default",
 "thread-id": "stageview-menfeu"}, "link": "https://videos.stagecraft.media/menfeu/1?k=49&t=0"}
JSON
for i in $(seq ${1:-40}); do
  xcrun simctl push "StageView Test" media.stagecraft.stageview "$DATEI" >/dev/null 2>&1
  sleep ${2:-6}
done
rm -f "$DATEI"
