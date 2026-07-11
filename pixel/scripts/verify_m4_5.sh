#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m4_4.sh

if ! rg -q 'record_cost' pixel/services/cost_service.gd pixel/ui/shell/openai_generation_controller.gd; then
  echo "M4-5 completed-task cost ledger is missing." >&2
  exit 1
fi

if ! rg -q 'ProviderBudgetDialog' pixel/ui pixel/tests; then
  echo "M4-5 budget confirmation UI is missing." >&2
  exit 1
fi

if ! rg -q 'test_mock_estimate_and_actual_month_ledger_are_exact' pixel/tests; then
  echo "M4-5 exact estimate/actual coverage is missing." >&2
  exit 1
fi

echo "verify_m4_5: ok"
