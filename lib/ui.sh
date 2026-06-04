# shellcheck shell=bash
# ui.sh - Interactive prompts built on gum (with read fallbacks).

# Pretty prompt for free-form text. Uses gum when interactive and the
# binary is available, otherwise falls back to read.
#
# Usage: mainwp_ui_input "Prompt" [default]
# Echoes the user's reply to stdout.
mainwp_ui_input() {
	local prompt="$1" default="${2:-}"
	if [[ $MAINWP_INTERACTIVE -eq 0 ]]; then
		printf '%s' "$default"
		return 0
	fi
	if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
		if [[ -n "$default" ]]; then
			gum input --prompt "$prompt " --value "$default" --placeholder "press enter for default"
		else
			gum input --prompt "$prompt " --placeholder "type a value"
		fi
	else
		local reply
		if [[ -n "$default" ]]; then
			read -r -p "$prompt [$default]: " reply
			printf '%s' "${reply:-$default}"
		else
			read -r -p "$prompt: " reply
			printf '%s' "$reply"
		fi
	fi
}

# Password-style prompt that masks input. Falls back to read -s.
# Usage: mainwp_ui_password "Prompt"
mainwp_ui_password() {
	local prompt="$1"
	if [[ $MAINWP_INTERACTIVE -eq 0 ]]; then
		return 1
	fi
	if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
		gum input --password --prompt "$prompt "
	else
		local reply
		read -r -s -p "$prompt: " reply
		printf '\n' >&2
		printf '%s' "$reply"
	fi
}

# Multi-choice prompt. Echoes the selected value (or empty if cancelled).
# Usage: mainwp_ui_choose "Prompt" "opt1" "opt2" ...
mainwp_ui_choose() {
	local prompt="$1"
	shift
	if [[ $MAINWP_INTERACTIVE -eq 0 ]]; then
		mainwp_die "Cannot prompt for selection in non-interactive mode."
	fi
	if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
		gum choose --prompt "$prompt" --height 10 "$@"
	else
		local i=1 selection reply
		for opt in "$@"; do
			printf '  %2d) %s\n' "$i" "$opt"
			i=$((i + 1))
		done
		read -r -p "$prompt [1]: " reply
		selection="${reply:-1}"
		if ! [[ "$selection" =~ ^[0-9]+$ ]] || ((selection < 1 || selection > $#)); then
			mainwp_die "Invalid selection: $selection"
		fi
		printf '%s' "${!selection}"
	fi
}

# Fuzzy-filter a list. Reads newline-delimited items from stdin and prints
# the chosen one to stdout. Falls back to gum filter; if gum is missing
# in interactive mode, the first line is returned.
mainwp_ui_filter() {
	local prompt="$1"
	if [[ $MAINWP_INTERACTIVE -eq 0 ]]; then
		mainwp_die "Cannot filter in non-interactive mode."
	fi
	if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
		gum filter --prompt "$prompt" --height 15
	else
		head -n 1
	fi
}
