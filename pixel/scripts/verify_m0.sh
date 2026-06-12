#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[M0 verify] lint"
./scripts/lint.sh

echo "[M0 verify] tests"
./scripts/run_tests.sh

echo "[M0 verify] headless/export-template check"
./scripts/check_export_templates.sh

echo "[M0 verify] completed"
