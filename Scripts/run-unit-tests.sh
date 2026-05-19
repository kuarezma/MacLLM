#!/usr/bin/env bash
# Foundation-only birim testleri (Xcode gerekmez)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/build"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
BIN="$ROOT/build/unit-test-markdown"

echo "==> MarkdownContentParserTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$BIN" \
  MacLLM/Core/MarkdownContentParser.swift \
  Tests/MarkdownContentParserTests.swift

"$BIN"

SANITIZER_BIN="$ROOT/build/unit-test-sanitizer"
echo "==> ControlTokenSanitizerTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$SANITIZER_BIN" \
  MacLLM/Services/GenerationOutputFilter.swift \
  Tests/ControlTokenSanitizerTests.swift

"$SANITIZER_BIN"

FILTER_BIN="$ROOT/build/unit-test-filter"
echo "==> GenerationOutputFilterTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$FILTER_BIN" \
  MacLLM/Services/GenerationOutputFilter.swift \
  Tests/GenerationOutputFilterTests.swift

"$FILTER_BIN"

LAUNCH_BIN="$ROOT/build/unit-test-launch"
echo "==> LaunchPreferencesTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$LAUNCH_BIN" \
  MacLLM/Services/LaunchPreferences.swift \
  Tests/LaunchPreferencesTests.swift

"$LAUNCH_BIN"
echo "==> unit tests başarılı"
