class_name PFGridDetector
extends RefCounted

## 伪像素图网格检测器。
## contract: 03-milestones/M1-cleanup-pipeline.md §M1-2；返回 scale/offset/confidence，不直接修改图像。

const ImageMath := preload("res://core/util/image_math.gd")

const DEFAULT_MIN_LAG := 2.0
const DEFAULT_MAX_LAG := 64.0
const LAG_STEP := 0.1
const OFFSET_STEP := 0.25
const LOW_CONFIDENCE_THRESHOLD := 2.0
const EPSILON := 0.000001


static func detect(source: Image, params: Dictionary = {}) -> Dictionary:
	var image := ImageMath.duplicate_rgba8(source)
	var grayscale := _to_grayscale(image)
	var gradients := _sobel_magnitude(grayscale, image.get_width(), image.get_height())
	var x_projection := _project_columns(gradients, image.get_width(), image.get_height())
	var y_projection := _project_rows(gradients, image.get_width(), image.get_height())
	var search_range := _resolve_search_range(image, params)
	var preferred_scale := _resolve_preferred_scale(image, params)

	var x_period := _find_period(x_projection, search_range.x, search_range.y, preferred_scale)
	var y_period := _find_period(y_projection, search_range.x, search_range.y, preferred_scale)
	var scale_x := float(x_period["period"])
	var scale_y := float(y_period["period"])
	var scale := maxf(1.0, (scale_x + scale_y) * 0.5)
	var non_square_ratio := absf(scale_x - scale_y) / maxf(scale, EPSILON)
	var offset := Vector2(_find_offset(x_projection, scale), _find_offset(y_projection, scale))
	var confidence := minf(float(x_period["confidence"]), float(y_period["confidence"]))

	return {
		"scale": scale,
		"scale_x": scale_x,
		"scale_y": scale_y,
		"non_square_warning": non_square_ratio > 0.1,
		"non_square_ratio": non_square_ratio,
		"offset": offset,
		"confidence": confidence,
		"threshold": LOW_CONFIDENCE_THRESHOLD,
		"status": "ok" if confidence >= LOW_CONFIDENCE_THRESHOLD else "low_confidence",
	}


static func _resolve_search_range(image: Image, params: Dictionary) -> Vector2:
	var min_lag := float(params.get("min_lag", DEFAULT_MIN_LAG))
	var max_lag := float(params.get("max_lag", DEFAULT_MAX_LAG))
	if params.has("prior_scale"):
		var prior := float(params["prior_scale"])
		if prior > 0.0:
			min_lag = maxf(DEFAULT_MIN_LAG, prior * 0.7)
			max_lag = minf(DEFAULT_MAX_LAG, prior * 1.3)
	elif params.has("base_size"):
		var base_size := maxf(1.0, float(params["base_size"]))
		var prior_from_size := maxf(float(image.get_width()), float(image.get_height())) / base_size
		min_lag = maxf(DEFAULT_MIN_LAG, prior_from_size * 0.7)
		max_lag = minf(DEFAULT_MAX_LAG, prior_from_size * 1.3)

	if max_lag <= min_lag:
		max_lag = min_lag + 1.0
	return Vector2(min_lag, max_lag)


static func _resolve_preferred_scale(image: Image, params: Dictionary) -> float:
	if params.has("prior_scale"):
		return maxf(0.0, float(params["prior_scale"]))
	if params.has("base_size"):
		var base_size := maxf(1.0, float(params["base_size"]))
		return maxf(float(image.get_width()), float(image.get_height())) / base_size
	return 0.0


static func _to_grayscale(image: Image) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(image.get_width() * image.get_height())
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			output[y * image.get_width() + x] = color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return output


static func _sobel_magnitude(
	gray: PackedFloat32Array, width: int, height: int
) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(width * height)
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var tl := gray[(y - 1) * width + x - 1]
			var tc := gray[(y - 1) * width + x]
			var tr := gray[(y - 1) * width + x + 1]
			var ml := gray[y * width + x - 1]
			var mr := gray[y * width + x + 1]
			var bl := gray[(y + 1) * width + x - 1]
			var bc := gray[(y + 1) * width + x]
			var br := gray[(y + 1) * width + x + 1]
			var gx := -tl - 2.0 * ml - bl + tr + 2.0 * mr + br
			var gy := -tl - 2.0 * tc - tr + bl + 2.0 * bc + br
			output[y * width + x] = sqrt(gx * gx + gy * gy)
	return output


static func _project_columns(
	values: PackedFloat32Array, width: int, height: int
) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(width)
	for x in range(width):
		var total := 0.0
		for y in range(height):
			total += values[y * width + x]
		output[x] = total
	return output


static func _project_rows(
	values: PackedFloat32Array, width: int, height: int
) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(height)
	for y in range(height):
		var total := 0.0
		for x in range(width):
			total += values[y * width + x]
		output[y] = total
	return output


static func _find_period(
	samples: PackedFloat32Array, min_lag: float, max_lag: float, preferred_lag: float = 0.0
) -> Dictionary:
	var centered := _center_signal(samples)
	if _mean_abs(centered) < EPSILON:
		return {"period": min_lag, "confidence": 0.0}

	var lag_values := []
	var score_values := []
	var best_score := -INF
	var best_lag := min_lag
	var steps := maxi(1, int(round((max_lag - min_lag) / LAG_STEP)))
	for step in range(steps + 1):
		var lag := min_lag + float(step) * LAG_STEP
		var score := _autocorrelation_score(centered, lag)
		lag_values.append(lag)
		score_values.append(score)
		if score > best_score:
			best_score = score
			best_lag = lag

	var selected_lag := _select_lag(lag_values, score_values, best_lag, best_score, preferred_lag)
	var selected_score := _score_at_lag(lag_values, score_values, selected_lag)
	var confidence_score := best_score if preferred_lag > 0.0 else selected_score
	var confidence_scale := 1.35 if preferred_lag > 0.0 else 1.0
	var mean_score := _mean_positive(score_values)
	var confidence := maxf(0.0, confidence_score) / maxf(mean_score, EPSILON) * confidence_scale
	return {
		"period": selected_lag,
		"confidence": confidence,
	}


static func _center_signal(samples: PackedFloat32Array) -> PackedFloat32Array:
	var mean := 0.0
	for value in samples:
		mean += value
	mean /= maxf(1.0, float(samples.size()))

	var output := PackedFloat32Array()
	output.resize(samples.size())
	for index in range(samples.size()):
		output[index] = samples[index] - mean
	return output


static func _autocorrelation_score(samples: PackedFloat32Array, lag: float) -> float:
	var limit := samples.size() - int(ceil(lag)) - 1
	if limit <= 1:
		return 0.0

	var total := 0.0
	for index in range(limit):
		total += samples[index] * _sample_signal(samples, float(index) + lag)
	return total / float(limit)


static func _select_lag(
	lags: Array, scores: Array, best_lag: float, best_score: float, preferred_lag: float
) -> float:
	if preferred_lag > 0.0:
		return preferred_lag
	return _first_strong_local_peak(lags, scores, best_lag, best_score)


static func _first_strong_local_peak(
	lags: Array, scores: Array, best_lag: float, best_score: float
) -> float:
	var threshold := best_score * 0.72
	for index in range(1, scores.size() - 1):
		var score := float(scores[index])
		if (
			score >= threshold
			and score >= float(scores[index - 1])
			and score >= float(scores[index + 1])
		):
			return float(lags[index])
	return best_lag


static func _score_at_lag(lags: Array, scores: Array, lag: float) -> float:
	var best_distance := INF
	var selected_score := 0.0
	for index in range(lags.size()):
		var distance := absf(float(lags[index]) - lag)
		if distance < best_distance:
			best_distance = distance
			selected_score = float(scores[index])
	return selected_score


static func _find_offset(projection: PackedFloat32Array, scale: float) -> float:
	if projection.is_empty() or scale <= 0.0:
		return 0.0

	var best_offset := 0.0
	var best_score := -INF
	var steps := maxi(1, int(ceil(scale / OFFSET_STEP)))
	for step in range(steps):
		var offset := float(step) * OFFSET_STEP
		var score := 0.0
		var position := offset
		while position < float(projection.size()):
			score += _sample_signal(projection, position)
			position += scale
		if score > best_score:
			best_score = score
			best_offset = offset
	return best_offset


static func _sample_signal(samples: PackedFloat32Array, position: float) -> float:
	var left := floori(position)
	var right := left + 1
	if left < 0 or left >= samples.size():
		return 0.0
	if right >= samples.size():
		return samples[left]
	var ratio := position - float(left)
	return lerpf(samples[left], samples[right], ratio)


static func _mean_abs(samples: PackedFloat32Array) -> float:
	var total := 0.0
	for value in samples:
		total += absf(value)
	return total / maxf(1.0, float(samples.size()))


static func _mean_positive(values: Array) -> float:
	var total := 0.0
	var count := 0
	for value in values:
		var number := float(value)
		if number > 0.0:
			total += number
			count += 1
	return total / maxf(1.0, float(count))
