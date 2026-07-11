#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

readonly SOURCE_DIRS=(core infra plugins services ui)
readonly SECRET_PATTERN='(sk|rdpk)-[A-Za-z0-9_-]{16,}'

if rg -n --glob '*.gd' --glob '*.json' --glob '*.cfg' -e "${SECRET_PATTERN}" "${SOURCE_DIRS[@]}" project.godot; then
  echo "Credential-like plaintext found in production resources." >&2
  exit 1
fi

if git ls-files | rg -i '(^|/)(credentials|secrets?)\.cfg$'; then
  echo "Credential store file is tracked by git." >&2
  exit 1
fi

rg -q 'test_secret_roundtrip_uses_ciphertext_and_no_plaintext' tests/unit/test_credential_store.gd
rg -q 'test_sensitive_headers_are_redacted_for_request_logs' tests/integration/test_http_client.gd
rg -q 'PLUGIN_SECURITY_WARNING' ui/dialogs/plugin_manager_dialog.gd ui/shell/strings.gd

echo "v1 security audit: ok"
