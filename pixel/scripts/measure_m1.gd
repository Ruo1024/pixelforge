extends SceneTree

## M1 本地性能采样脚本。
## 输出 5 次采样的 p95，用于完成报告；严格门控仍由 GUT 性能断言兜底。

const PaletteScript := preload("res://core/pixel/palette.gd")
const GridDetector := preload("res://core/pixel/grid_detector.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")
const Quantizer := preload("res://core/pixel/quantizer.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")
const Log := preload("res://core/util/log_util.gd")

const SAMPLE_COUNT := 5


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(128, 128), 0)
	var pseudo := FixtureGenerator.scale_nearest(original, 4)
	var palette: PFPalette = PaletteScript.load_builtin("db32")

	var map_ms := _measure_p95_ms(func() -> void: PaletteScript.map_image(pseudo, palette))
	var detect_ms := _measure_p95_ms(
		func() -> void: GridDetector.detect(pseudo, {"prior_scale": 4.0})
	)
	var pipeline_ms := _measure_p95_ms(
		func() -> void:
			(
				Pipeline
				. apply(
					pseudo,
					{
						"detect": Pipeline.DETECT_MANUAL,
						"scale": 4.0,
						"quantize": Quantizer.MODE_AUTO_K,
						"k": 16,
					}
				)
			)
	)

	(
		Log
		. info(
			"M1 performance sample p95",
			{
				"samples": SAMPLE_COUNT,
				"palette_map_p95_ms": snapped(map_ms, 0.01),
				"grid_detect_p95_ms": snapped(detect_ms, 0.01),
				"cleanup_pipeline_p95_ms": snapped(pipeline_ms, 0.01),
			}
		)
	)
	quit()


func _measure_p95_ms(callable: Callable) -> float:
	var samples := []
	for _index in range(SAMPLE_COUNT):
		samples.append(_measure_ms(callable))
	samples.sort()
	var p95_index := clampi(int(ceil(float(samples.size()) * 0.95)) - 1, 0, samples.size() - 1)
	return float(samples[p95_index])


func _measure_ms(callable: Callable) -> float:
	var started := Time.get_ticks_usec()
	callable.call()
	return float(Time.get_ticks_usec() - started) / 1000.0
