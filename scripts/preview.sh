#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/compiler.sh
compile_core
xcrun swiftc "${compiler_flags[@]}" -parse-as-library -I "$build_dir" -L "$build_dir" \
    -lClipboardCore Sources/Clip20/HistoryView.swift Sources/Clip20/HarveyTheme.swift \
    scripts/RenderPreview.swift -o "$build_dir/RenderPreview"
"$build_dir/RenderPreview" "$PWD/.build/previews" "$PWD/Sources/Clip20/Resources/Fonts"
