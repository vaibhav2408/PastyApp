#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/compiler.sh
compile_core
xcrun swiftc "${compiler_flags[@]}" -O -parse-as-library -I "$build_dir" -L "$build_dir" \
    -lClipboardCore Sources/Clip20/*.swift -o "$build_dir/Clip20"
app="$PWD/dist/Clip20.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace the executable atomically so an already-running copy keeps its mapped binary.
cp "$build_dir/Clip20" "$app/Contents/MacOS/Clip20.next"
mv -f "$app/Contents/MacOS/Clip20.next" "$app/Contents/MacOS/Clip20"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources/Fonts"
cp Sources/Clip20/Resources/Fonts/*.ttf "$app/Contents/Resources/Fonts/"
xcrun swiftc "${compiler_flags[@]}" -parse-as-library Sources/Clip20/HarveyTheme.swift \
    scripts/GenerateAppIcon.swift -o "$build_dir/GenerateAppIcon"
"$build_dir/GenerateAppIcon" "$build_dir/Clip20.iconset"
iconutil -c icns "$build_dir/Clip20.iconset" -o "$app/Contents/Resources/Clip20.icns"
codesign --force --sign - "$app"
touch "$app"
printf 'Built %s\n' "$app"
