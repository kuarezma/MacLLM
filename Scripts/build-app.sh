#!/usr/bin/env bash
# xcodebuild alternatifi: swiftc ile MacLLM.app üretir
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d "Vendor/build-apple/llama.xcframework" ]]; then
  echo "llama.xcframework yok — önce ./Scripts/build-llama-xcframework.sh çalıştırılıyor..."
  ./Scripts/build-llama-xcframework.sh
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
FW_DIR="$ROOT/Vendor/build-apple/llama.xcframework/macos-arm64"
APP="$ROOT/build/MacLLM.app"
BIN="$APP/Contents/MacOS/MacLLM"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp MacLLM/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string MacLLM" "$APP/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable MacLLM" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist" 2>/dev/null || true

cp MacLLM/Resources/default-catalog.json "$APP/Contents/Resources/"
cp -R "$FW_DIR/llama.framework" "$APP/Contents/Frameworks/"

echo "Uygulama simgesi hazırlanıyor..."
if [[ -f "$ROOT/MacLLM/Resources/MacLLMIcon-1024-v2.png" ]]; then
  python3 "$ROOT/Scripts/fit-app-icon.py" "$ROOT/MacLLM/Resources/MacLLMIcon-1024-v2.png" 2>/dev/null || true
fi
echo "Uygulama simgesi derleniyor..."
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP/Contents/Info.plist"
xcrun actool "$ROOT/MacLLM/Resources/Assets.xcassets" \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /tmp/macsistem-actool.plist 2>/dev/null || {
  ICONSET="/tmp/MacLLM.iconset"
  ASSET="$ROOT/MacLLM/Resources/Assets.xcassets/AppIcon.appiconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  cp "$ASSET"/icon_*.png "$ICONSET/"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"
}

MTMD_CC_FLAGS=(
  -Xcc -I"$ROOT/Vendor/llama.cpp/include"
  -Xcc -I"$ROOT/Vendor/llama.cpp/ggml/include"
  -Xcc -I"$ROOT/Vendor/llama.cpp/tools/mtmd"
  -Xcc -I"$ROOT/MacLLM/Bridge"
)

MTMD_SHIM_O="$ROOT/build/mtmd_shim.o"
clang -c "$ROOT/MacLLM/Bridge/mtmd_shim.c" -o "$MTMD_SHIM_O" -O2 \
  -I "$ROOT/Vendor/llama.cpp/include" \
  -I "$ROOT/Vendor/llama.cpp/ggml/include" \
  -I "$ROOT/Vendor/llama.cpp/tools/mtmd" \
  -I "$ROOT/MacLLM/Bridge" \
  -isysroot "$SDK" \
  -target arm64-apple-macos14.0

SOURCES=(
  MacLLM/App/MacLLMApp.swift
  MacLLM/App/AppDelegate.swift
  MacLLM/App/AppShutdown.swift
  MacLLM/App/AppModel.swift
  MacLLM/Core/Models.swift
  MacLLM/Core/MessageAttachment.swift
  MacLLM/Core/UserErrorFormatter.swift
  MacLLM/Core/AppVersion.swift
  MacLLM/Core/AppTheme.swift
  MacLLM/Core/MarkdownContentParser.swift
  MacLLM/Core/HubFileListLogic.swift
  MacLLM/Core/HFModelTypes.swift
  MacLLM/Core/AppNotifications.swift
  MacLLM/Core/AppSettingsOpener.swift
  MacLLM/Core/GenerationStats.swift
  MacLLM/Core/ReasoningContentSplitter.swift
  MacLLM/Services/AppUpdateService.swift
  MacLLM/Services/ModelStore.swift
  MacLLM/Services/ModelCatalogService.swift
  MacLLM/Services/MacSystemProfile.swift
  MacLLM/Services/ModelRecommendationService.swift
  MacLLM/Services/DownloadMetrics.swift
  MacLLM/Services/DownloadPreferences.swift
  MacLLM/Services/RangeDownloadEngine.swift
  MacLLM/Services/HuggingFaceDownloadService.swift
  MacLLM/Services/GGUFFileValidator.swift
  MacLLM/Services/ModelMetadataParser.swift
  MacLLM/Services/ChatTemplateResolver.swift
  MacLLM/Services/GenerationOutputFilter.swift
  MacLLM/Services/HuggingFaceHubService.swift
  MacLLM/Services/HuggingFaceCredentials.swift
  MacLLM/Services/ChatHistoryStore.swift
  MacLLM/Services/ChatProjectStore.swift
  MacLLM/Services/InferenceService.swift
  MacLLM/Services/InferenceMessageBuilder.swift
  MacLLM/Services/AttachmentStore.swift
  MacLLM/Services/MediaContentProcessor.swift
  MacLLM/Services/ModelCapabilities.swift
  MacLLM/Bridge/LibLlama.swift
  MacLLM/Bridge/LibMtmd.swift
  MacLLM/Features/Main/MainView.swift
  MacLLM/Features/Main/NewProjectSheet.swift
  MacLLM/Features/Main/AppUpdateBannerView.swift
  MacLLM/Features/Chat/ChatView.swift
  MacLLM/Features/Chat/ChatHeaderView.swift
  MacLLM/Features/Chat/ContextUsageView.swift
  MacLLM/Features/Chat/CodeBlockView.swift
  MacLLM/Features/Chat/QuickPromptChips.swift
  MacLLM/Features/Chat/SystemPromptSheet.swift
  MacLLM/Features/Chat/ComposerToolsView.swift
  MacLLM/Features/Chat/MessageRow.swift
  MacLLM/Features/Chat/ChatErrorBanner.swift
  MacLLM/Features/Chat/MessageMarkdownView.swift
  MacLLM/Features/Chat/ProseMarkdownView.swift
  MacLLM/Features/Chat/ChatComposerAttachments.swift
  MacLLM/Features/Chat/MessageAttachmentsView.swift
  MacLLM/Features/Models/DownloadProgressView.swift
  MacLLM/Features/Models/ActiveDownloadsPanel.swift
  MacLLM/Features/Models/ModelCatalogView.swift
  MacLLM/Features/Models/OnlineModelSearchView.swift
  MacLLM/Services/HubQuantAdvisor.swift
  MacLLM/Features/Models/HubQuantFitCard.swift
  MacLLM/Features/Models/HubModelAvatarView.swift
  MacLLM/Features/Models/ModelHubBrowserView.swift
  MacLLM/Features/Models/ModelHubDetailView.swift
  MacLLM/Features/Models/HubQuantRowView.swift
  MacLLM/Features/Models/DownloadManagerPopover.swift
  MacLLM/Features/Models/ReadmeMarkdownView.swift
  MacLLM/Features/Settings/SettingsView.swift
  MacLLM/Features/Settings/SettingsComponents.swift
)

echo "Swift derleniyor..."
# Modules symlink (eski derlemeler için)
if [[ ! -e "$FW_DIR/llama.framework/Modules" ]]; then
  ln -sfh Versions/Current/Modules "$FW_DIR/llama.framework/Modules"
fi

swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -O \
  -F "$FW_DIR" \
  -F "$APP/Contents/Frameworks" \
  -framework llama \
  -framework Metal \
  -framework Accelerate \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework UniformTypeIdentifiers \
  -framework AVFoundation \
  -framework PDFKit \
  -framework CoreMedia \
  -o "$BIN" \
  "${SOURCES[@]}" \
  "$MTMD_SHIM_O"

install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

echo "Tamamlandı: $APP"
echo "Çalıştırmak için: open $APP"
