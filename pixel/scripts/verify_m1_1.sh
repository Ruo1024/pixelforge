#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[M1.1 verify] M1 regression gate"
./scripts/verify_m1.sh

echo "[M1.1 verify] coverage matrix"
./scripts/check_m1_1_coverage_matrix.sh

echo "[M1.1 verify] p95 performance regression band"
# M1.1 改进新增：性能此前只采样不门控。以 M1.1 完成报告实测 p95 为基线，
# 允许 1.3 倍漂移带；超出说明引入了真实性能回归（或环境异常，需人工确认）。
# 基线（2026-06-13，Apple M5 / Godot 4.6.3）：
#   palette_map_p95_ms      156.92 -> cap 204
#   grid_detect_p95_ms       76.94 -> cap 100
#   cleanup_pipeline_p95_ms 221.95 -> cap 289
PERF_LOG="$(mktemp)"
trap 'rm -f "${PERF_LOG}"' EXIT
source scripts/_godot_path.sh
GODOT="$(find_godot)"
prepare_godot_env
"${GODOT}" --headless --script res://scripts/measure_m1.gd 2>&1 | tee "${PERF_LOG}"

check_p95() {
  local key="$1" cap="$2"
  local value
  value="$(grep -Eo "\"${key}\": *[0-9.]+" "${PERF_LOG}" | tail -n 1 | grep -Eo '[0-9.]+$' || true)"
  if [[ -z "${value}" ]]; then
    echo "p95 metric ${key} not found in measure output." >&2
    exit 1
  fi
  if awk -v v="${value}" -v c="${cap}" 'BEGIN { exit !(v > c) }'; then
    echo "p95 regression: ${key}=${value}ms exceeds cap ${cap}ms (baseline x1.3)." >&2
    exit 1
  fi
  echo "p95 ok: ${key}=${value}ms (cap ${cap}ms)"
}

check_p95 "palette_map_p95_ms" 204
check_p95 "grid_detect_p95_ms" 100
check_p95 "cleanup_pipeline_p95_ms" 289

echo "[M1.1 verify] completed"

# --- milestone exit: working tree must be clean ---
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 工作区有未提交变更——里程碑出口要求 commit 后再签字"
  exit 1
fi
echo "✅ git working tree clean"
