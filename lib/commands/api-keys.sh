# shellcheck shell=bash
# api-keys.sh - REST API key management.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_api_keys_help() {
	cat <<EOF
api-keys - Manage REST API keys

Usage:
  mainwp api-keys SUBCOMMAND [OPTIONS] [ARGS...]

  list                    List API keys
  add                     Create a new key (interactive or --active/--permissions/--description)
  edit KEY_ID             Edit a key
  delete KEY_ID           Delete a key

Note: Newly generated tokens are returned ONLY in the create response.
Store them safely.
EOF
}

cmd_api_keys() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_api_keys_list "$@" ;;
	add) cmd_api_keys_add "$@" ;;
	edit) cmd_api_keys_edit "$@" ;;
	delete) cmd_api_keys_delete "$@" ;;
	-h | --help) cmd_api_keys_help ;;
	*) mainwp_die "Unknown api-keys subcommand: '$sub'" ;;
	esac
}

cmd_api_keys_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /rest-api/keys "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(printf '%s' "$response" | jq -c '.data // .keys // []')"
	_mainwp_render_list "$arr" "ID,Description,Permissions,Active" \
		'.id // empty' '.description // empty' '.permissions // empty' '.active // empty'
}

cmd_api_keys_add() {
	local active="true" permissions="" description=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--active)
			active="$2"
			shift 2
			;;
		--permissions)
			permissions="$2"
			shift 2
			;;
		--description)
			description="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$permissions" ]] && permissions="$(mainwp_ui_input "Permissions (read|write|read,write)" "read,write")"
		[[ -z "$description" ]] && description="$(mainwp_ui_input "Description" "")"
	fi
	[[ -n "$permissions" ]] || mainwp_die "--permissions is required (read, write, or read,write)."

	local body
	body="$(jq -n --argjson a "$active" --arg p "$permissions" --arg d "$description" \
		'{active:$a,permissions:$p} + (if $d != "" then {description:$d} else {} end)')"
	local response
	response="$(mainwp_api_post /rest-api/add-key "$body")"
	mainwp_success "Key created. Save the token now - it won't be shown again."
	printf '%s' "$response" | mainwp_render_object
}

cmd_api_keys_edit() {
	local id="${1:?Usage: mainwp api-keys edit KEY_ID}"
	shift
	local active="" permissions="" description=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--active)
			active="$2"
			shift 2
			;;
		--permissions)
			permissions="$2"
			shift 2
			;;
		--description)
			description="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	local body
	body="$(jq -n --arg a "$active" --arg p "$permissions" --arg d "$description" \
		'{} + (if $a != "" then {active:($a|fromjson? // ($a == "true"))} else {} end)
        + (if $p != "" then {permissions:$p} else {} end)
        + (if $d != "" then {description:$d} else {} end)')"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/rest-api/edit-key/$id" "$body")"
	mainwp_success "Key updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_api_keys_delete() {
	local id="${1:?Usage: mainwp api-keys delete KEY_ID}"
	mainwp_confirm "Delete API key #$id? Any tooling using it will stop working." || return 0
	local response
	response="$(mainwp_api_delete "/rest-api/delete-key/$id")"
	mainwp_success "Key deleted."
	printf '%s' "$response" | mainwp_render_object
}
