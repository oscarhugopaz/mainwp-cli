# shellcheck shell=bash
# users.sh - User management across child sites.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_users_help() {
	cat <<EOF
users - Manage users across child sites

Usage:
  mainwp users SUBCOMMAND [OPTIONS] [ARGS...]

  list                              List users
  create                            Create a user on selected sites
  edit SITE_ID USER_ID [--flags]    Edit a user on one site
  delete SITE_ID USER_ID            Delete a user on one site
  update-admin-password             Update admin password across selected sites
  import PATH.csv [--has-header]    Import users from a CSV file

Site selection flags for list/create/update-admin-password:
  --clients IDS   --groups NAMES   --websites IDS   --roles ROLES   --search TEXT
EOF
}

cmd_users() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_users_list "$@" ;;
	create) cmd_users_create "$@" ;;
	edit) cmd_users_edit "$@" ;;
	delete) cmd_users_delete "$@" ;;
	update-admin-password) cmd_users_update_admin_password "$@" ;;
	import) cmd_users_import "$@" ;;
	-h | --help | help) cmd_users_help ;;
	*) mainwp_die "Unknown users subcommand: '$sub'" ;;
	esac
}

cmd_users_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /users "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(_mainwp_extract_list "$response")"
	# The /users endpoint returns an object keyed by site URL, with the
	# site URL preserved on each record as the `site` field by the
	# extractor. Fall back to the key/value view if no array could be
	# materialized.
	if [[ "$(printf '%s' "$arr" | jq -r 'type' 2>/dev/null)" == "array" && $(printf '%s' "$arr" | jq 'length') -gt 0 ]]; then
		_mainwp_render_list "$arr" "ID,Username,Name,Email,Role,Site" \
			'.id // empty' '.username // empty' '.name // empty' '.email // empty' '.role // empty' '.site // empty'
	else
		printf '%s' "$response" | mainwp_render_object
	fi
}

cmd_users_create() {
	local username="" email="" password="" role=""
	local first_name="" last_name="" user_url="" send_password="false"
	local clients="" groups="" websites=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--username)
			username="$2"
			shift 2
			;;
		--email)
			email="$2"
			shift 2
			;;
		--password)
			password="$2"
			shift 2
			;;
		--role)
			role="$2"
			shift 2
			;;
		--first-name)
			first_name="$2"
			shift 2
			;;
		--last-name)
			last_name="$2"
			shift 2
			;;
		--user-url)
			user_url="$2"
			shift 2
			;;
		--send-password)
			send_password="$2"
			shift 2
			;;
		--clients)
			clients="$2"
			shift 2
			;;
		--groups)
			groups="$2"
			shift 2
			;;
		--websites)
			websites="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$username" ]] && username="$(mainwp_ui_input "Username")"
		[[ -z "$email" ]] && email="$(mainwp_ui_input "Email")"
		[[ -z "$role" ]] && role="$(mainwp_ui_input "Role" "subscriber")"
		[[ -z "$websites" && -z "$groups" && -z "$clients" ]] && websites="$(mainwp_ui_input "Website IDs (comma-separated)")"
	fi
	[[ -n "$username" && -n "$email" ]] || mainwp_die "username and email are required."

	local body
	body="$(jq -n \
		--arg u "$username" --arg e "$email" --arg p "$password" --arg r "$role" \
		--arg fn "$first_name" --arg ln "$last_name" --arg url "$user_url" \
		--argjson sp "$send_password" \
		--arg c "$clients" --arg g "$groups" --arg w "$websites" \
		'{username:$u,email:$e,role:$r,send_password:$sp}
     + (if $p  != "" then {password:$p}      else {} end)
     + (if $fn != "" then {first_name:$fn}   else {} end)
     + (if $ln != "" then {last_name:$ln}    else {} end)
     + (if $url!= "" then {user_url:$url}    else {} end)
     + (if $c  != "" then {clients:$c}       else {} end)
     + (if $g  != "" then {groups:$g}        else {} end)
     + (if $w  != "" then {websites:$w}      else {} end)')"

	local response
	response="$(mainwp_api_post /users/create "$body")"
	mainwp_success "User created."
	printf '%s' "$response" | mainwp_render_object
}

cmd_users_edit() {
	local site_id="${1:?Usage: mainwp users edit SITE_ID USER_ID}"
	shift
	local user_id="${1:?missing USER_ID}"
	shift
	local email="" role="" first_name="" last_name="" password=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--email)
			email="$2"
			shift 2
			;;
		--role)
			role="$2"
			shift 2
			;;
		--first-name)
			first_name="$2"
			shift 2
			;;
		--last-name)
			last_name="$2"
			shift 2
			;;
		--password)
			password="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	local body
	body="$(jq -n --arg e "$email" --arg r "$role" --arg fn "$first_name" --arg ln "$last_name" --arg p "$password" \
		'{} + (if $e  != "" then {email:$e}        else {} end)
        + (if $r  != "" then {role:$r}         else {} end)
        + (if $fn != "" then {first_name:$fn}  else {} end)
        + (if $ln != "" then {last_name:$ln}   else {} end)
        + (if $p  != "" then {password:$p}     else {} end)')"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/users/$site_id/$user_id/edit" "$body")"
	mainwp_success "User updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_users_delete() {
	local site_id="${1:?missing SITE_ID}"
	shift
	local user_id="${1:?missing USER_ID}"
	shift
	mainwp_confirm "Delete user #$user_id from site #$site_id?" || return 0
	local response
	response="$(mainwp_api_delete "/users/$site_id/$user_id/delete")"
	mainwp_success "User deleted."
	printf '%s' "$response" | mainwp_render_object
}

cmd_users_update_admin_password() {
	local password="" clients="" groups="" websites=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--password)
			password="$2"
			shift 2
			;;
		--clients)
			clients="$2"
			shift 2
			;;
		--groups)
			groups="$2"
			shift 2
			;;
		--websites)
			websites="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$password" ]] && password="$(mainwp_ui_password "New admin password")"
	fi
	[[ -n "$password" ]] || mainwp_die "password is required."
	mainwp_confirm "Rotate the administrator password across the selected sites?" || return 0

	local body
	body="$(jq -n --arg p "$password" --arg c "$clients" --arg g "$groups" --arg w "$websites" \
		'{password:$p}
     + (if $c != "" then {clients:$c}  else {} end)
     + (if $g != "" then {groups:$g}   else {} end)
     + (if $w != "" then {websites:$w} else {} end)')"
	local response
	response="$(mainwp_spinner "Rotating admin passwords..." mainwp_api_put /users/update-admin-password "$body")"
	mainwp_success "Admin passwords updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_users_import() {
	local file="${1:?Usage: mainwp users import PATH.csv [--has-header]}"
	local has_header="true"
	[[ "${2:-}" == "--has-header" || "${2:-}" == "--no-header" ]] && has_header="$2"
	[[ -f "$file" ]] || mainwp_die "File not found: $file"

	local response
	response="$(mainwp_spinner "Uploading $file..." \
		curl -sS --fail-with-body --connect-timeout 10 --max-time 600 \
		-H "Authorization: Bearer $(mainwp_config_key)" \
		-H "Accept: application/json" \
		-F "csv_file=@${file}" \
		-F "has_header=${has_header#--}" \
		"$(mainwp_config_url)/$(mainwp_config_api_path)/users/import")"
	mainwp_success "Import complete."
	printf '%s' "$response" | mainwp_render_object
}
