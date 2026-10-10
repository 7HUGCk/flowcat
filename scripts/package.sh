#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
mkdir -p dist
asset="FlowCat-$version-${ARCH:-arm64}.zip"
ditto -c -k --sequesterRsrc --keepParent build/流量喵.app "dist/$asset"
(cd dist && shasum -a 256 "$asset" > "$asset.sha256")
echo "Packaged: dist/$asset"
