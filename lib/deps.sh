# deps.sh - Detect and optionally install optional runtime dependencies
# (gum and jq). The CLI works without them, but the experience is much
# nicer when they are present.

# List of optional dependencies this CLI looks for. Add new entries
# here as features grow.
MAINWP_OPTIONAL_DEPS=(gum jq)

# Print the names of missing optional dependencies, one per line.
# Returns 0 if everything is present, 1 if anything is missing.
mainwp_deps_missing() {
	local missing=0 dep
	for dep in "${MAINWP_OPTIONAL_DEPS[@]}"; do
		if ! command -v "$dep" >/dev/null 2>&1; then
			printf '%s\n' "$dep"
			missing=1
		fi
	done
	return $missing
}

# Detect the system package manager. Echoes one of:
#   brew | apt | dnf | pacman | apk | ""
# Empty string means we could not identify a supported one.
mainwp_detect_package_manager() {
	local os
	os="$(uname -s 2>/dev/null || echo unknown)"
	case "$os" in
	Darwin)
		command -v brew >/dev/null 2>&1 && {
			echo brew
			return
		}
		;;
	Linux)
		command -v apt-get >/dev/null 2>&1 && {
			echo apt
			return
		}
		command -v dnf >/dev/null 2>&1 && {
			echo dnf
			return
		}
		command -v pacman >/dev/null 2>&1 && {
			echo pacman
			return
		}
		command -v apk >/dev/null 2>&1 && {
			echo apk
			return
		}
		;;
	esac
	echo ""
}

# Build the install command for a given package manager and a list of
# package names. Echoes the command string, or empty if unsupported.
mainwp_install_cmd_for() {
	local pm="$1"
	shift
	[[ $# -eq 0 ]] && {
		echo ""
		return
	}
	local pkgs="$*"
	case "$pm" in
	brew) echo "brew install $pkgs" ;;
	apt) echo "sudo apt-get update >/dev/null && sudo apt-get install -y $pkgs" ;;
	dnf) echo "sudo dnf install -y $pkgs" ;;
	pacman) echo "sudo pacman -S --noconfirm $pkgs" ;;
	apk) echo "sudo apk add --no-cache $pkgs" ;;
	*) echo "" ;;
	esac
}

# Check for missing optional deps. In interactive mode, offer to
# install them through the detected package manager. In non-interactive
# mode, just print what is missing and how to install it. Idempotent.
mainwp_ensure_deps() {
	local missing=()
	local dep
	while IFS= read -r dep; do
		[[ -n "$dep" ]] && missing+=("$dep")
	done < <(mainwp_deps_missing)

	if [[ ${#missing[@]} -eq 0 ]]; then
		return 0
	fi

	mainwp_warn "Missing optional dependencies: ${missing[*]}"
	mainwp_info "mainwp works without them (falls back to plain text and raw JSON), but the experience is much nicer when they are present."

	local pm cmd
	pm="$(mainwp_detect_package_manager)"

	if [[ -z "$pm" ]]; then
		mainwp_info "No supported package manager detected. Install ${missing[*]} manually for your platform."
		return 0
	fi

	cmd="$(mainwp_install_cmd_for "$pm" "${missing[@]}")"
	mainwp_info "Detected package manager: ${pm}"
	mainwp_info "Suggested command: ${cmd}"

	if [[ $MAINWP_INTERACTIVE -eq 0 ]]; then
		mainwp_info "Non-interactive mode: skipping install. Run the command above when convenient."
		return 0
	fi

	if mainwp_confirm "Install missing dependencies with ${pm}?"; then
		mainwp_info "Running: ${cmd}"
		if bash -c "$cmd"; then
			mainwp_success "Dependencies installed."
			# Re-check so the caller knows the final state.
			missing=()
			while IFS= read -r dep; do
				[[ -n "$dep" ]] && missing+=("$dep")
			done < <(mainwp_deps_missing)
			if [[ ${#missing[@]} -gt 0 ]]; then
				mainwp_warn "Still missing after install: ${missing[*]}"
			fi
		else
			mainwp_warn "Installation failed. Try the command above manually."
		fi
	else
		mainwp_info "Skipped. You can run \`mainwp deps install\` later."
	fi
}
