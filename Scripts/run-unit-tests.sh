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

MEDIA_BIN="$ROOT/build/unit-test-media"
echo "==> MediaContentProcessorTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -framework PDFKit \
  -framework AVFoundation \
  -framework AppKit \
  -o "$MEDIA_BIN" \
  MacLLM/Services/MediaContentProcessor.swift \
  MacLLM/Services/AttachmentStore.swift \
  MacLLM/Services/ModelStore.swift \
  MacLLM/Core/MessageAttachment.swift \
  MacLLM/Core/GenerationStats.swift \
  MacLLM/Core/Models.swift \
  MacLLM/Services/MacSystemProfile.swift \
  Tests/MediaContentProcessorTests.swift
"$MEDIA_BIN"

ATTACH_BIN="$ROOT/build/unit-test-attach-kind"
echo "==> AttachmentStoreKindTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$ATTACH_BIN" \
  MacLLM/Services/AttachmentStore.swift \
  MacLLM/Services/ModelStore.swift \
  MacLLM/Core/MessageAttachment.swift \
  MacLLM/Core/GenerationStats.swift \
  MacLLM/Core/Models.swift \
  MacLLM/Services/MacSystemProfile.swift \
  Tests/AttachmentStoreKindTests.swift
"$ATTACH_BIN"

EXPORT_BIN="$ROOT/build/unit-test-export"
echo "==> ChatExporterTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$EXPORT_BIN" \
  MacLLM/Core/GenerationStats.swift \
  MacLLM/Core/Models.swift \
  MacLLM/Core/MessageAttachment.swift \
  MacLLM/Services/ModelStore.swift \
  MacLLM/Services/MacSystemProfile.swift \
  MacLLM/Services/ChatProjectStore.swift \
  MacLLM/Services/ChatImporter.swift \
  Tests/ChatExporterTests.swift
"$EXPORT_BIN"

KEYCHAIN_BIN="$ROOT/build/unit-test-keychain"
echo "==> HuggingFaceCredentialsTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$KEYCHAIN_BIN" \
  MacLLM/Services/KeychainStorage.swift \
  Tests/HuggingFaceCredentialsTests.swift
"$KEYCHAIN_BIN"

FORMATTER_BIN="$ROOT/build/unit-test-user-error-formatter"
echo "==> UserErrorFormatterTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -o "$FORMATTER_BIN" \
  MacLLM/Core/UserErrorFormatter.swift \
  Tests/UserErrorFormatterTests.swift
"$FORMATTER_BIN"

echo "==> unit tests başarılı"
