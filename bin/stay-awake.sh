#!/usr/bin/env bash
# Temporarily suppress Omarchy idle behavior while the pointer is in the
# Stay awake hot corner, restoring the state that was in effect beforehand.
set -euo pipefail

state_dir="$HOME/.local/state/omarchy/indicators"
idle_state="$state_dir/stay-awake"
marker="$state_dir/hotcorners-stay-awake-original-state"
mkdir -p "$state_dir"
exec 9>"$state_dir/hotcorners-stay-awake.lock"
flock -x 9

case "${1:-}" in
  enter)
    if [[ ! -e $marker ]]; then
      if [[ -e $idle_state ]]; then
        printf 'enabled\n' > "$marker"
      else
        printf 'disabled\n' > "$marker"
        touch "$idle_state"
      fi
    fi
    ;;
  leave|recover)
    if [[ -f $marker ]]; then
      if [[ $(<"$marker") == disabled ]]; then
        rm -f "$idle_state"
      fi
      rm -f "$marker"
    fi
    ;;
  *)
    echo "Usage: $0 {enter|leave|recover}" >&2
    exit 2
    ;;
esac
