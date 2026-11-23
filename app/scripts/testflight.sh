#!/bin/zsh
# Neue Version zu TestFlight: Release Archiv bauen, signieren und hochladen (wie TESS_APP/scripts/testflight.sh und der Prompter).
# Nur auf Oles ausdrückliches Ja (Ole, 06.11.2026: das Team soll nicht so viele Updates bekommen).
# Build Nummer = Uhrzeit. Danach verarbeitet Apple 5 bis 30 Minuten. Der App Eintrag in App Store Connect muss existieren
# (nur im Browser anlegbar). Schlüssel aus dem Mac Schlüsselbund (TESS_ASC_SCHLUESSEL, TESS_ASC_AUSSTELLER), nie ausgeben.
# Aufruf im Ordner app/: scripts/testflight.sh [--nur-archiv]
set -eu
cd "${0:A:h}/.."
BUILD=$(date +%Y%m%d%H%M)
ORDNER=$PWD/build/archiv
TEAM=9ZM98AMD7M
SCHLUESSEL=$(mktemp -d)/asc.p8
trap 'rm -rf "${SCHLUESSEL:h}"' EXIT
security find-generic-password -s TESS_ASC_SCHLUESSEL -w | base64 -d > "$SCHLUESSEL"
ZUGANG=(-allowProvisioningUpdates -authenticationKeyPath "$SCHLUESSEL"
  -authenticationKeyID "$(security find-generic-password -s TESS_ASC_SCHLUESSEL | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')"
  -authenticationKeyIssuerID "$(security find-generic-password -s TESS_ASC_AUSSTELLER -w)")
mkdir -p "$ORDNER"
cat > "$ORDNER/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodegen -q
xcodebuild archive -project StageView.xcodeproj -scheme StageView -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ORDNER/StageView-$BUILD.xcarchive" -derivedDataPath build/DerivedDataArchiv "${ZUGANG[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD" > build/archiv.log 2>&1 || { grep -E "error:" build/archiv.log | cut -c1-260 | head; exit 1; }
[ -d "$ORDNER/StageView-$BUILD.xcarchive" ] && echo "Archiv $BUILD fertig"
[ "${1:-}" = "--nur-archiv" ] && exit 0
xcodebuild -exportArchive -archivePath "$ORDNER/StageView-$BUILD.xcarchive" -exportOptionsPlist "$ORDNER/ExportOptions.plist" \
  -exportPath "$ORDNER/export-$BUILD" "${ZUGANG[@]}" 2>&1 | grep -E "error|rror:|Upload|upload|EXPORT|no suitable|App Store|Progress 100" | cut -c1-260 | tail -14
echo "Build $BUILD"
