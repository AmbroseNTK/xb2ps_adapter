#!/bin/zsh
# Build and sign Xb2PS.app with your own Apple Developer account.
#
#   ./build.sh            build + sign (Xcode registers the App ID and creates a provisioning profile)
#   ./build.sh --no-sign  compile only; the app will NOT be able to create the virtual controller
#
# Optional environment variables:
#   DEVELOPMENT_TEAM  Team ID (default: taken from the "Apple Development" certificate in the keychain)
#   BUNDLE_ID         Bundle identifier (default: dev.xb2ps.<lowercased team id>)
set -euo pipefail
cd "$(dirname "$0")"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  DEVELOPMENT_TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
    | awk -F'= ' '/organizationalUnitName/ {print $2; exit}')
fi
export DEVELOPMENT_TEAM
export BUNDLE_ID="${BUNDLE_ID:-dev.xb2ps.${DEVELOPMENT_TEAM:l}}"

xcodegen generate --quiet

args=(-project Xb2PS.xcodeproj -scheme Xb2PS -configuration Release -derivedDataPath build)
if [[ "${1:-}" == "--no-sign" ]]; then
  args+=(CODE_SIGNING_ALLOWED=NO)
else
  [[ -n "$DEVELOPMENT_TEAM" ]] || { echo "No Team ID found. Set DEVELOPMENT_TEAM=<team id> and run again." >&2; exit 1; }
  args+=(-allowProvisioningUpdates)
fi

xcodebuild "${args[@]}" build | grep -E "error|warning: |BUILD|Signing Identity|Provisioning Profile" || true
echo "App: $PWD/build/Build/Products/Release/Xb2PS.app"
