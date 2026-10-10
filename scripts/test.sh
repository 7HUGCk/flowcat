#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/trafficledger-clang-cache"
test_binary=$(mktemp "${TMPDIR:-/tmp}/trafficledger-tests.XXXXXX")
trap 'rm -f "$test_binary"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/Core.swift Tests/main.swift -o "$test_binary"
"$test_binary"
