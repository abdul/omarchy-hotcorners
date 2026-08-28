#!/bin/bash
# Rewrite this plugin's managed keybinding block in the user's Hyprland
# bindings, then reload Hyprland.
#
#   apply-binding.sh "SUPER + SHIFT + H"   bind (replacing any previous one)
#   apply-binding.sh ""                    remove the binding
#
# Only ever touches the block between its own markers; everything else in the
# file is left byte-for-byte alone.

set -uo pipefail

shortcut="${1:-}"
file="$HOME/.config/hypr/bindings.lua"
begin="-- >>> hotcorners (managed by the hotcorners plugin) >>>"
end="-- <<< hotcorners <<<"
action="omarchy-shell hotcorners-settings toggle"

[[ -f $file ]] || { echo "no bindings file at $file" >&2; exit 1; }

# The shortcut lands inside a quoted Lua string, so accept only the modifier
# and key vocabulary Omarchy uses and reject anything else outright.
if [[ -n $shortcut ]] && ! [[ $shortcut =~ ^[A-Za-z0-9_]+( \+ [A-Za-z0-9_]+)*$ ]]; then
  echo "refusing to write malformed shortcut: $shortcut" >&2
  exit 1
fi

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT

# Drop any existing managed block.
awk -v b="$begin" -v e="$end" '
  $0 == b { skip = 1 }
  !skip   { print }
  $0 == e { skip = 0 }
' "$file" > "$tmp" || exit 1

# Collapse trailing blank lines so repeated saves do not grow the file.
while [[ -s $tmp && -z $(tail -n 1 "$tmp") ]]; do
  sed -i '$d' "$tmp"
done

if [[ -n $shortcut ]]; then
  {
    echo
    echo "$begin"
    echo "o.bind(\"$shortcut\", \"Hot corners\", \"$action\")"
    echo "$end"
  } >> "$tmp"
fi

cp "$tmp" "$file" || exit 1
hyprctl reload >/dev/null 2>&1
exit 0
