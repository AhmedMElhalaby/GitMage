#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: release.sh vX.Y.Z}"
DESC="A Git workspace inspector for Ainkrad."
AUTHOR="Ahmed M. Elhalaby"
LONG_DESC="Git Mage brings a focused Git workspace inspector into Ainkrad: choose a repository folder, inspect branch and status, review file-level changes, and prepare the next commit from a clean HUD-style surface."

xcodegen generate
xcodebuild -scheme GitMagePlugin -configuration Release -derivedDataPath build -destination 'platform=macOS' build
BUNDLE="build/Build/Products/Release/GitMagePlugin.bundle"

rm -rf dist && mkdir -p dist
/usr/bin/ditto -c -k --keepParent "$BUNDLE" dist/gitmage.bundle.zip
SHA="$(shasum -a 256 dist/gitmage.bundle.zip | awk '{print $1}')"

cat > dist/ainkrad-plugin.json <<JSON
{ "id": "gitmage", "name": "Git Mage", "icon": "wand.and.stars", "description": "$DESC", "apiVersion": 4, "sha256": "$SHA",
  "author": "$AUTHOR", "longDescription": "$LONG_DESC",
  "links": [] }
JSON

gh release create "$VERSION" dist/ainkrad-plugin.json dist/gitmage.bundle.zip \
  --title "Git Mage $VERSION" --notes "Git Mage plugin $VERSION"
echo "Released $VERSION (sha256 $SHA)"

