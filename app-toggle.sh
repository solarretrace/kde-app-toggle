#!/usr/bin/bash
# A script to toggle between a fixed application and the current window.
# Uses kdotool to query and activate windows.

# Return the error code of the first failure.
set -euo pipefail

if [[ $# -lt 2 ]]; then
	echo "Usage: $0 <window-class> <launch-command> [launch-args]...]" >&2
	exit 1
fi

# Parse arguments
APP_TOGGLE_CLASS="$1"
shift
APP_TOGGLE_LAUNCH_CMD=("$@")

# Derive a unique state file for the previous window. This prevents multiple
# shortcuts from conflicting with each other.
SAFE_CLASS_ID=$(echo "$APP_TOGGLE_CLASS" | tr -c 'A-Za-z0-9._-' '_')
APP_TOGGLE_STATE_FILE="/tmp/.app-toggle-prev-${USER}-${SAFE_CLASS_ID}"

# Get active window, exit if not relevant.
active_id=$(kdotool getactivewindow 2>/dev/null)
[[ -z "$active_id" ]] && exit 0

# Get active window class.
active_class=$(kdotool getwindowclassname "$active_id" 2>/dev/null)

# Get the fallback window if we haven't switched yet. We skip any windows with
# whitespace-only names, as these are probably background windows. A better
# check would be to filter KDE windows by skipTaskbar and skipSwitcher flags,
# but kdotool doesn't expose filters for those.
fallback_window() {
	local wid fallback_class
	while read -r wid; do
		[[ -z "$wid" ]] && continue
		fallback_class=$(kdotool getwindowclassname "$wid" 2>/dev/null) || continue
		[[ "$fallback_class" == "$APP_TOGGLE_CLASS" ]] && continue
		echo "$wid"
		return 0
	done < <(kdotool search --name '.*\S.*' 2>/dev/null)
	return 1
}

if [[ "$active_class" == "$APP_TOGGLE_CLASS" ]]; then
	# Already in the toggle class, check the state file for the switch target.
	prev_id=""
	[[ -f "$APP_TOGGLE_STATE_FILE" ]] && prev_id=$(cat "$APP_TOGGLE_STATE_FILE")
	if [[ -n "$prev_id" ]] && kdotool windowactivate "$prev_id" 2>/dev/null; then
		# Go back to the saved class.
		: # Success 
	else
		# No saved switch target or state file is missing; use fallback window.
		rm -f "$APP_TOGGLE_STATE_FILE"
		fallback_id=$(fallback_window) || true
		if [[ -n "$fallback_id:-}" ]]; then
			kdotool windowactivate "$fallback_id"
		fi
	fi
else
	# Save the current window class as toggle class, then switch.
	echo "$active_id" > "$APP_TOGGLE_STATE_FILE"
	target_id=$(kdotool search --class "$APP_TOGGLE_CLASS" 2>/dev/null | head -n1)
	if [[ -n "$target_id" ]]; then
		kdotool windowactivate "$target_id"
	else
		setsid -f "${APP_TOGGLE_LAUNCH_CMD[@]}" >/dev/null 2>&1
	fi
fi

