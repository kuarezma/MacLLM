#!/usr/bin/env bash
# Yerel çıkarım regresyonu: sabit prompt ile çok tur, TTFT (prompt eval) ve tok/s loglar.
# CI'ya bağlanmaz; llama-cli gerekir (yoksa derlenir).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="$ROOT/Vendor/llama.cpp"
BUILD_DIR="${LLAMA_BUILD_DIR:-$LLAMA_DIR/build-macos-arm64}"
CLI="$BUILD_DIR/bin/llama-cli"

MODEL=""
PROMPT="Bugün günlerden ne?"
TURNS=5
PREDICT=64
NGPU="auto"
FLASH="auto"
BUILD_CLI=0

usage() {
  cat <<'EOF'
Kullanım: bench-inference.sh --model path.gguf [seçenekler]

Seçenekler:
  --model PATH     GGUF model yolu (zorunlu)
  --prompt TEXT    Kullanıcı mesajı (varsayılan: "Bugün günlerden ne?")
  --turns N        Tur sayısı (varsayılan: 5)
  --predict N      Tur başına üretilecek token (varsayılan: 64)
  --ngl N|auto     GPU katman sayısı (varsayılan: auto)
  --flash on|off|auto  Flash Attention (varsayılan: auto)
  --build-cli      llama-cli yoksa önce derle
  -h, --help       Bu yardım

Örnek:
  ./Scripts/bench-inference.sh --model ~/Models/qwopus.Q5_K_M.gguf --turns 5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --turns) TURNS="$2"; shift 2 ;;
    --predict) PREDICT="$2"; shift 2 ;;
    --ngl) NGPU="$2"; shift 2 ;;
    --flash) FLASH="$2"; shift 2 ;;
    --build-cli) BUILD_CLI=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Bilinmeyen argüman: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$MODEL" ]]; then
  echo "HATA: --model gerekli" >&2
  usage
  exit 1
fi
if [[ ! -f "$MODEL" ]]; then
  echo "HATA: model dosyası yok: $MODEL" >&2
  exit 1
fi

ensure_cli() {
  if [[ -x "$CLI" ]]; then
    return
  fi
  if [[ "$BUILD_CLI" -ne 1 ]]; then
    echo "HATA: $CLI bulunamadı. --build-cli ile derleyin veya Scripts/build-llama-xcframework.sh çalıştırın." >&2
    exit 1
  fi
  if [[ ! -d "$LLAMA_DIR" ]]; then
    echo "HATA: Vendor/llama.cpp yok" >&2
    exit 1
  fi
  echo "==> llama-cli derleniyor..."
  cmake -S "$LLAMA_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DLLAMA_BUILD_TOOLS=ON \
    -DLLAMA_BUILD_COMMON=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON
  cmake --build "$BUILD_DIR" -j "$(sysctl -n hw.ncpu)" --target llama-cli
}

parse_perf() {
  local log="$1"
  local prompt_ms prompt_tps eval_ms eval_tps
  prompt_ms="$(echo "$log" | sed -n 's/.*prompt eval time =[[:space:]]*\([0-9.]*\) ms.*/\1/p' | tail -1)"
  prompt_tps="$(echo "$log" | sed -n 's/.*prompt eval time =.*(\([0-9.]*\) tokens per second).*/\1/p' | tail -1)"
  eval_ms="$(echo "$log" | sed -n 's/.*eval time =[[:space:]]*\([0-9.]*\) ms.*/\1/p' | tail -1)"
  eval_tps="$(echo "$log" | sed -n 's/.*eval time =.*(\([0-9.]*\) tokens per second).*/\1/p' | tail -1)"
  echo "${prompt_ms:-?} ${prompt_tps:-?} ${eval_ms:-?} ${eval_tps:-?}"
}

ensure_cli

echo "==> bench-inference"
echo "    model:  $MODEL"
echo "    prompt: $PROMPT"
echo "    turns:  $TURNS"
echo ""

CONTEXT=""
printf "%-4s %-12s %-14s %-12s %-14s\n" "Tur" "prompt_ms" "prompt_tok/s" "eval_ms" "eval_tok/s"
printf "%-4s %-12s %-14s %-12s %-14s\n" "----" "----------" "------------" "----------" "------------"

for ((turn = 1; turn <= TURNS; turn++)); do
  FULL_PROMPT="${CONTEXT}User: ${PROMPT}
Assistant:"
  LOG="$(
    "$CLI" \
      -m "$MODEL" \
      -p "$FULL_PROMPT" \
      -n "$PREDICT" \
      --perf \
      -ngl "$NGPU" \
      -fa "$FLASH" \
      --no-warmup \
      --log-disable \
      2>&1 || true
  )"
  read -r prompt_ms prompt_tps eval_ms eval_tps <<< "$(parse_perf "$LOG")"
  printf "%-4s %-12s %-14s %-12s %-14s\n" "$turn" "$prompt_ms" "$prompt_tps" "$eval_ms" "$eval_tps"

  # Son üretilen metni bağlama ekle (basit çok tur simülasyonu)
  REPLY="$(echo "$LOG" | awk '/^Assistant:/{found=1; next} found{print}' | head -c 200 | tr '\n' ' ')"
  CONTEXT="${FULL_PROMPT}${REPLY}
"
done

echo ""
echo "==> Tamamlandı (yüksek prompt_tok/s ve düşük prompt_ms sonraki turlarda KV reuse işaretidir)"
