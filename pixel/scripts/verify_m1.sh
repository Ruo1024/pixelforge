#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

EXPECTED_GUT_ORPHANS=1
TEST_LOG="$(mktemp)"
trap 'rm -f "${TEST_LOG}"' EXIT

echo "[M1 verify] lint"
./scripts/lint.sh

echo "[M1 verify] tests"
./scripts/run_tests.sh 2>&1 | tee "${TEST_LOG}"
orphan_count="$(grep -Eo '[0-9]+ Orphans' "${TEST_LOG}" | tail -n 1 | awk '{print $1}')"
orphan_count="${orphan_count:-0}"
if [[ "${orphan_count}" != "${EXPECTED_GUT_ORPHANS}" ]]; then
  echo "Expected ${EXPECTED_GUT_ORPHANS} GUT orphan(s), got ${orphan_count}." >&2
  exit 1
fi

echo "[M1 verify] performance sample"
source scripts/_godot_path.sh
GODOT="$(find_godot)"
prepare_godot_env
import_godot_project "${GODOT}"
"${GODOT}" --headless --script res://scripts/measure_m1.gd

echo "[M1 verify] headless/export-template check"
./scripts/check_export_templates.sh

echo "[M1 verify] completed"
