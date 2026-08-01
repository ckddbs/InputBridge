#!/bin/sh

set -eu

version="${1:-0.1.7}"
build_number="${2:-1}"
project_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
binary_path="$project_dir/.build/apple/Products/Release/InputBridge"
icon_path="$project_dir/Assets/AppIcon.icns"
output_dir="$project_dir/dist"
output_path="$output_dir/InputBridge-$version-unsigned-universal.zip"
package_dir="$(mktemp -d /private/tmp/inputbridge-package.XXXXXX)"
app_path="$package_dir/InputBridge.app"

cleanup() {
    rm -rf "$package_dir"
}
trap cleanup EXIT INT TERM

cd "$project_dir"
swift build -c release --arch arm64 --arch x86_64

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$output_dir"
cp "$binary_path" "$app_path/Contents/MacOS/InputBridge"
cp "$icon_path" "$app_path/Contents/Resources/AppIcon.icns"

plist="$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string ko" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string InputBridge" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string InputBridge" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string net.inputbridge.app" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string InputBridge" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$plist"

# This is an ad-hoc signature, not a Developer ID distribution signature.
codesign --force --deep --sign - "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_path"

codesign --verify --deep --strict "$app_path"
lipo -info "$app_path/Contents/MacOS/InputBridge"
shasum -a 256 "$output_path"

echo "Created $output_path"
