#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-release}"
output_app="$project_dir/build/XFC Bridge.app"
staging_app="/private/tmp/XFCBridge-app/XFC Bridge.app"
sdk_root="${XFCBRIDGE_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
scratch_path="/private/tmp/XFCBridge-swiftpm-release"
module_cache="$scratch_path/ModuleCache"
build_environment=(SDKROOT="$sdk_root" CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache")
binary_dir="$(env $build_environment swift build --disable-sandbox -debug-info-format none --scratch-path "$scratch_path" --package-path "$project_dir" -c "$configuration" --show-bin-path)"

env $build_environment swift build --disable-sandbox -debug-info-format none --scratch-path "$scratch_path" --package-path "$project_dir" -c "$configuration"
/bin/rm -rf -- "$staging_app"
mkdir -p "$staging_app/Contents/MacOS"
mkdir -p "$staging_app/Contents/Resources"
cp "$project_dir/Info.plist" "$staging_app/Contents/Info.plist"
cp "$binary_dir/XFCBridge" "$staging_app/Contents/MacOS/XFC Bridge"
cp "$project_dir/Resources/AppIcon.icns" "$staging_app/Contents/Resources/AppIcon.icns"
xattr -cr "$staging_app"
codesign --force --sign - "$staging_app"
codesign --verify --deep --strict "$staging_app"

mkdir -p "$project_dir/build"
/bin/rm -rf -- "$output_app"
/usr/bin/ditto "$staging_app" "$output_app"
# Finder/iCloud may immediately add an empty FinderInfo xattr to the copied
# bundle. Preserve the valid staging signature and verify the copy without
# trying to sign the File Provider managed destination in place.
codesign --verify --deep "$output_app"
/usr/bin/touch "$output_app"

echo "$output_app"
