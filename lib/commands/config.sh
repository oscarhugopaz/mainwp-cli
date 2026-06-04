# shellcheck shell=bash
# config.sh - Inspect and manage the on-disk configuration.

cmd_config_help() {
	cat <<EOF
config - Manage CLI configuration and profiles

Usage:
  mainwp config SUBCOMMAND [OPTIONS]

Subcommands:
  get                         Print the active profile as JSON
  set url URL                 Set the dashboard URL
  set key KEY                 Set the API key
  set api-path PATH           Set the API base path (default: wp-json/mainwp/v2)
  profile list                List all configured profiles
  profile use NAME            Switch the active profile
  profile create NAME         Create an empty profile
  profile delete NAME         Remove a profile and its credentials
  path                        Print the path to the config file
EOF
}

cmd_config() {
	local sub="${1:-}"
	if [[ -z "$sub" || "$sub" == "-h" || "$sub" == "--help" ]]; then
		cmd_config_help
		return 0
	fi
	shift

	case "$sub" in
	get) cmd_config_get "$@" ;;
	set) cmd_config_set "$@" ;;
	profile) cmd_config_profile "$@" ;;
	path) mainwp_config_path ;;
	*) mainwp_die "Unknown config subcommand: '$sub'" ;;
	esac
}

cmd_config_get() {
	mainwp_config_load | jq --arg p "$MAINWP_PROFILE" '.profiles[$p] // {}'
}

cmd_config_set() {
	local field="${1:-}" value="${2:-}"
	[[ -n "$field" && -n "$value" ]] || mainwp_die "Usage: mainwp config set <url|key|api-path> VALUE"
	case "$field" in
	url)
		value="$(mainwp_config_validate_url "$value")"
		mainwp_config_set_field '.url' "$value"
		mainwp_success "URL updated for profile '$MAINWP_PROFILE'."
		;;
	key | api-key | api_key)
		mainwp_config_set_field '.api_key' "$value"
		mainwp_success "API key updated for profile '$MAINWP_PROFILE'."
		;;
	api-path | api_path)
		mainwp_config_set_field '.api_path' "$value"
		mainwp_success "API base path updated to '$value'."
		;;
	*)
		mainwp_die "Unknown field: '$field'. Use: url, key, api-path."
		;;
	esac
}

cmd_config_profile() {
	local action="${1:-}"
	shift || true
	case "$action" in
	list)
		local active
		active="$(mainwp_config_load | jq -r '.active // "default"')"
		if profile="$(mainwp_config_list_profiles)"; then
			if [[ -z "$profile" ]]; then
				mainwp_info "No profiles configured yet. Run: mainwp init"
			else
				while IFS= read -r name; do
					if [[ "$name" == "$active" ]]; then
						printf '* %s (active)\n' "$name"
					else
						printf '  %s\n' "$name"
					fi
				done <<<"$profile"
			fi
		fi
		;;
	use)
		local name="${1:-}"
		[[ -n "$name" ]] || mainwp_die "Usage: mainwp config profile use NAME"
		if ! mainwp_config_load | jq -e --arg p "$name" '.profiles[$p]' >/dev/null; then
			mainwp_die "Profile '$name' does not exist. Run: mainwp config profile create $name"
		fi
		MAINWP_PROFILE="$name"
		mainwp_config_set_active "$(mainwp_config_load)"
		mainwp_success "Active profile: $name"
		;;
	create)
		local name="${1:-}"
		[[ -n "$name" ]] || mainwp_die "Usage: mainwp config profile create NAME"
		mainwp_config_set_field '.placeholder = true' "true"
		mainwp_config_set_field 'del(.placeholder)' "ignored" 2>/dev/null || true
		# Initialize empty fields without overwriting existing values.
		local cfg
		cfg="$(mainwp_config_load)"
		cfg="$(printf '%s' "$cfg" | jq --arg p "$name" '.profiles[$p] //= {url:"",api_key:""}')"
		mainwp_config_save "$cfg"
		mainwp_success "Profile '$name' created. Fill in URL and key with: mainwp config set url KEY --profile $name"
		;;
	delete | rm)
		local name="${1:-}"
		[[ -n "$name" ]] || mainwp_die "Usage: mainwp config profile delete NAME"
		if [[ "$name" == "$MAINWP_PROFILE" ]]; then
			mainwp_die "Refusing to delete the active profile. Switch first with: mainwp config profile use OTHER"
		fi
		mainwp_confirm "Delete profile '$name' and all its credentials?" || return 0
		mainwp_config_delete_profile "$name"
		mainwp_success "Profile '$name' deleted."
		;;
	*)
		mainwp_die "Unknown profile action: '$action'. Use: list, use, create, delete."
		;;
	esac
}
