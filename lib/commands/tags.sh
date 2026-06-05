# shellcheck shell=bash
# tags.sh - Tag management (site groups).
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_tags_help() {
	cat <<EOF
tags - Manage MainWP tags (site groups)

Usage:
  mainwp tags SUBCOMMAND [OPTIONS] [ARGS...]

  list              List tags
  get ID            Get one tag
  add               Add a tag (interactive or --name/--color)
  edit ID           Edit a tag
  remove ID         Delete a tag
  sites ID          Show sites in a tag
  clients ID        Show clients linked through tagged sites
EOF
}

cmd_tags() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_tags_list "$@" ;;
	get) cmd_tags_get "$@" ;;
	add) cmd_tags_add "$@" ;;
	edit) cmd_tags_edit "$@" ;;
	remove) cmd_tags_remove "$@" ;;
	sites) cmd_tags_relationship sites "$@" ;;
	clients) cmd_tags_relationship clients "$@" ;;
	-h | --help | help) cmd_tags_help ;;
	*) mainwp_die "Unknown tags subcommand: '$sub'" ;;
	esac
}

cmd_tags_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /tags "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(_mainwp_extract_list "$response")"
	_mainwp_render_list "$arr" "ID,Name,Color" \
		'.id // empty' '.name // empty' '.color // empty'
}

cmd_tags_get() {
	local id="${1:?Usage: mainwp tags get ID}"
	local response
	response="$(mainwp_api_get "/tags/$id")"
	printf '%s' "$response" | mainwp_render_object
}

cmd_tags_add() {
	local name="" color=""
	while [[ $# -gt 0 ]]; do
		case "$1" in --name)
			name="$2"
			shift 2
			;;
		--color)
			color="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;; esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$name" ]] && name="$(mainwp_ui_input "Tag name" "")"
		[[ -z "$color" ]] && color="$(mainwp_ui_input "Color (e.g. #7fb100)" "")"
	fi
	[[ -n "$name" ]] || mainwp_die "Tag name is required."

	local body
	body="$(jq -n --arg n "$name" --arg c "$color" \
		'{name:$n} + (if $c != "" then {color:$c} else {} end)')"
	local response
	response="$(mainwp_api_post /tags/add "$body")"
	mainwp_success "Tag created."
	printf '%s' "$response" | mainwp_render_object
}

cmd_tags_edit() {
	local id="${1:?Usage: mainwp tags edit ID}"
	shift
	local name="" color=""
	while [[ $# -gt 0 ]]; do
		case "$1" in --name)
			name="$2"
			shift 2
			;;
		--color)
			color="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;; esac
	done
	local body
	body="$(jq -n --arg n "$name" --arg c "$color" \
		'{} + (if $n != "" then {name:$n} else {} end)
        + (if $c != "" then {color:$c} else {} end)')"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/tags/$id/edit" "$body")"
	mainwp_success "Tag updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_tags_remove() {
	local id="${1:?Usage: mainwp tags remove ID}"
	mainwp_confirm "Delete tag #$id?" || return 0
	local response
	response="$(mainwp_api_delete "/tags/$id/remove")"
	mainwp_success "Tag deleted."
	printf '%s' "$response" | mainwp_render_object
}

cmd_tags_relationship() {
	local rel="$1" id="${2:?missing ID}"
	local response
	response="$(mainwp_api_get "/tags/$id/$rel")"
	printf '%s' "$response" | mainwp_render_object
}
