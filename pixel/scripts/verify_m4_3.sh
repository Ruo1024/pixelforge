#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m4_2.sh

if ! rg -q 'X-RD-Token' pixel/plugins/provider_retrodiffusion/retrodiffusion_provider.gd; then
  echo "M4-3 RetroDiffusion authentication header is missing." >&2
  exit 1
fi

if ! rg -q 'worker_transform.*true' pixel/plugins/provider_retrodiffusion/retrodiffusion_provider.gd; then
  echo "M4-3 worker-thread image decode is missing." >&2
  exit 1
fi

if ! rg -q 'test_verified_graph_runs_through_ui_cloud_provider_flow' pixel/tests; then
  echo "M4-3 UI-to-provider graph coverage is missing." >&2
  exit 1
fi

secret_pattern='rdpk-[a-z0-9]{20,}|X-RD'
secret_pattern+='-Token: [^%]'
if rg -i --glob '!*.uid' "${secret_pattern}" pixel pixelforge-plan; then
  echo "M4-3 possible RetroDiffusion credential leak detected." >&2
  exit 1
fi

echo "verify_m4_3: ok"
