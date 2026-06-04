# shellcheck shell=bash
# settings.sh - Dashboard settings (general, advanced, monitoring, email, cost-tracker, ...).
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_settings_help() {
	cat <<EOF
settings - Manage MainWP Dashboard settings

Usage:
  mainwp settings SUBCOMMAND [OPTIONS] [ARGS...]

  general get                 Show general settings
  general set [--key=VAL...]  Update general settings (repeatable)
  advanced get                Show advanced settings
  advanced set [--key=VAL...] Update advanced settings
  monitoring get              Show monitoring settings
  monitoring set [--key=VAL...]
  emails get                  Show email settings
  emails set TYPE [--key=VAL...]
  cost-tracker get            Show cost tracker settings
  cost-tracker set [--key=VAL...]
  cost-tracker product-types add    --title T [--color C] [--icon I]
  cost-tracker product-types edit   SLUG --title T
  cost-tracker product-types delete SLUG
  cost-tracker payment-methods add    --title T
  cost-tracker payment-methods edit   SLUG --title T
  cost-tracker payment-methods delete SLUG
  insights get / set
  api-backups get
  api-backups set SLUG [--key=VAL...]
  tools get
  tools set [--key=VAL...]
  tools destroy-sessions [--status ID]
  tools renew-connections [--status ID]
  tools disconnect-all-sites [--status ID]
  tools clear-activation-data
  tools restore-info-messages
EOF
}

cmd_settings() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-general}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	general) cmd_settings_section settings/general "$@" ;;
	advanced) cmd_settings_section settings/advanced "$@" ;;
	monitoring) cmd_settings_section settings/monitoring "$@" ;;
	emails) cmd_settings_emails "$@" ;;
	cost-tracker) cmd_settings_cost_tracker "$@" ;;
	insights) cmd_settings_section settings/dashboard-insights "$@" ;;
	api-backups) cmd_settings_api_backups "$@" ;;
	tools) cmd_settings_tools "$@" ;;
	-h | --help) cmd_settings_help ;;
	*) mainwp_die "Unknown settings subcommand: '$sub'" ;;
	esac
}

# Generic get/set handler for sections that are simple JSON blobs.
cmd_settings_section() {
	local section="$1"
	shift
	local action="${1:-get}"
	shift || true
	case "$action" in
	get)
		local response
		response="$(mainwp_api_get "/$section")"
		printf '%s' "$response" | mainwp_render_object
		;;
	set)
		eval "$(_mainwp_collect_kv_flags)"
		[[ ${#MAINWP_KV_FLAGS[@]} -gt 0 ]] || mainwp_die "Provide at least one --key=value flag."
		local body
		body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
		local response
		response="$(mainwp_api_post "/$section/edit" "$body")"
		mainwp_success "$section updated."
		printf '%s' "$response" | mainwp_render_object
		;;
	*) mainwp_die "Unknown action: '$action' (use get|set)" ;;
	esac
}

cmd_settings_emails() {
	local action="${1:-get}"
	shift || true
	case "$action" in
	get)
		local response
		response="$(mainwp_api_get /settings/emails)"
		printf '%s' "$response" | mainwp_render_object
		;;
	set)
		local mail_type="${1:?Usage: mainwp settings emails set TYPE [--key=value ...]}"
		shift
		eval "$(_mainwp_collect_kv_flags)"
		local body
		if [[ ${#MAINWP_KV_FLAGS[@]} -gt 0 ]]; then
			body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
		else
			body="{}"
		fi
		local response
		response="$(mainwp_api_post "/settings/emails/$mail_type/edit" "$body")"
		mainwp_success "Email settings updated for $mail_type."
		printf '%s' "$response" | mainwp_render_object
		;;
	*) mainwp_die "Unknown action: '$action' (use get|set)" ;;
	esac
}

cmd_settings_cost_tracker() {
	local action="${1:-get}"
	shift || true
	case "$action" in
	get)
		local response
		response="$(mainwp_api_get /settings/cost-tracker)"
		printf '%s' "$response" | mainwp_render_object
		;;
	set)
		eval "$(_mainwp_collect_kv_flags)"
		local body
		body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
		local response
		response="$(mainwp_api_post /settings/cost-tracker/edit "$body")"
		mainwp_success "Cost tracker settings updated."
		printf '%s' "$response" | mainwp_render_object
		;;
	product-types | payment-methods)
		cmd_settings_cost_tracker_named "$action" "$@"
		;;
	*) mainwp_die "Unknown action: '$action'" ;;
	esac
}

cmd_settings_cost_tracker_named() {
	local kind="$1" action="${2:-list}"
	shift 2
	case "$action" in
	add)
		local title="" color="" icon=""
		while [[ $# -gt 0 ]]; do
			case "$1" in --title)
				title="$2"
				shift 2
				;;
			--color)
				color="$2"
				shift 2
				;;
			--icon)
				icon="$2"
				shift 2
				;;
			*) mainwp_die "Unknown option: $1" ;; esac
		done
		[[ -n "$title" ]] || mainwp_die "--title is required."
		local body
		body="$(jq -n --arg t "$title" --arg c "$color" --arg i "$icon" \
			'{title:$t} + (if $c != "" then {color:$c} else {} end) + (if $i != "" then {icon:$i} else {} end)')"
		local response
		response="$(mainwp_api_post "/settings/cost-tracker/$kind/add" "$body")"
		mainwp_success "$kind entry created."
		printf '%s' "$response" | mainwp_render_object
		;;
	edit)
		local slug="${1:?missing slug}"
		shift
		local title="" color="" icon=""
		while [[ $# -gt 0 ]]; do
			case "$1" in --title)
				title="$2"
				shift 2
				;;
			--color)
				color="$2"
				shift 2
				;;
			--icon)
				icon="$2"
				shift 2
				;;
			*) mainwp_die "Unknown option: $1" ;; esac
		done
		local body
		body="$(jq -n --arg t "$title" --arg c "$color" --arg i "$icon" \
			'{} + (if $t != "" then {title:$t} else {} end) + (if $c != "" then {color:$c} else {} end) + (if $i != "" then {icon:$i} else {} end)')"
		local response
		response="$(mainwp_api_post "/settings/cost-tracker/$kind/$slug/edit" "$body")"
		mainwp_success "$kind entry updated."
		printf '%s' "$response" | mainwp_render_object
		;;
	delete)
		local slug="${1:?missing slug}"
		mainwp_confirm "Delete $kind entry '$slug'?" || return 0
		local response
		response="$(mainwp_api_delete "/settings/cost-tracker/$kind/$slug/delete")"
		mainwp_success "$kind entry deleted."
		printf '%s' "$response" | mainwp_render_object
		;;
	*) mainwp_die "Unknown action: '$action' (use add|edit|delete)" ;;
	esac
}

cmd_settings_api_backups() {
	local action="${1:-get}"
	shift || true
	case "$action" in
	get)
		local response
		response="$(mainwp_api_get /settings/api-backups)"
		printf '%s' "$response" | mainwp_render_object
		;;
	set)
		local slug="${1:?missing provider slug}"
		shift
		eval "$(_mainwp_collect_kv_flags)"
		local body
		body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
		local response
		response="$(mainwp_api_post "/settings/api-backups/$slug/edit" "$body")"
		mainwp_success "API backups updated for $slug."
		printf '%s' "$response" | mainwp_render_object
		;;
	*) mainwp_die "Unknown action: '$action' (use get|set)" ;;
	esac
}

cmd_settings_tools() {
	local action="${1:-get}"
	shift || true
	case "$action" in
	get)
		local response
		response="$(mainwp_api_get /settings/tools)"
		printf '%s' "$response" | mainwp_render_object
		;;
	set)
		eval "$(_mainwp_collect_kv_flags)"
		local body
		body="$(printf '%s\n' "${MAINWP_KV_FLAGS[@]:-}" | jq -R -s 'split("\n") | map(select(length>0)) | map(split("=") | {(.[0]): .[1]}) | add')"
		local response
		response="$(mainwp_api_post /settings/tools/edit "$body")"
		mainwp_success "Tools settings updated."
		printf '%s' "$response" | mainwp_render_object
		;;
	destroy-sessions | renew-connections | disconnect-all-sites | clear-activation-data | restore-info-messages)
		cmd_settings_tools_action "$action" "$@"
		;;
	*) mainwp_die "Unknown tools action: '$action'" ;;
	esac
}

cmd_settings_tools_action() {
	local action="$1"
	shift
	case "$action" in
	destroy-sessions | renew-connections | disconnect-all-sites)
		local status_endpoint_id=""
		# accept --status ID as well
		if [[ ${1:-} == "--status" ]]; then
			status_endpoint_id="${2:-}"
			shift 2
		fi
		if [[ -n "$status_endpoint_id" ]]; then
			local response
			response="$(mainwp_api_get "/settings/tools/${action}-status/$status_endpoint_id")"
			printf '%s' "$response" | mainwp_render_object
		else
			local response
			response="$(mainwp_api_post "/settings/tools/$action")"
			mainwp_success "$action dispatched."
			printf '%s' "$response" | mainwp_render_object
		fi
		;;
	clear-activation-data | restore-info-messages)
		local response
		response="$(mainwp_api_post "/settings/tools/$action")"
		mainwp_success "$action dispatched."
		printf '%s' "$response" | mainwp_render_object
		;;
	*) mainwp_die "Unknown tools action: $action" ;;
	esac
}
