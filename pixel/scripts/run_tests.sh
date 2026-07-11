#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

GODOT="$(find_godot)"
prepare_godot_env
import_godot_project "${GODOT}"

http_port_file="$(mktemp)"
http_server_pid=""
cleanup_http_fixture() {
  if [[ -n "${http_server_pid}" ]]; then
    kill "${http_server_pid}" 2>/dev/null || true
    wait "${http_server_pid}" 2>/dev/null || true
  fi
  rm -f "${http_port_file}"
}
trap cleanup_http_fixture EXIT

python3 tests/fixtures/http/mock_http_server.py "${http_port_file}" &
http_server_pid=$!
for _attempt in {1..100}; do
  if [[ -s "${http_port_file}" ]]; then
    break
  fi
  sleep 0.02
done
if [[ ! -s "${http_port_file}" ]]; then
  echo "Local HTTP fixture server did not start." >&2
  exit 1
fi
export PF_HTTP_MOCK_URL="http://127.0.0.1:$(<"${http_port_file}")"

"${GODOT}" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gno_error_tracking -gexit
