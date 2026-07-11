#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m4_v1.sh

if ! git grep -q 'mock_http_server.py' -- pixel/scripts/run_tests.sh pixel/tests; then
  echo "M4-1 local HTTP fixture server is not wired into the test gate." >&2
  exit 1
fi

if ! git grep -q '\[REDACTED\]' -- pixel/infra/http_client.gd pixel/tests; then
  echo "M4-1 sensitive header redaction guard is missing." >&2
  exit 1
fi

echo "verify_m4_1: ok"
