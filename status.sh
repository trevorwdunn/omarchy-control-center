#!/bin/bash

# State the Control Center cannot bind to directly, one "key=value" per line.
# Every command here answers in well under 100ms; it runs when the menu opens
# and every few seconds while it stays open.
#
#   $1  monitor the menu is on (for the brightness reading)

monitor=${1:-}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}

line() { printf '%s=%s\n' "$1" "$(tr -d '\n' <<<"$2")"; }

line dnd "$(omarchy-shell notifications dndState 2>/dev/null)"
line night "$(omarchy-toggle-nightlight --status 2>/dev/null)"
line idle "$(omarchy-shell idle status 2>/dev/null)"
line brightness "$(omarchy-brightness-display --monitor "$monitor" 2>/dev/null | head -n 1)"
line airdrop "$(omarchy-shell netmojo.omdrop status 2>/dev/null)"
line localsend "$(omarchy-shell bredda.localsend receiver status 2>/dev/null)"
line sink "$(omarchy-audio-output-sink 2>/dev/null)"

# Peripheral batteries nothing else reports: wireless headsets that only
# speak a vendor protocol, and AirPods through the librepods daemon.
if command -v headsetcontrol >/dev/null; then
  line headset "$(headsetcontrol -o json -b 2>/dev/null)"
fi
if [[ -r $state_home/librepods/status.json ]]; then
  line pods "$(cat "$state_home/librepods/status.json")"
fi
