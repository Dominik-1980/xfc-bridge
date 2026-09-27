#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
sdk_root="${XFCBRIDGE_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
scratch_path="/private/tmp/XFCBridge-swiftpm-tests"
module_cache="$scratch_path/ModuleCache"

env \
    SDKROOT="$sdk_root" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift test --disable-sandbox --scratch-path "$scratch_path" --package-path "$project_dir"
