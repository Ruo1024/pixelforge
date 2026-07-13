#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

metadata=".godot/editor/project_metadata.cfg"
mkdir -p "$(dirname "${metadata}")"

if [[ ! -f "${metadata}" ]]; then
  cat >"${metadata}" <<'EOF'
[game_view]

select_mode=1
embed_size_mode=2
hide_selection=false
EOF
else
  tmp="$(mktemp)"
  awk '
  BEGIN {
    in_game_view = 0
    saw_game_view = 0
    wrote_embed_size = 0
  }
  /^\[game_view\]$/ {
    in_game_view = 1
    saw_game_view = 1
    print
    next
  }
  /^\[/ {
    if (in_game_view && !wrote_embed_size) {
      print "embed_size_mode=2"
      wrote_embed_size = 1
    }
    in_game_view = 0
  }
  in_game_view && /^embed_size_mode=/ {
    print "embed_size_mode=2"
    wrote_embed_size = 1
    next
  }
  { print }
  END {
    if (!saw_game_view) {
      print ""
      print "[game_view]"
      print ""
      print "embed_size_mode=2"
    } else if (in_game_view && !wrote_embed_size) {
      print "embed_size_mode=2"
    }
  }
' "${metadata}" >"${tmp}"
  mv "${tmp}" "${metadata}"
fi

configure_editor_settings() {
  local settings="$1"
  [[ -f "${settings}" ]] || return 0

  local tmp_settings
  tmp_settings="$(mktemp)"
  awk '
    BEGIN {
      wrote_game_embed_mode = 0
    }
    /^run\/window_placement\/game_embed_mode = / {
      print "run/window_placement/game_embed_mode = -1"
      wrote_game_embed_mode = 1
      next
    }
    { print }
    END {
      if (!wrote_game_embed_mode) {
        print "run/window_placement/game_embed_mode = -1"
      }
    }
  ' "${settings}" >"${tmp_settings}"
  mv "${tmp_settings}" "${settings}"
  echo "configure_editor_game_view: selected an independent game window in ${settings}"
}

configure_editor_settings "${HOME}/Library/Application Support/Godot/editor_settings-4.6.tres"
configure_editor_settings "${HOME}/.config/godot/editor_settings-4.6.tres"
if [[ -n "${APPDATA:-}" ]]; then
  configure_editor_settings "${APPDATA}/Godot/editor_settings-4.6.tres"
fi

echo "configure_editor_game_view: kept Stretch to Fit as the per-project embedded fallback"

if pgrep -f "[G]odot" >/dev/null 2>&1; then
  echo "configure_editor_game_view: restart the Godot editor so these settings are loaded" >&2
fi
