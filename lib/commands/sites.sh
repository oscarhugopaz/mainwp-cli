# shellcheck shell=bash
# sites.sh - Child site management (list, get, add, sync, plugins, themes, ...).
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_sites_help() {
	cat <<EOF
sites - Manage child sites

Usage:
  mainwp sites SUBCOMMAND [OPTIONS] [ARGS...]

List & Inspection:
  list                       List child sites
  basic                      List lightweight site records
  count                      Count child sites
  get ID_OR_DOMAIN           Show details for one site
  security ID_OR_DOMAIN      Show security snapshot
  non-mainwp-changes ID      List external/non-MainWP changes
  client ID_OR_DOMAIN        Show the client linked to a site
  costs ID_OR_DOMAIN         Show costs linked to a site
  plugins ID_OR_DOMAIN       List plugins on a site
  themes ID_OR_DOMAIN        List themes on a site

Write operations:
  add                        Add a child site (interactive or --url/--name/--admin)
  edit ID_OR_DOMAIN          Update site fields (--name, --client-id, ...)
  sync [ID_OR_DOMAIN]        Sync one site or all sites
  reconnect [ID_OR_DOMAIN]   Reconnect one site or all sites
  disconnect [ID_OR_DOMAIN]  Disconnect one site or all sites
  check [ID_OR_DOMAIN]       Run a connection check
  suspend ID                 Suspend a site
  unsuspend ID               Unsuspend a site
  remove ID                  Remove a site from the Dashboard

Plugin / theme actions (require ID_OR_DOMAIN):
  plugin activate ID SLUG    Activate a plugin
  plugin deactivate ID SLUG  Deactivate a plugin
  plugin delete ID SLUG      Delete a plugin
  theme activate ID SLUG     Activate a theme
  theme delete ID SLUG       Delete a theme

Common Filters:
  --per-page N               Results per page (default 20)
  --page N                   Page number
  --search TEXT              Search keyword
  --status STATUS            connected | disconnected | suspended | all
  --include IDS              Comma-separated site IDs
  --exclude IDS              Comma-separated site IDs
  --with-tags                Include tags in the response

Use \`mainwp sites SUBCOMMAND --help\` for per-subcommand options.
EOF
}

cmd_sites() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi

	case "$sub" in
	list) cmd_sites_list "$@" ;;
	basic) cmd_sites_basic "$@" ;;
	count) cmd_sites_count "$@" ;;
	get) cmd_sites_get "$@" ;;
	security) cmd_sites_security "$@" ;;
	non-mainwp-changes) cmd_sites_nonmainwp_changes "$@" ;;
	client) cmd_sites_client "$@" ;;
	costs) cmd_sites_costs "$@" ;;
	plugins) cmd_sites_plugins "$@" ;;
	themes) cmd_sites_themes "$@" ;;
	add) cmd_sites_add "$@" ;;
	edit) cmd_sites_edit "$@" ;;
	sync) cmd_sites_sync "$@" ;;
	reconnect) cmd_sites_reconnect "$@" ;;
	disconnect) cmd_sites_disconnect "$@" ;;
	check) cmd_sites_check "$@" ;;
	suspend) cmd_sites_site_toggle suspend "$@" ;;
	unsuspend) cmd_sites_site_toggle unsuspend "$@" ;;
	remove) cmd_sites_remove "$@" ;;
	plugin) cmd_sites_plugin "$@" ;;
	theme) cmd_sites_theme "$@" ;;
	-h | --help | help) cmd_sites_help ;;
	*) mainwp_die "Unknown sites subcommand: '$sub'" ;;
	esac
}

# ---- helpers --------------------------------------------------------

# Forward remaining REMAINING kv-flags as query string args to the API.
# Usage: _mainwp_forward_query_filter key=value ...
_mainwp_forward_query_filter() {
	local extra=()
	local pair
	for pair in "$@"; do
		extra+=("$pair")
	done
	printf '%s\n' "${extra[@]}"
}

# Pull a JSON array of child site records from any "data" envelope. If the
# response isn't wrapped, returns the input unchanged.
_mainwp_extract_sites() {
	local input="$1"
	if printf '%s' "$input" | jq -e 'type == "array"' >/dev/null 2>&1; then
		printf '%s' "$input"
	else
		printf '%s' "$input" | jq -c '.data // .sites // []'
	fi
}

# ---- list / count ---------------------------------------------------

cmd_sites_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get /sites "${MAINWP_KV_FLAGS[@]:-}")"
	local arr
	arr="$(_mainwp_extract_sites "$response")"
	_mainwp_render_list "$arr" "ID,Name,URL,Status" \
		'.id // empty' '.name // empty' '.url // empty' '.status // empty'
}

cmd_sites_basic() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /sites/basic "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(_mainwp_extract_sites "$response")"
	_mainwp_render_list "$arr" "ID,Name,URL" \
		'.id // empty' '.name // empty' '.url // empty'
}

cmd_sites_count() {
	local response
	response="$(mainwp_api_get /sites/count)"
	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		printf '%s\n' "$response"
	else
		# The MainWP /sites/count response is `{"count":N}` - check the
		# most likely field names so this works across endpoint
		# variants. The trailing `0` is the safe fallback.
		local total
		total="$(printf '%s' "$response" | jq -r '(.count // .total // .data.count // .data.total // 0) | tostring')"
		mainwp_info "Connected sites: $total"
	fi
}

cmd_sites_get() {
	local id="${1:?Usage: mainwp sites get ID_OR_DOMAIN}"
	local response
	response="$(mainwp_api_get "/sites/$id")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_security() {
	local id="${1:?Usage: mainwp sites security ID_OR_DOMAIN}"
	local response
	response="$(mainwp_api_get "/sites/$id/security")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_nonmainwp_changes() {
	local id="${1:?Usage: mainwp sites non-mainwp-changes ID_OR_DOMAIN}"
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get "/sites/$id/non-mainwp-changes" "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_client() {
	local id="${1:?Usage: mainwp sites client ID_OR_DOMAIN}"
	local response
	response="$(mainwp_api_get "/sites/$id/client")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_costs() {
	local id="${1:?Usage: mainwp sites costs ID_OR_DOMAIN}"
	local response
	response="$(mainwp_api_get "/sites/$id/costs")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_plugins() {
	local id="${1:?Usage: mainwp sites plugins ID_OR_DOMAIN}"
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get "/sites/$id/plugins" "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(_mainwp_extract_sites "$response")"
	# Plugins endpoints often return an object keyed by slug, not an array.
	if printf '%s' "$arr" | jq -e 'type == "object"' >/dev/null 2>&1; then
		printf '%s' "$arr" | mainwp_render_object
	else
		_mainwp_render_list "$arr" "Slug,Name,Status" \
			'.slug // . // empty' '.Name // .name // empty' '.Status // .status // empty'
	fi
}

cmd_sites_themes() {
	local id="${1:?Usage: mainwp sites themes ID_OR_DOMAIN}"
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get "/sites/$id/themes" "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(_mainwp_extract_sites "$response")"
	if printf '%s' "$arr" | jq -e 'type == "object"' >/dev/null 2>&1; then
		printf '%s' "$arr" | mainwp_render_object
	else
		_mainwp_render_list "$arr" "Slug,Name,Status" \
			'.slug // empty' '.name // .Name // empty' '.status // .Status // empty'
	fi
}

# ---- write ---------------------------------------------------------

cmd_sites_add() {
	local url="" name="" admin="" groupids="" client_id=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--url)
			url="$2"
			shift 2
			;;
		--name)
			name="$2"
			shift 2
			;;
		--admin)
			admin="$2"
			shift 2
			;;
		--groupids)
			groupids="$2"
			shift 2
			;;
		--client-id)
			client_id="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done

	if [[ $MAINWP_INTERACTIVE -eq 1 && -z "$url" ]]; then
		url="$(mainwp_ui_input "Site URL" "")"
	fi
	[[ -n "$url" ]] || mainwp_die "Site URL is required (--url)."

	if [[ $MAINWP_INTERACTIVE -eq 1 && -z "$name" ]]; then
		name="$(mainwp_ui_input "Site name" "")"
	fi
	[[ -n "$name" ]] || mainwp_die "Site name is required (--name)."

	if [[ $MAINWP_INTERACTIVE -eq 1 && -z "$admin" ]]; then
		admin="$(mainwp_ui_input "Admin username" "admin")"
	fi
	[[ -n "$admin" ]] || admin="admin"

	local body
	body="$(jq -n --arg url "$url" --arg name "$name" --arg admin "$admin" \
		--arg groupids "$groupids" --arg client_id "$client_id" \
		'{url:$url,name:$name,admin:$admin}
     + (if $groupids != "" then {groupids:$groupids} else {} end)
     + (if $client_id != "" then {client_id:$client_id} else {} end)')"

	local response
	response="$(mainwp_spinner "Adding site $name" mainwp_api_post /sites/add "$body")"
	mainwp_success "Site added."
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_edit() {
	local id="${1:?Usage: mainwp sites edit ID_OR_DOMAIN}"
	shift
	local name="" groupids="" client_id=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			name="$2"
			shift 2
			;;
		--groupids)
			groupids="$2"
			shift 2
			;;
		--client-id)
			client_id="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	local body
	body="$(jq -n --arg name "$name" --arg groupids "$groupids" --arg client_id "$client_id" \
		'{} + (if $name != "" then {name:$name} else {} end)
        + (if $groupids != "" then {groupids:$groupids} else {} end)
        + (if $client_id != "" then {client_id:$client_id} else {} end)')"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."

	local response
	response="$(mainwp_api_post "/sites/$id/edit" "$body")"
	mainwp_success "Site updated."
	printf '%s' "$response" | mainwp_render_object
}

# Bulk or per-site operations that accept optional ID and use POST.
cmd_sites_sync() { _mainwp_sites_bulk_action sync "$@"; }
cmd_sites_reconnect() { _mainwp_sites_bulk_action reconnect "$@"; }
cmd_sites_disconnect() { _mainwp_sites_bulk_action disconnect "$@"; }
cmd_sites_check() { _mainwp_sites_bulk_action check "$@"; }

_mainwp_sites_bulk_action() {
	local action="$1"
	shift
	local id="${1:-}"
	[[ -n "$id" ]] && shift
	eval "$(_mainwp_collect_kv_flags)"
	local path="/sites"
	[[ -n "$id" ]] && path="/sites/$id"
	path+="/$action"
	local response
	response="$(mainwp_spinner "Running $action..." mainwp_api_post "$path" "" "${MAINWP_KV_FLAGS[@]:-}")"
	mainwp_success "Action '$action' dispatched."
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_site_toggle() {
	local action="$1"
	shift
	local id="${1:?Usage: mainwp sites $action ID}"
	local response
	response="$(mainwp_api_post "/sites/$id/$action")"
	mainwp_success "Site $action."
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_remove() {
	local id="${1:?Usage: mainwp sites remove ID}"
	mainwp_confirm "Remove site #$id from the Dashboard? This cannot be undone." || return 0
	local response
	response="$(mainwp_api_delete "/sites/$id/remove")"
	mainwp_success "Site removed."
	printf '%s' "$response" | mainwp_render_object
}

# ---- plugin / theme sub-actions -----------------------------------

cmd_sites_plugin() {
	local action="${1:?Usage: mainwp sites plugin <activate|deactivate|delete> ID SLUG}"
	shift
	local id="${1:?missing ID}"
	shift
	local slug="${1:?missing SLUG}"
	shift
	local endpoint="/sites/$id/plugins/$action"
	local response
	case "$action" in
	activate | deactivate) response="$(mainwp_api_post "$endpoint" "$(jq -n --arg s "$slug" '{slug:$s}')")" ;;
	delete) response="$(mainwp_api_delete "$endpoint" "" "slug=$slug")" ;;
	*) mainwp_die "Unknown plugin action: $action" ;;
	esac
	mainwp_success "Plugin $action dispatched."
	printf '%s' "$response" | mainwp_render_object
}

cmd_sites_theme() {
	local action="${1:?Usage: mainwp sites theme <activate|delete> ID SLUG}"
	shift
	local id="${1:?missing ID}"
	shift
	local slug="${1:?missing SLUG}"
	shift
	local endpoint="/sites/$id/themes/$action"
	local response
	case "$action" in
	activate) response="$(mainwp_api_post "$endpoint" "$(jq -n --arg s "$slug" '{slug:$s}')")" ;;
	delete) response="$(mainwp_api_delete "$endpoint" "" "slug=$slug")" ;;
	*) mainwp_die "Unknown theme action: $action" ;;
	esac
	mainwp_success "Theme $action dispatched."
	printf '%s' "$response" | mainwp_render_object
}
