#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
dist_dir="$repo_root/dist"
app_path="$dist_dir/FindUAS.app"

cd "$repo_root"
swift build -c release --product FindUAS
bin_path="$(swift build -c release --show-bin-path)"

if [[ "$app_path" != "$repo_root/dist/FindUAS.app" ]]; then
    echo "Refusing to replace unexpected app path: $app_path" >&2
    exit 1
fi

rm -rf -- "$app_path"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/FindUAS" "$app_path/Contents/MacOS/FindUAS"
cp "$repo_root/Packaging/Info.plist" "$app_path/Contents/Info.plist"

codesign --force --deep --sign - "$app_path"
plutil -lint "$app_path/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Built $app_path"
