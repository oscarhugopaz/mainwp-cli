# shellcheck shell=bash
# updates.sh - Update listing, running, and ignore management.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_updates_help() {
	cat <<EOF
updates - Inspect and run WordPress core, plugin, theme, translation updates

Usage:
  mainwp updates SUBCOMMAND [OPTIONS] [ARGS...]

Listing:
  list [--type T]          List available updates (T: all|wp|plugins|themes|translations)
  for-site ID [--type T]   List updates for a single site
  ignored [--type T]       List globally ignored updates
  site-ignored ID          List ignored updates for a single site

Running:
  run-all [--type T]                Trigger update-all across the dashboard
  run-site ID [--type T]            Trigger update-all on one site
  wp ID                            Update WordPress core on one site
  plugins ID [--slug S]             Update plugins on one site
  themes ID [--slug S]              Update themes on one site
  translations ID                   Update translations on one site

Ignore management:
  ignore-wp ID                      Ignore a core update on one site
  ignore-plugins ID [--slug S]      Ignore plugin updates on one site
  ignore-themes ID [--slug S]       Ignore theme updates on one site
EOF
}

cmd_updates() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_updates_list "$@" ;;
	for-site) cmd_updates_site_list "$@" ;;
	ignored) cmd_updates_ignored "$@" ;;
	site-ignored) cmd_updates_site_ignored "$@" ;;
	run-all) cmd_updates_run_all "$@" ;;
	run-site) cmd_updates_run_site "$@" ;;
	wp) cmd_updates_run wp "$@" ;;
	plugins) cmd_updates_run plugins "$@" ;;
	themes) cmd_updates_run themes "$@" ;;
	translations) cmd_updates_run translations "$@" ;;
	ignore-wp) cmd_updates_ignore wp "$@" ;;
	ignore-plugins) cmd_updates_ignore plugins "$@" ;;
	ignore-themes) cmd_updates_ignore themes "$@" ;;
	-h | --help | help) cmd_updates_help ;;
	*) mainwp_die "Unknown updates subcommand: '$sub'" ;;
	esac
}

# ---- listing ---------------------------------------------------------

cmd_updates_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get /updates "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_updates_site_list() {
	local id="${1:?Usage: mainwp updates for-site ID}"
	shift
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get "/updates/$id" "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_updates_ignored() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get /updates/ignored "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_updates_site_ignored() {
	local id="${1:?Usage: mainwp updates site-ignored ID}"
	shift
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get "/updates/$id/ignored" "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

# ---- running ---------------------------------------------------------

cmd_updates_run_all() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_spinner "Triggering update-all..." mainwp_api_post /updates/update "" "${MAINWP_KV_FLAGS[@]:-}")"
	mainwp_success "Update-all dispatched."
	printf '%s' "$response" | mainwp_render_object
}

cmd_updates_run_site() {
	local id="${1:?Usage: mainwp updates run-site ID}"
	shift
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_spinner "Updating site $id..." mainwp_api_post "/updates/$id/update" "" "${MAINWP_KV_FLAGS[@]:-}")"
	mainwp_success "Update dispatched."
	printf '%s' "$response" | mainwp_render_object
}

cmd_updates_run() {
	local kind="$1" id="${2:?missing site ID}"
	shift 2
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	if [[ ${#MAINWP_KV_FLAGS[@]} -gt 0 ]]; then
		# Plugins/themes/translations may accept a "slug" kv to scope the run.
		response="$(mainwp_api_post "/updates/$id/update/$kind" "" "${MAINWP_KV_FLAGS[@]:-}")"
	else
		response="$(mainwp_api_post "/updates/$id/update/$kind")"
	fi
	mainwp_success "$kind update dispatched."
	printf '%s' "$response" | mainwp_render_object
}

# ---- ignoring --------------------------------------------------------

cmd_updates_ignore() {
	local kind="$1" id="${2:?missing site ID}"
	shift 2
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local body=""
	if [[ ${#MAINWP_KV_FLAGS[@]} -gt 0 ]]; then
		body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
	fi
	local response
	response="$(mainwp_api_post "/updates/$id/ignore/$kind" "$body")"
	mainwp_success "$kind ignore dispatched."
	printf '%s' "$response" | mainwp_render_object
}
