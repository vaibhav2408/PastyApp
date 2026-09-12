#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/compiler.sh
compile_core
xcrun swiftc "${compiler_flags[@]}" -parse-as-library -I "$build_dir" -L "$build_dir" \
    -lClipboardCore Tests/ClipboardCoreTests/*.swift -o "$build_dir/Clip20Checks"
if [[ "${1:-}" != "--build-only" ]]; then
    "$build_dir/Clip20Checks"
fi
