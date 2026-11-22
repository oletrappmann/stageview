#!/bin/zsh
# Screenshots aller Seiten und Menüs im Vorführmodus (echter Datenstand aus scripts/demo_daten.py, kein Server, keine Anmeldung).
# Aufruf im Ordner app/: scripts/bilder.sh <ausgabeordner>   (DUNKEL=1 für den Dunkelmodus)
# Läuft auf dem eigenen Simulator „StageView Test“, nie auf Oles Simulatoren. Danach wieder aus (Arbeitsspeicher).
set -eu
cd "${0:A:h}/.."
OUT=${1:?Ausgabeordner}; SIM="StageView Test"
mkdir -p "$OUT"; OUT=${OUT:A}
[ -f build/demo.json ] || python3 scripts/demo_daten.py
xcodegen -q
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryLevel 100 --batteryState charged --cellularBars 4 --wifiBars 3 2>/dev/null || true
TEST_RUNNER_BILDER_ORDNER="$OUT" TEST_RUNNER_DEMO_DATEI="${PWD}/build/demo.json" TEST_RUNNER_BILDER_DUNKEL="${DUNKEL:-0}" \
xcodebuild test -project StageView.xcodeproj -scheme StageView -destination "platform=iOS Simulator,name=$SIM" \
  -only-testing:StageViewUITests/BilderTests/${TEST:-testBilder} \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO > build/bilder.log 2>&1 || {
  echo "Screenshots mit Fehlern, siehe build/bilder.log"; grep -E "error:|failed|Fehler" build/bilder.log | cut -c1-260 | head; }
ls "$OUT" | wc -l
[ "${AN_LASSEN:-0}" = 1 ] || xcrun simctl shutdown "$SIM" 2>/dev/null || true
