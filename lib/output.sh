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

	# Decide between the plain fallback and the gum-styled table.
	# gum is only useful when stdout is a TTY: when it is not, gum
	# tries to open /dev/tty for its alternate-screen buffer and
	# fails with a non-zero exit, swallowing the output. By
	# requiring -t 1 we make the fallback automatic for pipes,
	# redirections, and CI.
	if [[ $MAINWP_OUTPUT_FORMAT == "plain" ]] || ! command -v gum >/dev/null 2>&1 || [[ ! -t 1 ]]; then
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

	# TTY + gum available: render a styled table. Build one ;-separated
	# row per record and hand the whole batch to `gum table`. We use
	# `;` as the separator (instead of the default `,`) so commas in
	# description-style cells do not split a row into the wrong
	# number of columns.
	local rows=()
	local row
	while IFS= read -r row; do
		local cells=()
		local expr
		for expr in "$@"; do
			cells+=("$(printf '%s' "$row" | jq -r "$expr | if type==\"array\" then join(\", \") else . end // empty" 2>/dev/null)")
		done
		# Defensively escape any literal `;` in cell content.
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

	# If gum fails for any reason (e.g. user is in a sub-shell with
	# no controlling terminal), fall back to plain. Capture both
	# stdout and stderr so the user sees gum's error if it ever
	# matters in the future.
	if ! printf '%s\n' "${rows[@]}" | gum table --separator ';' --columns "$cols_header"; then
		printf '%s\n' "$cols_header"
		local r
		for r in "${rows[@]}"; do
			# Convert ;-separated back to tabs for plain output.
			printf '%s\n' "${r//;/\	}"
		done
	fi
}

# Render a single object as a labeled key/value list using gum style.
#
# We deliberately avoid `column -t` here: it has a hard limit on line
# length and dies with "line too long" on payloads that include any
# large value (a long URL, an embedded JSON array, etc.), which used
# to swallow the entire output. Alignment is done with printf width
# specifiers, which has no such limit.
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

	# Build a two-column "Field | Value" layout. Printf width
	# specifiers (instead of `column -t`) keep this resilient to
	# very long values like URLs or embedded JSON.
	local body
	body="$(printf '%s' "$input" | jq -r '
		to_entries[] |
		"  \(.key)\t\(
			if type == "object" or type == "array"
			then tostring | gsub("\n"; " ")
			else tostring
			end
		)"
	')"

	# Compute a sensible label width: clamp between 12 and 36 so short
	# objects do not waste space and long ones still fit.
	local max_key=12
	local k
	while IFS= read -r k; do
		[[ ${#k} -gt $max_key ]] && max_key=${#k}
	done < <(printf '%s\n' "$body" | awk -F'\t' '{print $1}' | sed 's/^[[:space:]]*//')
	[[ $max_key -gt 36 ]] && max_key=36

	# Align: shell `printf "%-Ns"` pads to N; `awk` would also work.
	local aligned
	aligned="$(printf '%s\n' "$body" | awk -F'\t' -v w="$max_key" '{
		key = $1; sub(/^[[:space:]]+/, "", key)
		val = $2
		printf "  %-*s  %s\n", w, key, val
	}')"

	# Plain-text fallback: just print the aligned body.
	if [[ $MAINWP_OUTPUT_FORMAT == "plain" ]] || ! command -v gum >/dev/null 2>&1 || [[ ! -t 1 ]]; then
		printf '%s\n' "$aligned"
		return 0
	fi

	# Try gum styling; fall back to plain if anything goes wrong.
	if ! gum style --border rounded --padding "0 1" --margin "1 0" \
		--border-foreground 39 "$aligned"; then
		printf '%s\n' "$aligned"
	fi
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
