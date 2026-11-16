#!/bin/zsh
# Builds DialogForge.app into ./build from the Swift package.
# Usage: Scripts/build-app.sh [--sign "Developer ID Application: Name (TEAMID)"]
set -euo pipefail

cd "$(dirname "$0")/.."
identity="-"
if [[ "${1:-}" == "--sign" && -n "${2:-}" ]]; then identity="$2"; fi

version="0.1.0"
app="build/DialogForge.app"

swift build -c release --product DialogForge
binary="$(swift build -c release --show-bin-path)/DialogForge"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/DialogForge"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DialogForge</string>
    <key>CFBundleDisplayName</key><string>DialogForge</string>
    <key>CFBundleIdentifier</key><string>app.dialogforge.DialogForge</string>
    <key>CFBundleExecutable</key><string>DialogForge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${version}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>DialogForge Flow</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSItemContentTypes</key><array><string>app.dialogforge.flow</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>app.dialogforge.flow</string>
            <key>UTTypeDescription</key><string>DialogForge Flow</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>dialogforge</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# The app launches swiftDialog and talks to Jamf Pro, so it is not sandboxed.
codesign --force --options runtime --sign "$identity" "$app"
echo "Built $app"
