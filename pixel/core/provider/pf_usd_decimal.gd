class_name PFUsdDecimal
extends RefCounted

## Pure decimal USD conversion shared by Provider normalization and the ledger boundary.

const MICRO_USD_PER_USD := 1000000
const MAX_CANONICAL_MICRO_USD := 999999999999999
const DECIMAL_PATTERN := "^(0|[1-9][0-9]{0,8})(?:[.]([0-9]+))?$"


static func parse_to_micro(value: Variant) -> Variant:
	if not (value is String):
		return null
	var matched := RegEx.create_from_string(DECIMAL_PATTERN).search(String(value))
	if matched == null:
		return null
	var whole_micro := matched.get_string(1).to_int() * MICRO_USD_PER_USD
	var fraction := matched.get_string(2)
	var micro_usd := whole_micro + fraction.substr(0, 6).rpad(6, "0").to_int()
	if fraction.length() > 6 and fraction.unicode_at(6) >= "5".unicode_at(0):
		micro_usd += 1
	return micro_usd if micro_usd <= MAX_CANONICAL_MICRO_USD else null


static func format_micro(micro_usd: int) -> Variant:
	if micro_usd < 0 or micro_usd > MAX_CANONICAL_MICRO_USD:
		return null
	return "%d.%06d" % [micro_usd / MICRO_USD_PER_USD, micro_usd % MICRO_USD_PER_USD]
