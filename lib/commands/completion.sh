# shellcheck shell=bash
# completion.sh - Emit a shell completion script for bash or zsh.
# Usage: mainwp completion bash | zsh | fish

cmd_completion() {
	local shell="${1:-bash}"
	case "$shell" in
	bash)
		cat "$MAINWP_ROOT/completions/mainwp.bash"
		;;
	zsh)
		cat "$MAINWP_ROOT/completions/_mainwp"
		;;
	*)
		mainwp_die "Unknown shell: $shell. Use: bash, zsh."
		;;
	esac
}
