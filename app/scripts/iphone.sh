#!/bin/zsh
# Baut die App (Release) und spielt sie direkt auf ein verbundenes iPhone, ohne TestFlight (wie STAGECRAFT_REGIE/app/scripts/iphone.sh).
# Signiert über das Stagecraft Konto (Team 9ZM98AMD7M) mit dem App Store Connect Schlüssel aus dem Mac Schlüsselbund (derselbe wie
# scripts/testflight.sh der TESS App). Nur signiert gehen die Universal Links von videos.stagecraft.media in die App.
# Aufruf im Ordner app/: scripts/iphone.sh [Geräte UDID]
set -eu
cd "${0:A:h}/.."
GERAET=${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && (/ connected / || / available /) {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)}
[ -n "$GERAET" ] || { echo "Kein iPhone verbunden"; exit 1; }
SCHLUESSEL=$(mktemp -d)/asc.p8
trap 'rm -rf "${SCHLUESSEL:h}"' EXIT
security find-generic-password -s TESS_ASC_SCHLUESSEL -w | base64 -d > "$SCHLUESSEL"
ZUGANG=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration -authenticationKeyPath "$SCHLUESSEL"
  -authenticationKeyID "$(security find-generic-password -s TESS_ASC_SCHLUESSEL | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')"
  -authenticationKeyIssuerID "$(security find-generic-password -s TESS_ASC_AUSSTELLER -w)")
xcodegen -q
xcodebuild build -project StageView.xcodeproj -scheme StageView -configuration Release -destination "id=$GERAET" \
  -derivedDataPath build/DerivedDataGeraet "${ZUGANG[@]}" > build/iphone.log 2>&1 \
  || { grep -E "error:|rror:" build/iphone.log | cut -c1-260 | head -12; exit 1; }
APP=build/DerivedDataGeraet/Build/Products/Release-iphoneos/StageView.app
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "applinks:videos.stagecraft.media" && echo "Universal Links im Paket: ja" || echo "Universal Links im Paket: FEHLT"
xcrun devicectl device install app --device "$GERAET" "$APP" 2>&1 | grep -E "installed|App installed|bundleID|rror" | head -5
xcrun devicectl device process launch --device "$GERAET" media.stagecraft.stageview 2>&1 | grep -E "Launched|rror|locked" | head -3 || true
