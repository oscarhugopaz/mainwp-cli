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

	# Coerce any of the three shapes MainWP endpoints can return into
	# a flat array suitable for `_mainwp_render_list`:
	#
	#   1. an array
	#      -> returned as-is
	#   2. a wrapped array
	#      {"success":1, "data":[...]}  or  {"success":1, "tags":[...]}
	#      -> unwrap
	#   3. an object whose values are objects
	#      {"9":{...}, "12":{...}}  (e.g. /tags)
	#      -> [values...] merged with their parent key as a fallback
	#         `id` (or `_key`) when the inner object does not have one
	#   4. an object whose values are arrays (e.g. /users returns
	#      data keyed by site URL, each value is an array of users)
	#      -> flatten into a single array; site URL is added as
	#         a `_site` field on each record so the table can show it
	#
	# Anything that does not match falls through to the caller, which
	# then hits `mainwp_render_object` for a key/value view.
	_mainwp_extract_list() {
		local input="$1"
		local type
		type="$(printf '%s' "$input" | jq -r 'type' 2>/dev/null)"

		case "$type" in
		array)
			printf '%s' "$input"
			;;
		object)
			# Recursive search for the "real" envelope under a
			# known wrapper key (most commonly `data`). A common
			# pitfall in earlier revisions was embedding the jq
			# program inside `$'...\n\t\t...'`; the ANSI-C quoting
			# left the literal `\n` and `\t` markers in the
			# program, which made jq parse them as identifiers and
			# silently return empty. We sidestep the problem by
			# piping a one-line jq program on stdin.
			local recurse
			recurse="$(printf '%s' "$input" | jq -c \
				'if (.data | type) == "array" then .data
					 elif (.data | type) == "object" then .data
					 elif ([.[] | select(type=="array")] | length) > 0 then .
					 else . end' 2>/dev/null)"
			if [[ "$(printf '%s' "$recurse" | jq -r 'type' 2>/dev/null)" == "array" ]]; then
				printf '%s' "$recurse"
				return
			fi

			# Object whose values are arrays (e.g. /users
			# response after recursing into .data). Flatten and
			# tag each record with the parent key as `site`.
			if [[ "$(printf '%s' "$recurse" | jq -r 'type' 2>/dev/null)" == "object" ]]; then
				local flat_arrays
				flat_arrays="$(printf '%s' "$recurse" | jq -c \
					'[ to_entries[] | .value[] + { site: .key } ]' 2>/dev/null)"
				if [[ -n "$flat_arrays" && "$flat_arrays" != "[]" && "$flat_arrays" != "null" ]]; then
					printf '%s' "$flat_arrays"
					return
				fi

				# Object whose values are objects (e.g. /tags).
				# Flatten to [values...].
				local flat_objects
				flat_objects="$(printf '%s' "$recurse" | jq -c '[.[]]' 2>/dev/null)"
				if [[ -n "$flat_objects" && "$flat_objects" != "[]" && "$flat_objects" != "null" ]]; then
					printf '%s' "$flat_objects"
					return
				fi
			fi

			# Fall through: return the input as-is so
			# mainwp_render_object can show it.
			printf '%s' "$input"
			;;
		*)
			printf '%s' "$input"
			;;
		esac
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
