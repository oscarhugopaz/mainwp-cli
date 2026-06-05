# shellcheck shell=bash
# config.sh - Configuration and profile management for the mainwp CLI
# Stores settings as JSON in $XDG_CONFIG_HOME/mainwp-cli/config.json
# (falling back to ~/.config/mainwp-cli/config.json). The file is
# chmod 600 because it contains API keys.
#
# The directory name matches the Homebrew formula name (mainwp-cli)
# so that the config lives next to the package that owns it.

# Locate the config file path, honouring XDG Base Directory.
mainwp_config_path() {
	local base="${XDG_CONFIG_HOME:-$HOME/.config}"
	printf '%s/mainwp-cli/config.json' "$base"
}

# Locate the config directory, creating it if missing.
mainwp_config_dir() {
	local dir
	dir="$(dirname "$(mainwp_config_path)")"
	[[ -d "$dir" ]] || mkdir -p "$dir" "$dir/profiles" 2>/dev/null || {
		mainwp_die "Could not create config directory: $dir"
	}
	printf '%s' "$dir"
}

# Read the current config as JSON, returning an empty object if absent.
mainwp_config_load() {
	local path
	path="$(mainwp_config_path)"
	if [[ -f "$path" ]]; then
		cat "$path"
	else
		printf '{"profiles":{}}'
	fi
}

# Persist the JSON config atomically with 0600 permissions.
mainwp_config_save() {
	local content="$1"
	local path
	path="$(mainwp_config_path)"
	local dir
	dir="$(mainwp_config_dir)"
	local tmp
	tmp="$(mktemp "${dir}/.config.XXXXXX")"
	printf '%s\n' "$content" >"$tmp"
	chmod 600 "$tmp"
	mv "$tmp" "$path"
}

# Return the name of the currently active profile.
mainwp_config_active_profile() {
	printf '%s' "$MAINWP_PROFILE"
}

# Resolve the current dashboard base URL (scheme + host + path prefix).
# Honours, in order: --url flag, MAINWP_URL env var, profile config.
mainwp_config_url() {
	if [[ -n "${MAINWP_URL:-}" ]]; then
		printf '%s' "$MAINWP_URL"
		return 0
	fi
	local cfg url
	cfg="$(mainwp_config_load)"
	url="$(printf '%s' "$cfg" | jq -r --arg p "$MAINWP_PROFILE" '.profiles[$p].url // empty')"
	if [[ -z "$url" ]]; then
		return 1
	fi
	printf '%s' "$url"
}

# Resolve the current API key. Honours, in order: --key flag,
# MAINWP_API_KEY env var, profile config.
mainwp_config_key() {
	if [[ -n "${MAINWP_API_KEY:-}" ]]; then
		printf '%s' "$MAINWP_API_KEY"
		return 0
	fi
	local cfg key
	cfg="$(mainwp_config_load)"
	key="$(printf '%s' "$cfg" | jq -r --arg p "$MAINWP_PROFILE" '.profiles[$p].api_key // empty')"
	if [[ -z "$key" ]]; then
		return 1
	fi
	printf '%s' "$key"
}

# Return the configured API base path (default: wp-json/mainwp/v2).
mainwp_config_api_path() {
	local cfg path
	cfg="$(mainwp_config_load)"
	path="$(printf '%s' "$cfg" | jq -r --arg p "$MAINWP_PROFILE" '.profiles[$p].api_path // empty')"
	if [[ -z "$path" ]]; then
		printf '%s' "$MAINWP_API_BASE_PATH"
	else
		printf '%s' "$path"
	fi
}

# Set a value in the active profile, creating the profile if needed.
# Usage: mainwp_config_set_field <field-path> <value>
#
# `field-path` is the path within the profile, e.g. `.url` or
# `.api_key`. The function prepends `.profiles[$p]` so the value
# always lands under the active profile, never at the document root.
mainwp_config_set_field() {
	local path="$1" value="$2"
	local cfg expr
	cfg="$(mainwp_config_load)"
	# `$p` and `$v` are jq variables bound via --arg below. The `\$p`
	# and `\$v` here are escaped so bash leaves them alone for jq.
	# `$path` IS bash-interpolated to e.g. `.url`.
	expr=".profiles[\$p] //= {} | .profiles[\$p]$path = \$v"
	cfg="$(printf '%s' "$cfg" | jq --arg p "$MAINWP_PROFILE" --arg v "$value" "$expr")"
	mainwp_config_save "$cfg"
}

# Set the active profile name in the on-disk config. Loads the current
# config itself; any positional argument is ignored (kept for callers
# that historically passed the loaded config in).
mainwp_config_set_active() {
	local cfg
	cfg="$(mainwp_config_load)"
	cfg="$(printf '%s' "$cfg" | jq --arg p "$MAINWP_PROFILE" '.active = $p')"
	mainwp_config_save "$cfg"
}

# List all configured profile names.
mainwp_config_list_profiles() {
	local cfg
	cfg="$(mainwp_config_load)"
	printf '%s' "$cfg" | jq -r '.profiles | keys[]'
}

# Remove a profile and its credentials from disk.
mainwp_config_delete_profile() {
	local name="$1"
	local cfg
	cfg="$(mainwp_config_load)"
	cfg="$(printf '%s' "$cfg" | jq --arg p "$name" 'del(.profiles[$p])')"
	mainwp_config_save "$cfg"
}

# Validate that a URL is non-empty and uses http(s).
mainwp_config_validate_url() {
	local url="$1"
	[[ -n "$url" ]] || {
		mainwp_die "URL cannot be empty."
		return 1
	}
	if [[ ! "$url" =~ ^https?:// ]]; then
		mainwp_die "URL must start with http:// or https:// (got: $url)"
	fi
	# Strip trailing slash for consistency.
	printf '%s' "${url%/}"
}

# Sanity check: the active profile is configured. Exits with a helpful
# message pointing the user to `mainwp init` if it is not.
mainwp_config_require() {
	if ! mainwp_config_url >/dev/null 2>&1; then
		mainwp_die "No dashboard URL configured for profile '${MAINWP_PROFILE}'. Run: mainwp init"
	fi
	if ! mainwp_config_key >/dev/null 2>&1; then
		mainwp_die "No API key configured for profile '${MAINWP_PROFILE}'. Run: mainwp init"
	fi
}
