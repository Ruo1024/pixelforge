#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m4_1.sh

if ! rg -q 'MODE_CBC_ENCRYPT' pixel/services/credential_store.gd; then
  echo "M4-2 AES-256-CBC credential storage is missing." >&2
  exit 1
fi

if ! rg -q 'test_pbkdf2_matches_sha256_reference_vector' pixel/tests; then
  echo "M4-2 PBKDF2 reference-vector coverage is missing." >&2
  exit 1
fi

if ! rg -q 'get_selectable_provider_ids' pixel/ui pixel/tests; then
  echo "M4-2 verified-provider node filtering is not covered." >&2
  exit 1
fi

echo "verify_m4_2: ok"
