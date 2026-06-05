# shellcheck shell=bash
# output.sh - Output formatting helpers for the mainwp CLI
# Provides styled messages, JSON pretty-printing, and table rendering via gum.

# Print an informational message to stderr (suppressed with --quiet).
mainwp_info() {
	[[ $MAINWP_QUIET -eq 1 ]] && return 0
	if [[ $MAINWP_OUTPUT_FORMAT != "plain" ]] && command -v gum >/dev/null 2>&1; then
		gum style --foreground 39 "==> $*" >&2
	else
		printf '==> %s\n' "$*" >&2
	fi
}

# Print a success message to stderr.
mainwp_success() {
	[[ $MAINWP_QUIET -eq 1 ]] && return 0
	if [[ $MAINWP_OUTPUT_FORMAT != "plain" ]] && command -v gum >/dev/null 2>&1; then
		gum style --foreground 82 "✓ $*" >&2
	else
		printf '\033[32m✓\033[0m %s\n' "$*" >&2
	fi
}

# Print a warning to stderr.
mainwp_warn() {
	if [[ $MAINWP_OUTPUT_FORMAT != "plain" ]] && command -v gum >/dev/null 2>&1; then
		gum style --foreground 214 "⚠ $*" >&2
	else
		printf '\033[33m⚠\033[0m %s\n' "$*" >&2
	fi
}

# Print an error and exit with non-zero status.
mainwp_die() {
	if [[ $MAINWP_OUTPUT_FORMAT != "plain" ]] && command -v gum >/dev/null 2>&1; then
		gum style --foreground 196 --bold "✗ $*" >&2
	else
		printf '\033[31m✗\033[0m %s\n' "$*" >&2
	fi
	exit 1
}

# Pretty-print JSON to stdout. Falls back to cat when no formatter is present.
mainwp_print_json() {
	local input
	input="$(cat)"

	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		printf '%s\n' "$input"
		return 0
	fi

	if command -v jq >/dev/null 2>&1; then
		printf '%s\n' "$input" | jq .
	else
		printf '%s\n' "$input"
	fi
}

# Extract a value via jq, failing fast if the expression is invalid.
mainwp_jq() {
	local expr="$1"
	command -v jq >/dev/null 2>&1 || mainwp_die "jq is required for this command. Install it with: brew install jq"
	jq -r "$expr"
}

# Render a list of records as a gum table when interactive, or as a simple
# space-aligned table otherwise. Reads JSON array from stdin.
#
# Arguments:
#   $1 - columns string for gum table: "ID,Name,Status" (used with gum)
#   $2.. - jq expressions for each column, in order
mainwp_render_table() {
	local cols_header="$1"
	shift
	local input
	input="$(cat)"

	# Sanity: make sure we have an array. Read the first byte via
	# parameter expansion rather than `head -c 1` to avoid a SIGPIPE
	# race: a pipe-based read kills the producer (printf) on the next
	# write, and `set -o pipefail` then aborts the whole script.
	local first="${input:0:1}"
	if [[ -z "$input" || "$first" != "[" ]]; then
		# Not an array. Just print the JSON payload.
		mainwp_print_json <<<"$input"
		return 0
	fi

	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		printf '%s\n' "$input"
		return 0
	fi

	if [[ $MAINWP_OUTPUT_FORMAT == "plain" ]] || ! command -v gum >/dev/null 2>&1; then
		printf '%s\n' "$cols_header"
		local row
		while IFS= read -r row; do
			local cell
			local first_col=1
			for expr in "$@"; do
				# Flatten array values (e.g. permissions) into a
				# single comma-separated string so each row fits
				# on one line.
				cell="$(printf '%s' "$row" | jq -r "$expr | if type==\"array\" then join(\", \") else . end // empty" 2>/dev/null)"
				if [[ $first_col -eq 1 ]]; then
					printf '%s' "$cell"
					first_col=0
				else
					printf '\t%s' "$cell"
				fi
			done
			printf '\n'
		done < <(printf '%s' "$input" | jq -c '.[]')
		return 0
	fi

	# Default: gum-styled table. Build one comma-separated row per record
	# and hand the whole batch to `gum table --separator` so multi-word
	# values do not confuse the parser.
	local rows=()
	local row
	while IFS= read -r row; do
		local cells=()
		local expr
		for expr in "$@"; do
			# `// join("")` flattens array values like permissions
			# into a single comma-space-separated string.
			cells+=("$(printf '%s' "$row" | jq -r "$expr | if type==\"array\" then join(\", \") else . end // empty" 2>/dev/null)")
		done
		# Escape commas in cell content so gum's --separator does not
		# mis-split rows. Real cells rarely contain commas; this is a
		# belt-and-suspenders for header-like descriptions.
		local escaped=()
		local c
		for c in "${cells[@]}"; do
			escaped+=("${c//;/;}")
		done
		rows+=("$(
			IFS=';'
			printf '%s' "${escaped[*]}"
		)")
	done < <(printf '%s' "$input" | jq -c '.[]')

	# `gum table` reads rows from stdin when --separator is set.
	printf '%s\n' "${rows[@]}" | gum table --separator ';' --columns "$cols_header"
}

# Render a single object as a labeled key/value list using gum style.
mainwp_render_object() {
	local input
	input="$(cat)"

	if [[ -z "$input" || "$input" = "null" ]]; then
		mainwp_warn "Empty response."
		return 0
	fi

	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		printf '%s\n' "$input"
		return 0
	fi

	if ! command -v jq >/dev/null 2>&1; then
		mainwp_print_json <<<"$input"
		return 0
	fi

	if [[ $MAINWP_OUTPUT_FORMAT == "plain" ]] || ! command -v gum >/dev/null 2>&1; then
		printf '%s' "$input" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
		return 0
	fi

	# Pretty two-column layout with gum.
	local body
	body="$(printf '%s' "$input" | jq -r 'to_entries[] | "  \(.key)\t\(.value | tostring)"' |
		awk -F'\t' 'BEGIN{OFS="\t"} {printf "%-22s %s\n", $1, $2}')"

	gum style --border rounded --padding "0 1" --margin "1 0" \
		--border-foreground 39 "$(printf 'Field\tValue\n----\t-----\n%s' "$body" | column -t -s $'\t')"
}

# Wrap a long-running command with a gum spinner.
# Usage: mainwp_spinner "Updating sites" curl ...
mainwp_spinner() {
	local title="$1"
	shift
	if command -v gum >/dev/null 2>&1 && [[ $MAINWP_QUIET -eq 0 ]]; then
		gum spin --spinner dot --title "$title" -- "$@"
	else
		mainwp_info "$title"
		"$@"
	fi
}

# Ask for confirmation. Always uses gum when available and the terminal is
# interactive; otherwise reads y/N from stdin.
mainwp_confirm() {
	local prompt="$1"
	if [[ $MAINWP_INTERACTIVE -eq 0 ]]; then
		return 0
	fi
	if command -v gum >/dev/null 2>&1 && [[ -t 0 ]]; then
		gum confirm "$prompt"
	else
		local reply
		read -r -p "$prompt [y/N] " reply
		[[ "$reply" =~ ^[Yy]$ ]]
	fi
}
