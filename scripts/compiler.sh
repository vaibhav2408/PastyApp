#!/bin/bash
# Shared by build.sh and test.sh; no package manager or external dependencies needed.
build_dir="$PWD/.build/native"
mkdir -p "$build_dir/ModuleCache"
sdk_path="${SDKROOT:-$(xcrun --show-sdk-path)}"
# This Mac has Swift 6.1 alongside a newer default SDK. Prefer its matching SDK.
if [[ -z "${SDKROOT:-}" ]] && xcrun swiftc --version 2>&1 | /usr/bin/grep -q 'Swift version 6.1' \
   && [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk ]]; then
    sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk
fi
compiler_flags=(-sdk "$sdk_path" -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$build_dir/ModuleCache")

compile_core() {
    xcrun swiftc "${compiler_flags[@]}" -O -parse-as-library -emit-library -static -emit-module \
        -module-name ClipboardCore Sources/ClipboardCore/*.swift \
        -emit-module-path "$build_dir/ClipboardCore.swiftmodule" -o "$build_dir/libClipboardCore.a"
}
