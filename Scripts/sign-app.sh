#!/usr/bin/env bash
# MacLLM.app için geçerli codesign (adhoc veya Developer ID)
set -euo pipefail

APP_PATH="${1:?MacLLM.app yolu gerekli}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${APP_SIGN_IDENTITY:--}"
ENTITLEMENTS="$ROOT/MacLLM/MacLLM.entitlements"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Hata: $APP_PATH bulunamadı."
  exit 1
fi

sign() {
  local target="$1"
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$target"
  else
    local args=(--force --sign "$IDENTITY" --timestamp)
    if [[ -f "$ENTITLEMENTS" && "$target" == *".app" ]]; then
      args+=(--options runtime --entitlements "$ENTITLEMENTS")
    elif [[ "$target" == *".app" || "$target" == *MacLLM ]]; then
      args+=(--options runtime)
    fi
    codesign "${args[@]}" "$target"
  fi
}

FW="$APP_PATH/Contents/Frameworks/llama.framework"
if [[ -f "$FW/Versions/A/llama" ]]; then
  sign "$FW/Versions/A/llama"
  sign "$FW"
fi

sign "$APP_PATH/Contents/MacOS/MacLLM"
sign "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "İmza doğrulandı: $APP_PATH (identity=$IDENTITY)"
