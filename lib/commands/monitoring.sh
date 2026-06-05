# shellcheck shell=bash
# monitoring.sh - Uptime monitors.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_monitoring_help() {
	cat <<EOF
monitoring - Manage uptime monitors

Usage:
  mainwp monitoring SUBCOMMAND [OPTIONS] [ARGS...]

  list                    List monitors (full metrics)
  basic                   List monitors (basic fields)
  count                   Count monitors
  get ID                  Get one monitor
  heartbeat ID            Get heartbeat history
  incidents ID            Get incident list
  incidents-count ID      Count incidents
  check ID                Trigger an immediate monitor check
  settings ID             Update one monitor's settings
  global-settings         Update global monitor defaults
EOF
}

cmd_monitoring() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_monitors_list /monitors "$@" ;;
	basic) cmd_monitors_list /monitors/basic "$@" ;;
	count) cmd_monitors_count "$@" ;;
	get) cmd_monitors_get "$@" ;;
	heartbeat) cmd_monitor_relationship heartbeat "$@" ;;
	incidents) cmd_monitor_relationship incidents "$@" ;;
	incidents-count) cmd_monitor_relationship incidents/count "$@" ;;
	check) cmd_monitor_check "$@" ;;
	settings) cmd_monitor_settings "$@" ;;
	global-settings) cmd_monitor_global_settings "$@" ;;
	-h | --help | help) cmd_monitoring_help ;;
	*) mainwp_die "Unknown monitoring subcommand: '$sub'" ;;
	esac
}

cmd_monitors_list() {
	local path="$1"
	shift
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get "$path" "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(_mainwp_extract_list "$response")"
	_mainwp_render_list "$arr" "ID,URL,Status" \
		'.id // empty' '.url // empty' '.status // empty'
}

cmd_monitors_count() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response total
	response="$(mainwp_api_get /monitors/count "${MAINWP_KV_FLAGS[@]:-}")"
	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		printf '%s\n' "$response"
	else
		total="$(printf '%s' "$response" | jq -r '.total // .data.total // 0')"
		mainwp_info "Monitors: $total"
	fi
}

cmd_monitors_get() {
	local id="${1:?Usage: mainwp monitoring get ID}"
	local response
	response="$(mainwp_api_get "/monitors/$id")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_monitor_relationship() {
	local rel="$1" id="${2:?missing ID}"
	shift 2
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get "/monitors/$id/$rel" "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_monitor_check() {
	local id="${1:?missing ID}"
	local response
	response="$(mainwp_api_post "/monitors/$id/check")"
	mainwp_success "Monitor check dispatched."
	printf '%s' "$response" | mainwp_render_object
}

cmd_monitor_settings() {
	local id="${1:?missing ID}"
	shift
	eval "$(_mainwp_collect_kv_flags)"
	local body
	body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
	local response
	response="$(mainwp_api_post "/monitors/$id/settings" "$body")"
	mainwp_success "Monitor settings updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_monitor_global_settings() {
	eval "$(_mainwp_collect_kv_flags)"
	local body
	body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
	local response
	response="$(mainwp_api_post /monitors/settings "$body")"
	mainwp_success "Global monitor defaults updated."
	printf '%s' "$response" | mainwp_render_object
}
