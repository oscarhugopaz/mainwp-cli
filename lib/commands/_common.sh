# shellcheck shell=bash
# _common.sh - Shared helpers sourced by individual command files.
# The flag sentinel _MAINWP_COMMON_LOADED guards against redefinition when
# multiple command files source this module.
#
# IMPORTANT: bin/mainwp pre-declares the globals REMAINING and
# MAINWP_KV_FLAGS at the top level so that the helpers below can mutate
# them without making them local. bash 3.2 (the macOS system bash) does
# not have `declare -g`. The helpers use the "printf + eval" pattern:
# they output assignment text to stdout, and the caller runs that text
# with eval in its own scope, which is the global scope because of the
# pre-declaration.

if [[ -z "${_MAINWP_COMMON_LOADED:-}" ]]; then
	_MAINWP_COMMON_LOADED=1

	# Internal: build a "WORD=( %q %q ...)" string for a possibly-empty
	# array. Iterating with `${arr[@]}` under `set -u` errors when the
	# array is empty, so we go through positional parameters.
	_mainwp_quote_array() {
		local _first=1 _word="$1"
		shift
		printf '%s=(' "$_word"
		local _q
		for _q in "$@"; do
			if [[ $_first -eq 1 ]]; then
				printf ' %q' "$_q"
				_first=0
			else
				printf ' %q' "$_q"
			fi
		done
		printf ')'
	}

	# Parse per-command common flags out of "$@", printing shell
	# assignments for REMAINING (and any side-effect flags) to stdout.
	# The caller MUST eval the output, e.g.:
	#
	#   eval "$(_mainwp_parse_common_flags "$@")"
	#
	# After the eval, ${REMAINING[@]} contains all non-flag positional
	# arguments. The exported MAINWP_OUTPUT_FORMAT / MAINWP_INTERACTIVE /
	# MAINWP_QUIET / MAINWP_PROFILE variables are also updated.
	_mainwp_parse_common_flags() {
		local _items=()
		while [[ $# -gt 0 ]]; do
			case "$1" in
			--json)
				export MAINWP_OUTPUT_FORMAT="json"
				shift
				;;
			--plain)
				export MAINWP_OUTPUT_FORMAT="plain"
				shift
				;;
			--no-input)
				export MAINWP_INTERACTIVE=0
				shift
				;;
			-q | --quiet)
				export MAINWP_QUIET=1
				shift
				;;
			--profile)
				export MAINWP_PROFILE="$2"
				shift 2
				;;
			--)
				shift
				while [[ $# -gt 0 ]]; do
					_items+=("$1")
					shift
				done
				;;
			-h | --help)
				_items=("help")
				shift
				;;
			*)
				_items+=("$1")
				shift
				;;
			esac
		done
		# Emit assignment text. Using %q guarantees safe shell quoting.
		# We pass the array as positional args so empty arrays still work
		# under `set -u`.
		local _n=${#_items[@]}
		_mainwp_quote_array "REMAINING" "${_items[@]:+"${_items[@]}"}"
		printf '\n'
	}

	# Render a JSON array returned by a list endpoint using the configured
	# output mode. Arguments: array-json, header, jq-columns...
	_mainwp_render_list() {
		local json="$1" header="$2"
		shift 2
		mainwp_render_table "$header" "$@" <<<"$json"
	}

	# Extract --key=value / --key value pairs from REMAINING into
	# MAINWP_KV_FLAGS, removing them from REMAINING. Like parse, the
	# caller must eval the output:
	#
	#   eval "$(_mainwp_collect_kv_flags)"
	_mainwp_collect_kv_flags() {
		local _kvs=() _kept=()
		local i=0
		local _n=${#REMAINING[@]}
		while [[ $i -lt $_n ]]; do
			local arg="${REMAINING[$i]}"
			if [[ "$arg" == --*=* ]]; then
				_kvs+=("${arg#--}")
				i=$((i + 1))
			elif [[ "$arg" == --* && $((i + 1)) -lt $_n && "${REMAINING[$((i + 1))]}" != --* ]]; then
				_kvs+=("${arg#--}=${REMAINING[$((i + 1))]}")
				i=$((i + 2))
			else
				_kept+=("$arg")
				i=$((i + 1))
			fi
		done
		_mainwp_quote_array "MAINWP_KV_FLAGS" "${_kvs[@]:+"${_kvs[@]}"}"
		printf ' '
		_mainwp_quote_array "REMAINING" "${_kept[@]:+"${_kept[@]}"}"
		printf '\n'
	}
fi
