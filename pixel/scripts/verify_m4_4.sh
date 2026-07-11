#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m4_3.sh

if ! rg -q 'MODEL_ID := "gpt-image-2"' pixel/plugins/provider_openai/openai_image_provider.gd; then
  echo "M4-4 GPT Image 2 model binding is missing." >&2
  exit 1
fi

if ! rg -q '"background": "transparent"' pixel/plugins/provider_openai/openai_image_provider.gd; then
  echo "M4-4 transparent PNG request contract is missing." >&2
  exit 1
fi

if ! rg -q 'test_generate_uses_shared_http_worker_decode' pixel/tests; then
  echo "M4-4 shared HTTP worker-decode coverage is missing." >&2
  exit 1
fi

secret_pattern='sk-[a-zA-Z0-9_-]{32,}'
if rg "${secret_pattern}" pixel pixelforge-plan; then
  echo "M4-4 possible OpenAI credential leak detected." >&2
  exit 1
fi

echo "verify_m4_4: ok"
