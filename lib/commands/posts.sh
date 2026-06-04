# shellcheck shell=bash
# posts.sh - Cross-site post management.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_posts_help() {
	cat <<EOF
posts - Manage posts across child sites

Usage:
  mainwp posts SUBCOMMAND [OPTIONS] [ARGS...]

  list                                  List posts across selected sites
  get SITE_ID POST_ID                   Get a post
  create SITE_ID                        Create a post (interactive or flags)
  edit SITE_ID POST_ID                  Edit a post
  update-status SITE_ID POST_ID STATUS  Update only the post status
  delete SITE_ID POST_ID                Delete a post

Common list filters:
  --search TEXT   --status STATUS   --websites IDS   --groups NAMES
  --clients IDS   --post-type TYPE  --maximum N

Create / edit body flags:
  --title TEXT  --content HTML  --status STATUS  --name SLUG
  --extra JSON  (raw JSON merged into the body)
EOF
}

cmd_posts() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_posts_list "$@" ;;
	get) cmd_posts_get "$@" ;;
	create) cmd_posts_create "$@" ;;
	edit) cmd_posts_edit "$@" ;;
	update-status) cmd_posts_update_status "$@" ;;
	delete) cmd_posts_delete "$@" ;;
	-h | --help) cmd_posts_help ;;
	*) mainwp_die "Unknown posts subcommand: '$sub'" ;;
	esac
}

cmd_posts_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response
	response="$(mainwp_api_get /posts "${MAINWP_KV_FLAGS[@]:-}")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_posts_get() {
	local site_id="${1:?Usage: mainwp posts get SITE_ID POST_ID}"
	shift
	local post_id="${1:?missing POST_ID}"
	local response
	response="$(mainwp_api_get "/posts/$site_id/$post_id")"
	printf '%s' "$response" | mainwp_render_object
}

_mainwp_post_body() {
	local title="$1" content="$2" status="$3" name="$4" extra="$5"
	jq -n --arg t "$title" --arg c "$content" --arg s "$status" --arg n "$name" --argjson e "$extra" \
		'{} + (if $t != "" then {post_title:$t}   else {} end)
        + (if $c != "" then {post_content:$c} else {} end)
        + (if $s != "" then {post_status:$s}  else {} end)
        + (if $n != "" then {post_name:$n}    else {} end)
        + $e'
}

cmd_posts_create() {
	local site_id="${1:?Usage: mainwp posts create SITE_ID}"
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
		[[ -z "$title" ]] && title="$(mainwp_ui_input "Post title" "")"
		[[ -z "$content" ]] && content="$(mainwp_ui_input "Post content (HTML)" "")"
		[[ -z "$status" ]] && status="draft"
	fi
	[[ -n "$title" ]] || mainwp_die "Title is required."

	local body
	body="$(_mainwp_post_body "$title" "$content" "$status" "$name" "$extra")"
	local response
	response="$(mainwp_api_post "/posts/$site_id/create" "$body")"
	mainwp_success "Post created."
	printf '%s' "$response" | mainwp_render_object
}

cmd_posts_edit() {
	local site_id="${1:?Usage: mainwp posts edit SITE_ID POST_ID}"
	shift
	local post_id="${1:?missing POST_ID}"
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
	body="$(_mainwp_post_body "$title" "$content" "$status" "$name" "$extra")"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/posts/$site_id/$post_id/edit" "$body")"
	mainwp_success "Post updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_posts_update_status() {
	local site_id="${1:?Usage: mainwp posts update-status SITE_ID POST_ID STATUS}"
	shift
	local post_id="${1:?missing POST_ID}"
	shift
	local status="${1:?missing STATUS}"
	local body
	body="$(jq -n --arg s "$status" '{status:$s}')"
	local response
	response="$(mainwp_api_post "/posts/$site_id/$post_id/update-status" "$body")"
	mainwp_success "Post status updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_posts_delete() {
	local site_id="${1:?Usage: mainwp posts delete SITE_ID POST_ID}"
	shift
	local post_id="${1:?missing POST_ID}"
	mainwp_confirm "Delete post #$post_id from site #$site_id?" || return 0
	local response
	response="$(mainwp_api_delete "/posts/$site_id/$post_id/delete")"
	mainwp_success "Post deleted."
	printf '%s' "$response" | mainwp_render_object
}
