#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m3_1.sh

if git grep -IEn 'sk-proj-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}' -- pixel pixelforge-plan; then
  echo "Potential live OpenAI API key found in tracked project content." >&2
  exit 1
fi

if ! git grep -q 'session_only.*true' -- pixel/plugins/provider_openai pixel/tests; then
  echo "OpenAI session-only credential contract is missing." >&2
  exit 1
fi

if ! git grep -q 'openai_image_success.json' -- pixel/tests; then
  echo "OpenAI recorded response fixture is not covered by tests." >&2
  exit 1
fi

echo "verify_m4_v1: engineering gate ok (real API and product experiment not included)"
