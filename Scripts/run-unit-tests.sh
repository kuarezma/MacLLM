#!/usr/bin/env bash
# Foundation-only birim testleri (Xcode gerekmez)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/build"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
BIN="$ROOT/build/unit-test-markdown"
MODEL_CORE_SOURCES=(
  MacLLM/Core/MessageAttachment.swift
  MacLLM/Core/GenerationStats.swift
  MacLLM/Core/Models.swift
  MacLLM/Services/MacSystemProfile.swift
)

echo "==> MarkdownContentParserTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$BIN" \
  MacLLM/Core/MarkdownContentParser.swift \
  Tests/MarkdownContentParserTests.swift

"$BIN"

SANITIZER_BIN="$ROOT/build/unit-test-sanitizer"
echo "==> ControlTokenSanitizerTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$SANITIZER_BIN" \
  MacLLM/Services/GenerationOutputFilter.swift \
  Tests/ControlTokenSanitizerTests.swift

"$SANITIZER_BIN"

FILTER_BIN="$ROOT/build/unit-test-filter"
echo "==> GenerationOutputFilterTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$FILTER_BIN" \
  MacLLM/Services/GenerationOutputFilter.swift \
  Tests/GenerationOutputFilterTests.swift

"$FILTER_BIN"

LAUNCH_BIN="$ROOT/build/unit-test-launch"
echo "==> LaunchPreferencesTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$LAUNCH_BIN" \
  MacLLM/Services/LaunchPreferences.swift \
  Tests/LaunchPreferencesTests.swift

"$LAUNCH_BIN"

METADATA_BIN="$ROOT/build/unit-test-model-metadata"
echo "==> ModelMetadataParserTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$METADATA_BIN" \
  MacLLM/Services/ModelMetadataParser.swift \
  Tests/ModelMetadataParserTests.swift
"$METADATA_BIN"

CAPABILITIES_BIN="$ROOT/build/unit-test-model-capabilities"
echo "==> ModelCapabilitiesTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$CAPABILITIES_BIN" \
  MacLLM/Core/HFModelTypes.swift \
  "${MODEL_CORE_SOURCES[@]}" \
  MacLLM/Services/ModelMetadataParser.swift \
  MacLLM/Services/ModelCapabilities.swift \
  Tests/ModelCapabilitiesTests.swift
"$CAPABILITIES_BIN"

HUB_LIST_BIN="$ROOT/build/unit-test-hub-file-list"
echo "==> HubFileListLogicTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$HUB_LIST_BIN" \
  MacLLM/Core/HubFileListLogic.swift \
  MacLLM/Core/HFModelTypes.swift \
  "${MODEL_CORE_SOURCES[@]}" \
  MacLLM/Services/ModelMetadataParser.swift \
  MacLLM/Services/ModelRecommendationService.swift \
  Tests/HubFileListLogicTests.swift
"$HUB_LIST_BIN"

CATALOG_BIN="$ROOT/build/unit-test-model-catalog"
echo "==> ModelCatalogServiceTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$CATALOG_BIN" \
  "${MODEL_CORE_SOURCES[@]}" \
  MacLLM/Services/ModelCatalogService.swift \
  Tests/ModelCatalogServiceTests.swift
"$CATALOG_BIN"

MEDIA_BIN="$ROOT/build/unit-test-media"
echo "==> MediaContentProcessorTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -framework PDFKit \
  -framework AVFoundation \
  -framework AppKit \
  -o "$MEDIA_BIN" \
  MacLLM/Services/MediaContentProcessor.swift \
  MacLLM/Services/AttachmentStore.swift \
  MacLLM/Services/ModelStore.swift \
  "${MODEL_CORE_SOURCES[@]}" \
  Tests/MediaContentProcessorTests.swift
"$MEDIA_BIN"

ATTACH_BIN="$ROOT/build/unit-test-attach-kind"
echo "==> AttachmentStoreKindTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$ATTACH_BIN" \
  MacLLM/Services/AttachmentStore.swift \
  MacLLM/Services/ModelStore.swift \
  "${MODEL_CORE_SOURCES[@]}" \
  Tests/AttachmentStoreKindTests.swift
"$ATTACH_BIN"

EXPORT_BIN="$ROOT/build/unit-test-export"
echo "==> ChatExporterTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$EXPORT_BIN" \
  "${MODEL_CORE_SOURCES[@]}" \
  MacLLM/Services/ModelStore.swift \
  MacLLM/Services/ChatProjectStore.swift \
  MacLLM/Services/ChatImporter.swift \
  Tests/ChatExporterTests.swift
"$EXPORT_BIN"

KEYCHAIN_BIN="$ROOT/build/unit-test-keychain"
echo "==> HuggingFaceCredentialsTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$KEYCHAIN_BIN" \
  MacLLM/Services/KeychainStorage.swift \
  Tests/HuggingFaceCredentialsTests.swift
"$KEYCHAIN_BIN"

FORMATTER_BIN="$ROOT/build/unit-test-user-error-formatter"
echo "==> UserErrorFormatterTests"
swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -Onone \
  -o "$FORMATTER_BIN" \
  MacLLM/Core/UserErrorFormatter.swift \
  MacLLM/Services/WebSearchService.swift \
  Tests/UserErrorFormatterTests.swift
"$FORMATTER_BIN"

echo "==> unit tests başarılı"
