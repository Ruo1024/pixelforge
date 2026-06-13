extends "res://addons/gut/test.gd"

const Pipeline := preload("res://core/pixel/pipeline.gd")
const Quantizer := preload("res://core/pixel/quantizer.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")

const BATCH_SIZE := 50
# 计划口径：峰值帧 < 100ms、总耗时 < 60s；自动化环境放宽 3 倍。
# 本地复核可 PF_PERF_STRICT=1 启用严格预算。
const PEAK_FRAME_BUDGET_STRICT_MS := 100.0
const PEAK_FRAME_BUDGET_RELAXED_MS := 300.0
const TOTAL_BUDGET_STRICT_MS := 60000
const TOTAL_BUDGET_RELAXED_MS := 120000
# M1.1 复盘：8×8 基底放大 4 倍（32×32 输入）对预算毫无压力，断言形同空转。
# 改为 32×32 基底放大 4 倍（128×128 输入），更接近真实 AI 生成图的清洗负载。
const SPRITE_BASE_SIZE := Vector2i(32, 32)
const SPRITE_SCALE := 4


func test_batch_cleanup_keeps_main_thread_frame_time_under_budget() -> void:
	var strict := OS.get_environment("PF_PERF_STRICT") == "1"
	var peak_budget_ms := PEAK_FRAME_BUDGET_STRICT_MS if strict else PEAK_FRAME_BUDGET_RELAXED_MS
	var total_budget_ms := TOTAL_BUDGET_STRICT_MS if strict else TOTAL_BUDGET_RELAXED_MS
	var encoded_images := []
	for index in range(BATCH_SIZE):
		var original := FixtureGenerator.make_base_sprite(SPRITE_BASE_SIZE, index % 3)
		encoded_images.append(
			FixtureGenerator.scale_nearest(original, SPRITE_SCALE).save_png_to_buffer()
		)

	var params := {
		"detect": Pipeline.DETECT_MANUAL,
		"scale": float(SPRITE_SCALE),
		"quantize": Quantizer.MODE_AUTO_K,
		"k": 8,
	}

	var started := Time.get_ticks_msec()
	var peak_process_ms := 0.0
	var count := 0
	for encoded_image in encoded_images:
		var source_image := Image.new()
		var load_error := source_image.load_png_from_buffer(encoded_image)
		assert_eq(load_error, OK)
		if source_image.get_format() != Image.FORMAT_RGBA8:
			source_image.convert(Image.FORMAT_RGBA8)

		var item_started := Time.get_ticks_usec()
		Pipeline.apply(source_image, params)
		var item_ms := float(Time.get_ticks_usec() - item_started) / 1000.0
		count += 1
		await wait_process_frames(1)
		var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		peak_process_ms = maxf(peak_process_ms, maxf(item_ms, process_ms))

	var elapsed_ms := Time.get_ticks_msec() - started
	gut.p(
		(
			"batch cleanup peak_ms=%.2f total_ms=%d peak_budget_ms=%.0f total_budget_ms=%d"
			% [peak_process_ms, elapsed_ms, peak_budget_ms, total_budget_ms]
		)
	)
	assert_eq(count, BATCH_SIZE)
	assert_lt(peak_process_ms, peak_budget_ms)
	assert_lt(elapsed_ms, total_budget_ms)
