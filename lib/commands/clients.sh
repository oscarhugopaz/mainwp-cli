# shellcheck shell=bash
# clients.sh - Client records and client fields management.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_clients_help() {
	cat <<EOF
clients - Manage clients and client fields

Usage:
  mainwp clients SUBCOMMAND [OPTIONS] [ARGS...]

Records:
  list                   List clients
  count                  Count clients
  get ID_OR_EMAIL        Get one client
  add                    Add a client (interactive or flags)
  edit ID_OR_EMAIL       Edit a client
  remove ID_OR_EMAIL     Delete a client
  suspend ID_OR_EMAIL    Suspend a client
  unsuspend ID_OR_EMAIL  Unsuspend a client
  sites ID_OR_EMAIL      List sites for a client
  sites-count ID         Count sites for a client
  costs ID_OR_EMAIL      List costs for a client

Client fields (custom metadata):
  fields list            List all client fields
  fields add             Add a field
  fields edit ID_NAME    Edit a field
  fields delete ID_NAME  Delete a field
EOF
}

cmd_clients() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_clients_list "$@" ;;
	count) cmd_clients_count "$@" ;;
	get) cmd_clients_get "$@" ;;
	add) cmd_clients_add "$@" ;;
	edit) cmd_clients_edit "$@" ;;
	remove) cmd_clients_remove "$@" ;;
	suspend) cmd_clients_toggle suspend "$@" ;;
	unsuspend) cmd_clients_toggle unsuspend "$@" ;;
	sites) cmd_clients_relationship sites "$@" ;;
	sites-count) cmd_clients_relationship sites/count "$@" ;;
	costs) cmd_clients_relationship costs "$@" ;;
	fields) cmd_clients_fields "$@" ;;
	-h | --help | help) cmd_clients_help ;;
	*) mainwp_die "Unknown clients subcommand: '$sub'" ;;
	esac
}

cmd_clients_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /clients "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(printf '%s' "$response" | jq -c '.data // .clients // []')"
	_mainwp_render_list "$arr" "ID,Name,Email,Status" \
		'.id // empty' '.name // empty' '.client_email // .email // empty' '.status // empty'
}

cmd_clients_count() {
	local response total
	response="$(mainwp_api_get /clients/count)"
	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		printf '%s\n' "$response"
	else
		total="$(printf '%s' "$response" | jq -r '.total // .data.total // 0')"
		mainwp_info "Clients: $total"
	fi
}

cmd_clients_get() {
	local id="${1:?Usage: mainwp clients get ID_OR_EMAIL}"
	local response
	response="$(mainwp_api_get "/clients/$id")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_add() {
	local name="" email="" phone="" address=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			name="$2"
			shift 2
			;;
		--email)
			email="$2"
			shift 2
			;;
		--phone)
			phone="$2"
			shift 2
			;;
		--address)
			address="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$name" ]] && name="$(mainwp_ui_input "Client name")"
		[[ -z "$email" ]] && email="$(mainwp_ui_input "Client email")"
		[[ -z "$phone" ]] && phone="$(mainwp_ui_input "Client phone" "")"
	fi
	[[ -n "$name" ]] || mainwp_die "Client name is required."
	[[ -n "$email" ]] || mainwp_die "Client email is required."

	local body
	body="$(jq -n --arg n "$name" --arg e "$email" --arg p "$phone" --arg a "$address" \
		'{name:$n,client_email:$e}
     + (if $p != "" then {client_phone:$p} else {} end)
     + (if $a != "" then {client_address:$a} else {} end)')"

	local response
	response="$(mainwp_api_post /clients/add "$body")"
	mainwp_success "Client added."
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_edit() {
	local id="${1:?Usage: mainwp clients edit ID_OR_EMAIL}"
	shift
	local name="" email="" phone="" address="" status=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			name="$2"
			shift 2
			;;
		--email)
			email="$2"
			shift 2
			;;
		--phone)
			phone="$2"
			shift 2
			;;
		--address)
			address="$2"
			shift 2
			;;
		--status)
			status="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	local body
	body="$(jq -n --arg n "$name" --arg e "$email" --arg p "$phone" --arg a "$address" --arg s "$status" \
		'{} + (if $n != "" then {name:$n} else {} end)
        + (if $e != "" then {client_email:$e} else {} end)
        + (if $p != "" then {client_phone:$p} else {} end)
        + (if $a != "" then {client_address:$a} else {} end)
        + (if $s != "" then {status:$s} else {} end)')"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."

	local response
	response="$(mainwp_api_post "/clients/$id/edit" "$body")"
	mainwp_success "Client updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_remove() {
	local id="${1:?Usage: mainwp clients remove ID_OR_EMAIL}"
	mainwp_confirm "Delete client '$id'? This cannot be undone." || return 0
	local response
	response="$(mainwp_api_delete "/clients/$id/remove")"
	mainwp_success "Client removed."
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_toggle() {
	local action="$1" id="${2:?missing ID}"
	local response
	response="$(mainwp_api_post "/clients/$id/$action")"
	mainwp_success "Client $action."
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_relationship() {
	local rel="$1" id="${2:?missing ID}"
	local response
	response="$(mainwp_api_get "/clients/$id/$rel")"
	printf '%s' "$response" | mainwp_render_object
}

# ---- fields -------------------------------------------------------

cmd_clients_fields() {
	local action="${1:-list}"
	shift || true
	case "$action" in
	list) cmd_clients_fields_list "$@" ;;
	add) cmd_clients_fields_add "$@" ;;
	edit) cmd_clients_fields_edit "$@" ;;
	delete) cmd_clients_fields_delete "$@" ;;
	*) mainwp_die "Unknown fields action: '$action'" ;;
	esac
}

cmd_clients_fields_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /clients/fields "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(printf '%s' "$response" | jq -c '.data // .fields // []')"
	_mainwp_render_list "$arr" "ID,Name,Description" \
		'.field_id // .id // empty' '.name // empty' '.description // empty'
}

cmd_clients_fields_add() {
	local name="" description=""
	while [[ $# -gt 0 ]]; do
		case "$1" in --name)
			name="$2"
			shift 2
			;;
		--description)
			description="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;; esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$name" ]] && name="$(mainwp_ui_input "Field name")"
		[[ -z "$description" ]] && description="$(mainwp_ui_input "Field description" "")"
	fi
	[[ -n "$name" ]] || mainwp_die "Field name is required."
	local body
	body="$(jq -n --arg n "$name" --arg d "$description" \
		'{name:$n} + (if $d != "" then {description:$d} else {} end)')"
	local response
	response="$(mainwp_api_post /clients/fields/add "$body")"
	mainwp_success "Field created."
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_fields_edit() {
	local id="${1:?missing field ID or name}"
	shift
	local name="" description=""
	while [[ $# -gt 0 ]]; do
		case "$1" in --name)
			name="$2"
			shift 2
			;;
		--description)
			description="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;; esac
	done
	local body
	body="$(jq -n --arg n "$name" --arg d "$description" \
		'{} + (if $n != "" then {name:$n} else {} end)
        + (if $d != "" then {description:$d} else {} end)')"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/clients/fields/$id/edit" "$body")"
	mainwp_success "Field updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_clients_fields_delete() {
	local id="${1:?missing field ID or name}"
	mainwp_confirm "Delete client field '$id'?" || return 0
	local response
	response="$(mainwp_api_delete "/clients/fields/$id/delete")"
	mainwp_success "Field deleted."
	printf '%s' "$response" | mainwp_render_object
}
