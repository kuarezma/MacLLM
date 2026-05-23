#!/usr/bin/env bash
# macOS arm64 only — MacLLM için hızlı llama.cpp XCFramework derlemesi
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="$ROOT/Vendor/llama.cpp"
OUT_DIR="$ROOT/Vendor/build-apple"
BUILD_DIR="$LLAMA_DIR/build-macos-arm64"
MACOS_MIN="14.0"
JOBS="$(sysctl -n hw.ncpu)"

if [[ ! -d "$LLAMA_DIR" ]]; then
  echo "Hata: Vendor/llama.cpp bulunamadı. 'git submodule update --init' çalıştırın."
  exit 1
fi

command -v cmake >/dev/null || { echo "cmake gerekli: brew install cmake"; exit 1; }
command -v xcrun >/dev/null || { echo "Xcode CLI Tools gerekli"; exit 1; }

echo "macOS arm64 llama.cpp derleniyor (Metal, Ninja)..."
cd "$LLAMA_DIR"
rm -rf "$BUILD_DIR" "$OUT_DIR/llama.xcframework"

cmake -S . -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_COMMON=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_BLAS_DEFAULT=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_OPENMP=OFF

cmake --build "$BUILD_DIR" -j "$JOBS" --target mtmd

FW_DIR="$OUT_DIR/llama.framework"
mkdir -p "$FW_DIR/Versions/A/Headers" "$FW_DIR/Versions/A/Resources"

cp include/llama.h "$FW_DIR/Versions/A/Headers/"
cp tools/mtmd/mtmd.h tools/mtmd/mtmd-helper.h "$FW_DIR/Versions/A/Headers/" 2>/dev/null || true
cp "$ROOT/MacLLM/Bridge/mtmd_shim.h" "$FW_DIR/Versions/A/Headers/" 2>/dev/null || true
for h in ggml/include/*.h; do
  cp "$h" "$FW_DIR/Versions/A/Headers/" 2>/dev/null || true
done

LIBS=(
  "$BUILD_DIR/src/libllama.a"
  "$BUILD_DIR/ggml/src/libggml.a"
  "$BUILD_DIR/ggml/src/libggml-base.a"
  "$BUILD_DIR/ggml/src/libggml-cpu.a"
  "$BUILD_DIR/ggml/src/ggml-metal/libggml-metal.a"
  "$BUILD_DIR/ggml/src/ggml-blas/libggml-blas.a"
  "$BUILD_DIR/tools/mtmd/libmtmd.a"
)

# Ninja çıktı yolları farklıysa bul
if [[ ! -f "${LIBS[0]}" ]]; then
  LIBS=()
  while IFS= read -r lib; do
    LIBS+=("$lib")
  done < <(find "$BUILD_DIR" -name 'libllama.a' -o -name 'libggml.a' -o -name 'libggml-base.a' -o -name 'libggml-cpu.a' -o -name 'libggml-metal.a' -o -name 'libggml-blas.a' -o -name 'libmtmd.a' | sort -u)
fi

TEMP="$BUILD_DIR/temp-combined"
mkdir -p "$TEMP"
xcrun libtool -static -o "$TEMP/combined.a" "${LIBS[@]}" 2>/dev/null

xcrun -sdk macosx clang++ -dynamiclib \
  -arch arm64 \
  -mmacosx-version-min="$MACOS_MIN" \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -Wl,-force_load,"$TEMP/combined.a" \
  -framework Foundation -framework Metal -framework Accelerate -lc++ \
  -install_name "@rpath/llama.framework/Versions/A/llama" \
  -o "$FW_DIR/Versions/A/llama"

ln -sfh A "$FW_DIR/Versions/Current"
ln -sfh Versions/Current/llama "$FW_DIR/llama"
ln -sfh Versions/Current/Headers "$FW_DIR/Headers"
ln -sfh Versions/Current/Modules "$FW_DIR/Modules"
ln -sfh Versions/Current/Resources "$FW_DIR/Resources"

mkdir -p "$FW_DIR/Versions/A/Modules"
cat > "$FW_DIR/Versions/A/Modules/module.modulemap" <<'EOF'
framework module llama {
    umbrella header "llama.h"
    export *
    module * { export * }
}
EOF

cat > "$FW_DIR/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>llama</string>
  <key>CFBundleIdentifier</key><string>org.ggml.llama</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>${MACOS_MIN}</string>
</dict></plist>
EOF

# Xcode bazı XCFramework kopyalarında kök Info.plist arar; versioned framework
# imzasının bozulmaması için kökte normal dosya değil symlink olmalı.
ln -sfh Versions/Current/Resources/Info.plist "$FW_DIR/Info.plist"

xcodebuild -create-xcframework \
  -framework "$FW_DIR" \
  -output "$OUT_DIR/llama.xcframework"

echo "Tamamlandı: $OUT_DIR/llama.xcframework"
