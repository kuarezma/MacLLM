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

SOURCES=(
  MacLLM/App/MacLLMApp.swift
  MacLLM/App/AppModel.swift
  MacLLM/Core/Models.swift
  MacLLM/Services/ModelStore.swift
  MacLLM/Services/ModelCatalogService.swift
  MacLLM/Services/MacSystemProfile.swift
  MacLLM/Services/ModelRecommendationService.swift
  MacLLM/Services/DownloadMetrics.swift
  MacLLM/Services/HuggingFaceDownloadService.swift
  MacLLM/Services/HuggingFaceHubService.swift
  MacLLM/Services/HuggingFaceCredentials.swift
  MacLLM/Services/ChatHistoryStore.swift
  MacLLM/Services/InferenceService.swift
  MacLLM/Bridge/LibLlama.swift
  MacLLM/Features/Main/MainView.swift
  MacLLM/Features/Chat/ChatView.swift
  MacLLM/Features/Chat/MessageRow.swift
  MacLLM/Features/Models/DownloadProgressView.swift
  MacLLM/Features/Models/ModelCatalogView.swift
  MacLLM/Features/Models/OnlineModelSearchView.swift
  MacLLM/Features/Settings/SettingsView.swift
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
  -o "$BIN" \
  "${SOURCES[@]}"

install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

echo "Tamamlandı: $APP"
echo "Çalıştırmak için: open $APP"
