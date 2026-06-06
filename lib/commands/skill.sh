# shellcheck shell=bash
# skill.sh - Install the mainwp-cli skill into one or more AI agents.
#
# Each agent gets a copy of $MAINWP_ROOT/skills/mainwp-cli/ placed in
# its known skills directory. The list of supported agents is
# declared in MAINWP_SKILL_AGENTS at the top of this file; add a new
# entry there to support more agents.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

# Subcommand: install (default)
# Usage:
#   mainwp skill install
#   mainwp skill install --all
#   mainwp skill install --agent claude-code --agent codex
#
# The default (no flags, interactive) shows a gum multi-select over
# the supported agents. Selecting "all" expands to the full list.

# List of supported agents. Format: "name:skills-root-dir".
# `name` is what the user types or selects; `skills-root-dir` is
# the directory under which the mainwp-cli skill is installed.
# Use $HOME for paths that should expand at install time.
MAINWP_SKILL_AGENTS=(
	"claude-code:$HOME/.claude/skills"
	"codex:$HOME/.codex/skills"
	"pi:$HOME/.pi/agent/skills"
	"opencode:$HOME/.config/opencode/skills"
	"hermes:$HOME/.hermes/skills"
	"global:$HOME/.agents/skills"
)

# Display labels for the interactive picker. Order must match
# MAINWP_SKILL_AGENTS plus a trailing "all" entry.
MAINWP_SKILL_LABELS=(
	"claude-code  (~/.claude/skills)"
	"codex        (~/.codex/skills)"
	"pi           (~/.pi/agent/skills)"
	"opencode     (~/.config/opencode/skills)"
	"hermes       (~/.hermes/skills)"
	"global       (~/.agents/skills)"
	"all          (every agent above)"
)

# The skill bundle name (the directory under each skills root).
MAINWP_SKILL_NAME="mainwp-cli"

# Resolve the on-disk location of the skill bundle inside the repo.
mainwp_skill_source_dir() {
	printf '%s/skills/%s\n' "$MAINWP_ROOT" "$MAINWP_SKILL_NAME"
}

# Look up the skills root for an agent name. Echoes the path, or
# empty if the name is not in MAINWP_SKILL_AGENTS.
mainwp_skill_target_for() {
	local agent="$1"
	local entry name path
	for entry in "${MAINWP_SKILL_AGENTS[@]}"; do
		name="${entry%%:*}"
		if [[ "$name" == "$agent" ]]; then
			path="${entry#*:}"
			# Expand a leading $HOME so the path is usable on disk.
			# SC2016 is intentional: the comparison is against the
			# literal "$HOME" string in the agent entry.
			# shellcheck disable=SC2016
			[[ "$path" == '$HOME'* ]] && path="$HOME${path#\$HOME}"
			printf '%s\n' "$path"
			return 0
		fi
	done
	return 1
}

# Copy the skill bundle into the given skills root. The skill ends
# up at <root>/<MAINWP_SKILL_NAME>/. Existing files are overwritten.
mainwp_skill_install_to() {
	local target_root="$1"
	local source target
	source="$(mainwp_skill_source_dir)"
	target="$target_root/$MAINWP_SKILL_NAME"

	if [[ ! -d "$source" ]]; then
		mainwp_die "Skill bundle not found: $source (is the mainwp-cli install complete?)"
	fi
	if [[ ! -f "$source/SKILL.md" ]]; then
		mainwp_die "Skill bundle is missing SKILL.md: $source"
	fi

	mkdir -p "$target" || mainwp_die "Could not create $target"
	# Copy contents, not the directory itself, so the layout inside
	# each agent's skills root is identical.
	cp -R "$source"/. "$target"/ || mainwp_die "Could not copy skill into $target"
	printf '%s\n' "$target"
}

cmd_skill_help() {
	cat <<EOF
skill - Install the mainwp-cli skill into AI agents

Usage:
  mainwp skill SUBCOMMAND [OPTIONS]

Subcommands:
  install                   Install the skill. Interactive by default.

Install options:
  --all                     Install into every supported agent.
  --global                  Install only into the shared ~/.agents/skills/
                            location (overrides --all/--agent).
  --agent NAME              Install into one agent (repeatable).
  -h, --help                Show this help.

Supported agents (and where the skill is installed):
EOF
	local entry name path
	for entry in "${MAINWP_SKILL_AGENTS[@]}"; do
		name="${entry%%:*}"
		path="${entry#*:}"
		# SC2016 is intentional: literal $HOME comparison.
		# shellcheck disable=SC2016
		[[ "$path" == '$HOME'* ]] && path='$HOME'${path#\$HOME}
		printf '  %-12s %s\n' "$name" "$path/mainwp-cli/"
	done
	cat <<EOF

  "all" is also accepted in interactive mode and expands to every
  entry above. The installed skill is the SKILL.md and any helper
  files under skills/mainwp-cli/ in the mainwp-cli repo (or the
  installed copy).
EOF
}

cmd_skill() {
	# The printf+eval pattern is required: the helper outputs assignment
	# text to stdout, and the caller evals it so REMAINING is set in
	# this scope (bash 3.2 has no `declare -g`). Output is suppressed
	# so the user does not see raw `REMAINING=(...)` on stderr.
	eval "$(_mainwp_parse_common_flags "$@")" >/dev/null
	if [[ ${#REMAINING[@]} -gt 0 ]]; then
		set -- "${REMAINING[@]}"
	else
		set --
	fi
	local sub="${1:-install}"
	if [[ $# -gt 0 ]]; then
		shift
	fi
	case "$sub" in
	install) cmd_skill_install "$@" ;;
	-h | --help | help) cmd_skill_help ;;
	*) mainwp_die "Unknown skill subcommand: '$sub' (run: mainwp skill --help)" ;;
	esac
}

cmd_skill_install() {
	local selected=()
	local all=false
	local global_only=false
	local agents=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--all)
			all=true
			shift
			;;
		--global)
			# Force the shared ~/.agents/skills/ install, even if the
			# flag is combined accidentally with broader selectors.
			global_only=true
			agents+=("global")
			shift
			;;
		--agent)
			[[ $# -ge 2 ]] || mainwp_die "--agent requires a name."
			agents+=("$2")
			shift 2
			;;
		-h | --help)
			cmd_skill_help
			return 0
			;;
		*)
			mainwp_die "Unknown option: $1 (run: mainwp skill install --help)"
			;;
		esac
	done

	# ---- pick agents -------------------------------------------

	if [[ "$global_only" == true ]]; then
		selected=("global")
	elif [[ "$all" == true ]]; then
		local entry name
		for entry in "${MAINWP_SKILL_AGENTS[@]}"; do
			name="${entry%%:*}"
			selected+=("$name")
		done
	elif [[ ${#agents[@]} -gt 0 ]]; then
		selected=("${agents[@]}")
	elif [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		# Interactive multi-select.
		if command -v gum >/dev/null 2>&1; then
			local raw
			raw="$(gum choose --no-limit \
				--header "Install mainwp-cli skill in which agents? (space to toggle, enter to confirm)" \
				--height 10 \
				"${MAINWP_SKILL_LABELS[@]}")" || mainwp_warn "Cancelled."
			# gum prints the labels; map them back to short names.
			local label
			while IFS= read -r label; do
				[[ -z "$label" ]] && continue
				# Strip the description after the first whitespace.
				selected+=("${label%% *}")
			done <<<"$raw"
		else
			# Plain fallback.
			printf 'Install mainwp-cli skill in which agents? (comma-separated, or "all")\n'
			printf '  Options: '
			local first=1 entry name
			for entry in "${MAINWP_SKILL_AGENTS[@]}"; do
				name="${entry%%:*}"
				if [[ $first -eq 1 ]]; then
					printf '%s' "$name"
					first=0
				else
					printf ', %s' "$name"
				fi
			done
			printf ', all\n'
			local reply
			read -r reply
			IFS=',' read -ra selected <<<"$reply"
			# Trim whitespace from each entry.
			local i
			for i in "${!selected[@]}"; do
				# shellcheck disable=SC2004  # $i is the index, not arithmetic
				selected[$i]="${selected[$i]// /}"
			done
		fi

		# Expand "all" if it was selected.
		local contains_all=false s
		for s in "${selected[@]:-}"; do
			[[ "$s" == "all" ]] && contains_all=true
		done
		if [[ "$contains_all" == true ]]; then
			selected=()
			local entry name
			for entry in "${MAINWP_SKILL_AGENTS[@]}"; do
				name="${entry%%:*}"
				selected+=("$name")
			done
		fi
	else
		mainwp_die "Non-interactive mode requires --agent NAME or --all."
	fi

	# ---- validate ------------------------------------------------

	if [[ ${#selected[@]} -eq 0 ]]; then
		mainwp_warn "No agents selected; nothing to install."
		return 0
	fi

	local unknown=()
	local agent
	for agent in "${selected[@]}"; do
		if ! mainwp_skill_target_for "$agent" >/dev/null; then
			unknown+=("$agent")
		fi
	done
	if [[ ${#unknown[@]} -gt 0 ]]; then
		mainwp_die "Unknown agent(s): ${unknown[*]}. Run: mainwp skill --help"
	fi

	# ---- install -------------------------------------------------

	mainwp_info "Installing skill into ${#selected[@]} location(s)..."
	local target_root
	for agent in "${selected[@]}"; do
		target_root="$(mainwp_skill_target_for "$agent")"
		mainwp_info "  -> $agent: $target_root/$MAINWP_SKILL_NAME/"
		if ! mainwp_skill_install_to "$target_root"; then
			mainwp_warn "  Failed to install for $agent (continuing)"
		fi
	done

	mainwp_success "Done. Restart the agent to pick up the new skill."
}
