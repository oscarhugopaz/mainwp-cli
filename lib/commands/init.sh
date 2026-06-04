# shellcheck shell=bash
# init.sh - Interactive first-time setup for the mainwp CLI.
# Prompts the user for the MainWP Dashboard URL and an API key, then
# persists them under the current profile.

cmd_init_help() {
	cat <<EOF
init - Interactive setup for a MainWP Dashboard profile

Usage:
  mainwp init [OPTIONS]

Options:
  --url URL     Pre-fill the dashboard URL
  --key KEY     Pre-fill the API key (otherwise prompted securely)
  --profile N   Save the credentials under profile N (default: "default")

Guided walkthrough that asks for the dashboard URL and an API key,
stores them in your local config (~/.config/mainwp/config.json),
and runs a quick connectivity check against /sites/basic.
EOF
}

cmd_init() {
	local url="" key="" profile="default"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--url)
			url="$2"
			shift 2
			;;
		--key)
			key="$2"
			shift 2
			;;
		--profile)
			profile="$2"
			shift 2
			;;
		-h | --help)
			cmd_init_help
			return 0
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done

	MAINWP_PROFILE="$profile"
	export MAINWP_PROFILE

	mainwp_info "Setting up profile '$profile'."

	if [[ -z "$url" ]]; then
		url="$(mainwp_ui_input "Dashboard URL (e.g. https://dashboard.example.com)" "https://")"
	fi
	url="$(mainwp_config_validate_url "$url")"

	if [[ -z "$key" ]]; then
		key="$(mainwp_ui_password "API key (Bearer token)")"
		[[ -n "$key" ]] || mainwp_die "API key cannot be empty."
	fi

	mainwp_config_set_field '.url' "$url"
	mainwp_config_set_field '.api_key' "$key"
	mainwp_config_set_field '.api_path' "wp-json/mainwp/v2"
	mainwp_config_set_active

	mainwp_success "Profile '$profile' saved."

	mainwp_info "Running connectivity check..."
	if response="$(mainwp_api_get /sites/basic per_page=1 2>&1)"; then
		mainwp_success "Connected to $(mainwp_config_url)"
		if command -v jq >/dev/null 2>&1; then
			local count
			count="$(printf '%s' "$response" | jq -r '.data | if type=="array" then length else 0 end' 2>/dev/null || echo 0)"
			mainwp_info "Dashboard reports $count site(s) (showing first page only)."
		fi
	else
		mainwp_warn "Connectivity check failed. Double-check the URL and key, then retry."
	fi
}
