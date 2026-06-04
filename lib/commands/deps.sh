# shellcheck shell=bash
# deps.sh - Optional dependency management subcommand.
# Provides `mainwp deps status` and `mainwp deps install` for users
# who installed mainwp outside of Homebrew (and therefore did not get
# gum/jq as automatic dependencies).
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_deps_help() {
	cat <<'EOF'
deps - Check and install optional runtime dependencies

Usage:
  mainwp deps [SUBCOMMAND]

Subcommands:
  status    Print which optional dependencies are present or missing
            (default).
  install   Detect the system package manager (brew, apt, dnf, pacman,
            or apk) and offer to install the missing dependencies.

Optional dependencies:
  gum   Styled output, interactive prompts, and the progress spinner.
        Falls back to plain text and `read` when missing.
  jq    Pretty-prints and shapes JSON responses. Falls back to raw
        output when missing.
EOF
}

cmd_deps() {
	_mainwp_parse_common_flags "$@" >/dev/null
	if [[ ${#REMAINING[@]} -gt 0 ]]; then
		set -- "${REMAINING[@]}"
	else
		set --
	fi
	local sub="${1:-status}"
	if [[ $# -gt 0 ]]; then shift; fi

	case "$sub" in
	status) cmd_deps_status "$@" ;;
	install) cmd_deps_install "$@" ;;
	-h | --help | help) cmd_deps_help ;;
	*) mainwp_die "Unknown deps subcommand: '$sub'" ;;
	esac
}

cmd_deps_status() {
	local present=() missing=() dep ver
	for dep in "${MAINWP_OPTIONAL_DEPS[@]}"; do
		if command -v "$dep" >/dev/null 2>&1; then
			ver="$("$dep" --version 2>/dev/null | head -1)"
			present+=("${dep} (${ver:-unknown})")
		else
			missing+=("${dep}")
		fi
	done

	if [[ $MAINWP_OUTPUT_FORMAT == "json" ]]; then
		local p_json m_json
		if [[ ${#present[@]} -gt 0 ]]; then
			p_json="$(printf '%s\n' "${present[@]}" | jq -R . | jq -s .)"
		else
			p_json="[]"
		fi
		if [[ ${#missing[@]} -gt 0 ]]; then
			m_json="$(printf '%s\n' "${missing[@]}" | jq -R . | jq -s .)"
		else
			m_json="[]"
		fi
		jq -n --argjson p "$p_json" --argjson m "$m_json" '{present: $p, missing: $m}'
		return 0
	fi

	printf 'Present:\n'
	if [[ ${#present[@]} -eq 0 ]]; then
		printf '  (none)\n'
	else
		for entry in "${present[@]}"; do
			printf '  ✓ %s\n' "$entry"
		done
	fi
	printf 'Missing:\n'
	if [[ ${#missing[@]} -eq 0 ]]; then
		printf '  (none)\n'
		return 0
	fi
	for entry in "${missing[@]}"; do
		printf '  ✗ %s\n' "$entry"
	done

	local pm cmd
	pm="$(mainwp_detect_package_manager)"
	if [[ -n "$pm" ]]; then
		cmd="$(mainwp_install_cmd_for "$pm" "${missing[@]}")"
		mainwp_info "Install with: ${cmd}"
	else
		mainwp_info "No supported package manager detected; install ${missing[*]} manually for your platform."
	fi
}

cmd_deps_install() {
	mainwp_ensure_deps
}
