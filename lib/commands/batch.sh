# shellcheck shell=bash
# batch.sh - Global batch orchestration endpoint.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_batch_help() {
	cat <<EOF
batch - Execute grouped operations across multiple controllers

Usage:
  mainwp batch FILE
  mainwp batch --json '<json payload>'

Reads a JSON payload describing one or more controllers (sites, clients,
updates, costs, tags) and POSTs it to /batch. Use the global batch when a
single request needs to span multiple controllers; otherwise prefer
controller-specific batch endpoints (sites/batch, clients/batch, ...).

The file or string MUST be a JSON object. See:
https://docs.mainwp.com/api-reference/rest-api/batch
EOF
}

cmd_batch() {
	local input=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--json)
			input="$2"
			shift 2
			;;
		-h | --help)
			cmd_batch_help
			return 0
			;;
		*)
			if [[ -z "$input" && -f "$1" ]]; then
				input="$(cat "$1")"
				shift
			else
				mainwp_die "Unknown argument: $1"
			fi
			;;
		esac
	done
	[[ -n "$input" ]] || mainwp_die "Provide a JSON file path or --json '<payload>'."

	# Validate JSON before sending.
	printf '%s' "$input" | jq . >/dev/null 2>&1 || mainwp_die "Payload is not valid JSON."

	local response
	response="$(mainwp_spinner "Running batch..." mainwp_api_post /batch "$input")"
	mainwp_success "Batch complete."
	printf '%s' "$response" | mainwp_render_object
}
