# shellcheck shell=bash
# api.sh - HTTP client for the MainWP REST API v2
# Performs requests, handles authentication, surfaces API errors, and
# returns parsed JSON to stdout.

# curl options used for every request.
_mainwp_curl_common() {
	echo --silent --show-error --fail-with-body
	echo --connect-timeout 10
	echo --max-time 60
}

# Issue a MainWP API request.
#
# Usage: mainwp_api METHOD PATH [JSON_BODY] [EXTRA_QUERY_PARAMS...]
# METHOD  - HTTP verb (GET, POST, PUT, PATCH, DELETE)
# PATH    - Endpoint path beginning with "/" (e.g. "/sites")
# JSON_BODY - Optional JSON string to send as the request body.
# EXTRA   - Optional "key=value" pairs appended as query string parameters
#           for GET/DELETE, or merged into the body for write methods.
#
# Output: raw response body on stdout, exits non-zero on transport or
# API error with the API error message written to stderr.
mainwp_api() {
	local method="$1" path="$2" body="${3:-}"
	shift 3 || true

	mainwp_config_require

	local url key api_path
	url="$(mainwp_config_url)"
	key="$(mainwp_config_key)"
	api_path="$(mainwp_config_api_path)"

	# Build the full URL, stripping any leading slash from $path and any
	# trailing slash from $api_path so concatenation is safe.
	local full="${url%/}/${api_path#/}/${path#/}"

	# Split remaining args into query (GET/DELETE) or body (others).
	local query_args=() body_args=()
	local pair key_arg value_arg
	for pair in "$@"; do
		if [[ "$method" == "GET" || "$method" == "DELETE" ]]; then
			query_args+=("$pair")
		else
			key_arg="${pair%%=*}"
			value_arg="${pair#*=}"
			body_args+=("\"$key_arg\":\"$value_arg\"")
		fi
	done

	# Append query string for GET/DELETE when extra args exist.
	if [[ ${#query_args[@]} -gt 0 ]]; then
		local qs="?"
		local first=1
		for pair in "${query_args[@]}"; do
			key_arg="${pair%%=*}"
			value_arg="${pair#*=}"
			if [[ $first -eq 1 ]]; then
				qs+="${key_arg}=${value_arg}"
				first=0
			else
				qs+="&${key_arg}=${value_arg}"
			fi
		done
		full="${full}${qs}"
	fi

	# Merge body_args into a JSON object if a body wasn't already supplied.
	if [[ -n "$body" && ${#body_args[@]} -gt 0 ]]; then
		mainwp_die "Pass either a JSON body or key=value extras, not both."
	fi
	if [[ -z "$body" && ${#body_args[@]} -gt 0 ]]; then
		body="{$(
			IFS=,
			echo "${body_args[*]}"
		)}"
	fi

	# Build curl options.
	local -a opts
	opts=(-sS --fail-with-body --connect-timeout 10 --max-time 60
		-X "$method"
		-H "Authorization: Bearer ${key}"
		-H "Accept: application/json")

	if [[ -n "$body" ]]; then
		opts+=(-H "Content-Type: application/json" --data-raw "$body")
	fi

	local http_code
	local tmp_body tmp_headers
	tmp_body="$(mktemp)"
	tmp_headers="$(mktemp)"
	# shellcheck disable=SC2064
	trap "rm -f '$tmp_body' '$tmp_headers'" RETURN

	if ! http_code="$(curl "${opts[@]}" -o "$tmp_body" -w '%{http_code}' "$full" 2>"$tmp_headers")"; then
		local curl_err
		curl_err="$(cat "$tmp_headers")"
		mainwp_die "Network error contacting ${url}: ${curl_err:-connection failed}"
	fi

	local payload
	payload="$(cat "$tmp_body")"

	# Treat 2xx as success. Everything else is an error.
	if [[ ! "$http_code" =~ ^2 ]]; then
		local api_msg
		api_msg="$(printf '%s' "$payload" | jq -r '.message // .error // .' 2>/dev/null || printf '%s' "$payload")"
		mainwp_die "API ${method} ${path} failed (HTTP ${http_code}): ${api_msg}"
	fi

	printf '%s' "$payload"
}

# Convenience helpers for common verbs. Each accepts the same args as
# mainwp_api minus the method.
#
# `mainwp_api_get` and `mainwp_api_delete` have no body (the verb does
# not carry a payload), so any extra positional arguments are treated
# as query-string pairs. `mainwp_api_post/put/patch` keep the original
# signature where the first positional after path is the JSON body.
mainwp_api_get() { mainwp_api GET "$1" "" "${@:2}"; }
mainwp_api_delete() { mainwp_api DELETE "$1" "" "${@:2}"; }
mainwp_api_post() { mainwp_api POST "$@"; }
mainwp_api_put() { mainwp_api PUT "$@"; }
mainwp_api_patch() { mainwp_api PATCH "$@"; }
mainwp_api_delete() { mainwp_api DELETE "$@"; }
