class_name PFRetryScheduler
extends RefCounted

## Safe-GET retry timing boundary. Production waits use the scene tree; tests inject
## UTC/monotonic clocks and a manually advanced waiter so no wall-clock sleep is needed.

const MIN_DELAY_SECONDS := 0.25
const MAX_DELAY_SECONDS := 30.0
const FALLBACK_DELAYS := [0.5, 1.0]
const MONTHS := {
	"Jan": 1,
	"Feb": 2,
	"Mar": 3,
	"Apr": 4,
	"May": 5,
	"Jun": 6,
	"Jul": 7,
	"Aug": 8,
	"Sep": 9,
	"Oct": 10,
	"Nov": 11,
	"Dec": 12,
}

var _utc_now: Callable
var _monotonic_now: Callable
var _waiter: Callable


func _init(
	utc_now: Callable = Callable(),
	monotonic_now: Callable = Callable(),
	waiter: Callable = Callable()
) -> void:
	_utc_now = utc_now
	_monotonic_now = monotonic_now
	_waiter = waiter


func monotonic_msec() -> int:
	if _monotonic_now.is_valid():
		return int(_monotonic_now.call())
	return Time.get_ticks_msec()


func delay_for(attempt: int, response_headers: PackedStringArray) -> float:
	var retry_after := _header_value(response_headers, "retry-after")
	var parsed: Variant = _parse_retry_after(retry_after)
	if parsed != null:
		return clampf(float(parsed), MIN_DELAY_SECONDS, MAX_DELAY_SECONDS)
	var fallback_index := clampi(attempt, 0, FALLBACK_DELAYS.size() - 1)
	return float(FALLBACK_DELAYS[fallback_index])


func wait(delay_seconds: float) -> void:
	if _waiter.is_valid():
		await _waiter.call(delay_seconds)
		return
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		await (main_loop as SceneTree).create_timer(delay_seconds).timeout


func _parse_retry_after(value: String) -> Variant:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return null
	if normalized.is_valid_int():
		return float(normalized.to_int())
	var pieces := normalized.split(" ", false)
	if pieces.size() != 6 or pieces[5].to_upper() != "GMT":
		return null
	var day_text := pieces[1]
	var month_text := pieces[2]
	var year_text := pieces[3]
	var clock := pieces[4].split(":", false)
	if (
		not day_text.is_valid_int()
		or not year_text.is_valid_int()
		or not MONTHS.has(month_text)
		or clock.size() != 3
		or not clock[0].is_valid_int()
		or not clock[1].is_valid_int()
		or not clock[2].is_valid_int()
	):
		return null
	var target_unix := Time.get_unix_time_from_datetime_dict(
		{
			"year": year_text.to_int(),
			"month": int(MONTHS[month_text]),
			"day": day_text.to_int(),
			"hour": clock[0].to_int(),
			"minute": clock[1].to_int(),
			"second": clock[2].to_int(),
		}
	)
	return float(target_unix) - _utc_now_seconds()


func _utc_now_seconds() -> float:
	if _utc_now.is_valid():
		return float(_utc_now.call())
	return Time.get_unix_time_from_system()


func _header_value(headers: PackedStringArray, requested_name: String) -> String:
	for header in headers:
		var separator := header.find(":")
		if separator < 0:
			continue
		if header.substr(0, separator).strip_edges().to_lower() == requested_name:
			return header.substr(separator + 1).strip_edges()
	return ""
