#!/usr/bin/env bash
# MacLLM kalite kapısı: hızlı testler, Swift parse ve açılış smoke.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

run_xcodebuild_with_timeout() {
  local timeout_seconds="${XCODEBUILD_TIMEOUT_SECONDS:-180}"
  local log="$ROOT/build/xcodebuild-quality-gate.log"

  mkdir -p "$ROOT/build"
  rm -f "$log"

  xcodebuild \
    -project MacLLM.xcodeproj \
    -scheme MacLLM \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build >"$log" 2>&1 &

  local build_pid=$!
  local elapsed=0
  while kill -0 "$build_pid" 2>/dev/null; do
    if (( elapsed >= timeout_seconds )); then
      echo "HATA: xcodebuild ${timeout_seconds} saniye içinde tamamlanmadı."
      echo "      Son log satırları:"
      tail -80 "$log" || true
      pkill -P "$build_pid" 2>/dev/null || true
      kill "$build_pid" 2>/dev/null || true
      killall SWBBuildService 2>/dev/null || true
      pkill -f "clang -v -E -dM" 2>/dev/null || true
      wait "$build_pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  local status=0
  wait "$build_pid" || status=$?
  if (( status != 0 )); then
    echo "HATA: xcodebuild başarısız oldu."
    tail -120 "$log" || true
    return "$status"
  fi

  tail -40 "$log" || true
}

echo "==> kalite kapısı: unit testler"
./Scripts/run-unit-tests.sh

echo "==> kalite kapısı: Swift parse"
swiftc -parse $(rg --files MacLLM Tests -g '*.swift')

echo "==> kalite kapısı: smoke test"
./Scripts/smoke-test.sh

if [[ "${RUN_XCODEBUILD:-0}" == "1" ]]; then
  echo "==> kalite kapısı: xcodebuild"
  echo "    Not: Xcode 26.5 ortamında SWBBuildService/clang -dM kilidi görülebilir."
  run_xcodebuild_with_timeout
else
  echo "==> xcodebuild atlandı (çalıştırmak için RUN_XCODEBUILD=1 ./Scripts/quality-gate.sh)"
fi

echo "==> kalite kapısı başarılı"
