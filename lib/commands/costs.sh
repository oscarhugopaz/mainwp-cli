# shellcheck shell=bash
# costs.sh - Cost Tracker records.
# shellcheck source=lib/commands/_common.sh
. "$MAINWP_ROOT/lib/commands/_common.sh"

cmd_costs_help() {
	cat <<EOF
costs - Manage Cost Tracker records

Usage:
  mainwp costs SUBCOMMAND [OPTIONS] [ARGS...]

  list                      List cost records
  get ID                    Get one cost record
  add                       Add a cost (interactive or flags)
  edit ID                   Edit a cost record
  remove ID                 Delete a cost record
  sites ID                  List sites linked to a cost
  clients ID                List clients linked to a cost

Required fields for add: --name, --price, --payment-type, --product-type,
--renewal-type, plus one of --sites/--groups/--clients.
EOF
}

cmd_costs() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	local sub="${1:-list}"
	if [[ $# -gt 0 ]]; then shift; fi
	case "$sub" in
	list) cmd_costs_list "$@" ;;
	get) cmd_costs_get "$@" ;;
	add) cmd_costs_add "$@" ;;
	edit) cmd_costs_edit "$@" ;;
	remove) cmd_costs_remove "$@" ;;
	sites) cmd_costs_relationship sites "$@" ;;
	clients) cmd_costs_relationship clients "$@" ;;
	-h | --help) cmd_costs_help ;;
	*) mainwp_die "Unknown costs subcommand: '$sub'" ;;
	esac
}

cmd_costs_list() {
	eval "$(_mainwp_parse_common_flags "$@")"
	if [[ ${#REMAINING[@]} -gt 0 ]]; then set -- "${REMAINING[@]}"; else set --; fi
	eval "$(_mainwp_collect_kv_flags)"
	local response arr
	response="$(mainwp_api_get /costs "${MAINWP_KV_FLAGS[@]:-}")"
	arr="$(printf '%s' "$response" | jq -c '.data // .costs // []')"
	_mainwp_render_list "$arr" "ID,Name,Price,Type" \
		'.id // empty' '.name // empty' '.price // empty' '.product_type // empty'
}

cmd_costs_get() {
	local id="${1:?Usage: mainwp costs get ID}"
	local response
	response="$(mainwp_api_get "/costs/$id")"
	printf '%s' "$response" | mainwp_render_object
}

# Build the cost body from a small key/value set, supporting list fields
# like sites/groups/clients as JSON arrays.
_mainwp_costs_body() {
	local name="$1" price="$2" payment_type="$3" product_type="$4" renewal_type="$5"
	local sites="$6" groups="$7" clients="$8"
	shift 8
	local extra="$*"

	jq -n \
		--arg name "$name" \
		--arg price "$price" \
		--arg payment_type "$payment_type" \
		--arg product_type "$product_type" \
		--arg renewal_type "$renewal_type" \
		--arg sites "$sites" --arg groups "$groups" --arg clients "$clients" \
		--argjson extra "$extra" \
		'{
       name:$name, price:($price|tonumber? // 0), payment_type:$payment_type,
       product_type:$product_type, renewal_type:$renewal_type
     }
     + (if $sites   != "" then {sites:  ($sites   | split(","))} else {} end)
     + (if $groups  != "" then {groups: ($groups  | split(","))} else {} end)
     + (if $clients != "" then {clients:($clients | split(","))} else {} end)
     + $extra'
}

cmd_costs_add() {
	local name="" price="" payment_type="" product_type="" renewal_type=""
	local sites="" groups="" clients=""
	local extra='{}'
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			name="$2"
			shift 2
			;;
		--price)
			price="$2"
			shift 2
			;;
		--payment-type)
			payment_type="$2"
			shift 2
			;;
		--product-type)
			product_type="$2"
			shift 2
			;;
		--renewal-type)
			renewal_type="$2"
			shift 2
			;;
		--sites)
			sites="$2"
			shift 2
			;;
		--groups)
			groups="$2"
			shift 2
			;;
		--clients)
			clients="$2"
			shift 2
			;;
		--extra)
			extra="$2"
			shift 2
			;; # raw JSON object
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	if [[ $MAINWP_INTERACTIVE -eq 1 ]]; then
		[[ -z "$name" ]] && name="$(mainwp_ui_input "Cost name")"
		[[ -z "$price" ]] && price="$(mainwp_ui_input "Price" "0")"
		[[ -z "$payment_type" ]] && payment_type="$(mainwp_ui_input "Payment type (subscription|one-time)" "subscription")"
		[[ -z "$product_type" ]] && product_type="$(mainwp_ui_input "Product type (hosting|plugin|theme|...)" "hosting")"
		[[ -z "$renewal_type" ]] && renewal_type="$(mainwp_ui_input "Renewal type (monthly|yearly|...)" "monthly")"
		[[ -z "$sites" && -z "$groups" && -z "$clients" ]] && sites="$(mainwp_ui_input "Site IDs (comma-separated)" "")"
	fi
	[[ -n "$name" && -n "$price" && -n "$payment_type" && -n "$product_type" && -n "$renewal_type" ]] ||
		mainwp_die "name, price, payment-type, product-type, renewal-type are required."
	[[ -n "$sites$groups$clients" ]] || mainwp_die "Provide --sites, --groups, or --clients."

	local body
	body="$(_mainwp_costs_body "$name" "$price" "$payment_type" "$product_type" "$renewal_type" "$sites" "$groups" "$clients" "$extra")"
	local response
	response="$(mainwp_api_post /costs/add "$body")"
	mainwp_success "Cost created."
	printf '%s' "$response" | mainwp_render_object
}

cmd_costs_edit() {
	local id="${1:?Usage: mainwp costs edit ID}"
	shift
	local name="" price="" payment_type="" product_type="" renewal_type=""
	local sites="" groups="" clients=""
	local extra='{}'
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--name)
			name="$2"
			shift 2
			;;
		--price)
			price="$2"
			shift 2
			;;
		--payment-type)
			payment_type="$2"
			shift 2
			;;
		--product-type)
			product_type="$2"
			shift 2
			;;
		--renewal-type)
			renewal_type="$2"
			shift 2
			;;
		--sites)
			sites="$2"
			shift 2
			;;
		--groups)
			groups="$2"
			shift 2
			;;
		--clients)
			clients="$2"
			shift 2
			;;
		--extra)
			extra="$2"
			shift 2
			;;
		*) mainwp_die "Unknown option: $1" ;;
		esac
	done
	local body
	body="$(_mainwp_costs_body "$name" "$price" "$payment_type" "$product_type" "$renewal_type" "$sites" "$groups" "$clients" "$extra")"
	[[ "$body" != "{}" ]] || mainwp_die "Provide at least one field to update."
	local response
	response="$(mainwp_api_post "/costs/$id/edit" "$body")"
	mainwp_success "Cost updated."
	printf '%s' "$response" | mainwp_render_object
}

cmd_costs_remove() {
	local id="${1:?Usage: mainwp costs remove ID}"
	mainwp_confirm "Delete cost #$id?" || return 0
	local response
	response="$(mainwp_api_delete "/costs/$id/remove")"
	mainwp_success "Cost deleted."
	printf '%s' "$response" | mainwp_render_object
}

cmd_costs_relationship() {
	local rel="$1" id="${2:?missing ID}"
	local response
	response="$(mainwp_api_get "/costs/$id/$rel")"
	printf '%s' "$response" | mainwp_render_object
}
