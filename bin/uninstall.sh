#!/bin/bash
# Undo everything this plugin wrote outside its own directory.
#
# `omarchy plugin remove` deletes the plugin folder but runs no hooks, so run
# this first if you want the keybinding and settings gone too:
#
#   ~/.config/omarchy/plugins/abdul.hotcorners/bin/uninstall.sh
#   omarchy plugin remove abdul.hotcorners
#
# Pass --keep-config to drop only the keybinding.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config="$HOME/.config/omarchy/hotcorners.json"

# Removes this plugin's managed block from ~/.config/hypr/bindings.lua and
# reloads Hyprland. Safe when no block is present.
"$here/apply-binding.sh" "" && echo "removed the managed keybinding"

if [[ ${1:-} != "--keep-config" ]]; then
  if [[ -f $config ]]; then
    rm -f "$config" && echo "removed $config"
  fi
fi

cat <<'NOTE'

Two things this cannot do for you:
  - the menu entry, if you added one, is yours to delete from
    ~/.config/omarchy/extensions/omarchy-menu.jsonc
  - run `omarchy plugin remove abdul.hotcorners` to remove the plugin itself
NOTE
