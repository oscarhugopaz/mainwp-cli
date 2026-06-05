# shellcheck shell=bash
# pages.sh - Cross-site page management.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_pages_help() {
	cat <<EOF
pages - Manage pages across child sites

Usage:
  mainwp pages SUBCOMMAND [OPTIONS] [ARGS...]

  list                                  List pages
  get SITE_ID PAGE_ID                   Get a page
  create SITE_ID                        Create a page
  edit SITE_ID PAGE_ID                  Edit a page
  update-status SITE_ID PAGE_ID STATUS  Update page status
  delete SITE_ID PAGE_ID                Delete a page
EOF
}

cmd_pages() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_pages_list "$@" ;;
	get) cmd_pages_get "$@" ;;
	create) cmd_pages_create "$@" ;;
	edit) cmd_pages_edit "$@" ;;
	update-status) cmd_pages_update_status "$@" ;;
	delete) cmd_pages_delete "$@" ;;
	-h | --help | help) cmd_pages_help ;;
	*) mainwp_die "Unknown pages subcommand: '$sub'" ;;
	esac
}

cmd_pages_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get /pages "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_pages_get() {
	local site_id="${1:?Usage: mainwp pages get SITE_ID PAGE_ID}"
	shift
	local page_id="${1:?missing PAGE_ID}"
	local response
	response="$(mainwp_api_get "/pages/$site_id/$page_id")"
	printf '%s' "$response" | mainwp_render_object
}

_mainwp_page_body() {
	local title="$1" content="$2" status="$3" name="$4" extra="$5"
	jq -n --arg t "$title" --arg c "$content" --arg s "$status" --arg n "$name" --argjson e "$extra" \
		'{} + (if $t != "" then {post_title:$t}   else {} end)
        + (if $c != "" then {post_content:$c} else {} end)
        + (if $s != "" then {post_status:$s}  else {} end)
        + (if $n != "" then {post_name:$n}    else {} end)
        + $e'
}

cmd_pages_create() {
	local site_id="${1:?Usage: mainwp pages create SITE_ID}"
	shift
	local title="" content="" status="draft" name="" extra='{}'
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--title)
			title="$2"
			shift 2
			;;
		--content)
			content="$2"
			shift 2
			;;
		--status)
			status="$2"
			shift 2
			;;
		--name)
			name="$2"
			shift 2
			;;
		--extra)
			extra="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$title" ]] && title="$(mainwp_ui_input "Page title" "")"
		[[ -z "$content" ]] && content="$(mainwp_ui_input "Page content (HTML)" "")"
	fi
	[[ -n "$title" ]] || mainwp_die "Title is required."
	local body
	body="$(_mainwp_page_body "$title" "$content" "$status" "$name" "$extra")"
	local response
	response="$(mainwp_api_post "/pages/$site_id/create" "$body")"
	mainwp_success "Page created."
	printf '%s' "$response" | mainwp_render_object
}

cmd_pages_edit() {
	local site_id="${1:?Usage: mainwp pages edit SITE_ID PAGE_ID}"
	shift
	local page_id="${1:?missing PAGE_ID}"
	shift
	local title="" content="" status="" name="" extra='{}'
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--title)
			title="$2"
			shift 2
			;;
		--content)
			content="$2"
			shift 2
			;;
		--status)
			status="$2"
			shift 2
			;;
		--name)
			name="$2"
			shift 2
			;;
		--extra)
			extra="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	local body
	body="$(_mainwp_page_body "$title" "$content" "$status" "$name" "$extra")"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/pages/$site_id/$page_id/edit" "$body")"
	mainwp_success "Page updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_pages_update_status() {
	local site_id="${1:?Usage: mainwp pages update-status SITE_ID PAGE_ID STATUS}"
	shift
	local page_id="${1:?missing PAGE_ID}"
	shift
	local status="${1:?missing STATUS}"
	local body
	body="$(jq -n --arg s "$status" '{status:$s}')"
	local response
	response="$(mainwp_api_post "/pages/$site_id/$page_id/update-status" "$body")"
	mainwp_success "Page status updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_pages_delete() {
	local site_id="${1:?Usage: mainwp pages delete SITE_ID PAGE_ID}"
	shift
	local page_id="${1:?missing PAGE_ID}"
	mainwp_confirm "Delete page #$page_id from site #$site_id?" || return 0
	local response
	response="$(mainwp_api_delete "/pages/$site_id/$page_id/delete")"
	mainwp_success "Page deleted."
	printf '%s' "$response" | mainwp_render_object
}
