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
echo "==> unit tests başarılı"
