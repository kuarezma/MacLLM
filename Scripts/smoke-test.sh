#!/usr/bin/env bash
# MacLLM — derleme ve paket bütünlüğü duman testi (CI / yerel)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> MacLLM smoke test"
./Scripts/build-app.sh

APP="$ROOT/build/MacLLM.app"
BIN="$APP/Contents/MacOS/MacLLM"
PLIST="$APP/Contents/Info.plist"

test -d "$APP" || { echo "HATA: $APP yok"; exit 1; }
test -x "$BIN" || { echo "HATA: çalıştırılabilir yok: $BIN"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")
echo "    Sürüm: $VERSION ($BUILD)"

OTOOL_OUT="$(otool -L "$BIN" 2>/dev/null || true)"
if [[ "$OTOOL_OUT" != *llama.framework* ]]; then
  echo "HATA: llama.framework bağlı değil"
  exit 1
fi

FRAMEWORK="$APP/Contents/Frameworks/llama.framework/Versions/A/llama"
if [[ ! -f "$FRAMEWORK" ]]; then
  FRAMEWORK="$APP/Contents/Frameworks/llama.framework/llama"
fi
test -f "$FRAMEWORK" || { echo "HATA: llama.framework eksik"; exit 1; }

# İmza opsiyonel (yerel derlemede ad-hoc olabilir)
if codesign -dv "$APP" 2>/dev/null; then
  echo "    codesign: OK"
else
  echo "    codesign: atlandı (yerel derleme)"
fi

echo "==> smoke test başarılı"
