#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")"
source_app="$project_dir/build/XFC Bridge.app"
dmg_name="XFC-Bridge-${version}-macOS-Apple-Silicon.dmg"
output_dmg="$project_dir/dist/$dmg_name"
temporary_dir="$(mktemp -d /private/tmp/XFCBridge-dmg.XXXXXX)"
mount_dir="$temporary_dir/mount"
cleanup() {
    if mount | /usr/bin/grep -Fq " on $mount_dir ("; then
        hdiutil detach -quiet "$mount_dir" || true
    fi
    /bin/rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

if [[ ! -d "$source_app" ]]; then
    print -u2 "App fehlt: $source_app (zuerst ./scripts/build-app.sh ausführen)"
    exit 1
fi

codesign --verify --deep "$source_app"

volume_dir="$temporary_dir/XFC Bridge $version"
mkdir -p "$volume_dir" "$project_dir/dist"
/usr/bin/ditto "$source_app" "$volume_dir/XFC Bridge.app"
/usr/bin/xattr -cr "$volume_dir/XFC Bridge.app"
codesign --verify --deep --strict "$volume_dir/XFC Bridge.app"
cp "$project_dir/README.md" "$project_dir/ANLEITUNG.md" "$project_dir/LICENSE" "$volume_dir/"
cp "$project_dir/Resources/AppIcon.icns" "$volume_dir/.VolumeIcon.icns"
ln -s /Applications "$volume_dir/Programme"

temporary_rw_dmg="$temporary_dir/XFCBridge-staging.dmg"
temporary_dmg="$temporary_dir/$dmg_name"
hdiutil create -quiet -srcfolder "$volume_dir" -volname "XFC Bridge $version" -fs HFS+ -format UDRW "$temporary_rw_dmg"
mkdir "$mount_dir"
hdiutil attach -quiet -nobrowse -mountpoint "$mount_dir" "$temporary_rw_dmg"
xcrun SetFile -a C "$mount_dir"
hdiutil detach -quiet "$mount_dir"
hdiutil convert -quiet "$temporary_rw_dmg" -format UDZO -o "$temporary_dmg"
hdiutil verify -quiet "$temporary_dmg"
mv -f "$temporary_dmg" "$output_dmg"
(
    cd "$project_dir/dist"
    shasum -a 256 "$dmg_name"
) > "$project_dir/dist/SHA256SUMS"

print "$output_dmg"
