# COVERAGE-MATRIX-M1.md — M1/M1.1 core 覆盖矩阵

> 统计口径：Godot 4.6.3 + 当前 vendored GUT 未提供可接入 headless 出口门控的行覆盖率报告。M1.1 使用 public API / 分支矩阵替代；`pixel/scripts/check_m1_1_coverage_matrix.sh` 会校验本表引用的测试名真实存在。

## core/pixel public API 覆盖

| 模块 | API / 行为 | 分支与边界 | 自动化测试 |
|---|---|---|---|
| `color_space.gd` | RGBA32、hex、RGB/OKLab 距离 | hex 往返、RGB/OKLab 边界最近色 | `test_rgb_and_oklab_nearest_color_boundaries`, `test_map_image_uses_exact_palette_colors` |
| `palette.gd` | 内置调色板加载 | 9 个内置板、颜色数 2-256 | `test_builtin_palettes_load_with_contract_counts` |
| `palette.gd` | `map_image()` | 重复色缓存、透明外的精确映射、512 图预算 | `test_map_image_uses_exact_palette_colors`, `test_cached_map_image_handles_repeated_512_image_quickly` |
| `palette.gd` | `extract_palette()` | 纯色、双色、k 上限 | `test_extract_palette_keeps_pure_and_two_color_images_exact`, `test_auto_k_quantization_limits_color_count` |
| `palette_registry.gd` | 内置、自定义颜色数组、JSON 解析 | 合法 JSON、非法字段、registry 状态不污染 | `test_custom_palette_can_be_resolved_from_hex_values`, `test_custom_palette_import_registers_palette_from_json`, `test_invalid_custom_palette_reports_reason_and_does_not_pollute_registry` |
| `grid_detector.gd` | `detect()` | 整数/小数 scale、offset、低置信照片、非方形警告 | `test_detects_integer_scale_and_offset`, `test_detects_fractional_scale_with_prior`, `test_smooth_photo_like_input_reports_low_confidence`, `test_non_square_scale_divergence_is_reported_in_meta` |
| `grid_detector.gd` | prior 搜索窗口 | `prior_scale`、`base_size ±30%`、512 图预算、24 样本矩阵 | `test_base_size_prior_limits_search_range_to_thirty_percent_window`, `test_512_detection_finishes_within_budget`, `test_24_sample_detection_matrix_meets_m1_acceptance_rate` |
| `resampler.gd` | `resample()` | mode/center/median/edge-aware、透明投票、噪声对照 | `test_nearest_scaled_images_resample_back_to_original`, `test_mode_resampling_survives_center_noise_better_than_center_strategy`, `test_transparent_pixels_vote_in_their_own_bucket`, `test_edge_aware_preserves_center_line_when_mode_would_choose_background`, `test_edge_aware_matches_mode_when_cell_contrast_is_below_threshold` |
| `quantizer.gd` | fixed palette + dither | Bayer 周期、strength=0、chromatic、FS serpentine | `test_fixed_palette_bayer4_outputs_two_color_periodic_pattern`, `test_strength_zero_matches_no_dither`, `test_chromatic_dither_keeps_palette_constraint`, `test_error_diffusion_uses_serpentine_scan_order` |
| `quantizer.gd` | auto_k strategy | median_cut 默认、非法回退、kmeans 质量、确定性、512 图预算 | `test_auto_k_quantization_limits_color_count`, `test_auto_k_invalid_strategy_falls_back_to_median_cut`, `test_auto_k_kmeans_error_is_not_worse_than_median_cut`, `test_auto_k_kmeans_is_deterministic`, `test_auto_k_kmeans_512_finishes_within_budget` |
| `pipeline.gd` | 步骤编排 | 默认端到端、手动网格、显式步骤、禁用步骤、StylePreset prior | `test_default_cleanup_pipeline_returns_true_pixel_asset`, `test_manual_cleanup_honors_given_grid`, `test_namespaced_params_can_disable_resample_step`, `test_explicit_step_order_runs_only_requested_algorithms`, `test_style_preset_base_size_flows_into_detect_params` |
| `pipeline.gd` | fixed_palette 自定义路径 | registry resolve 后清洗输出色值正确 | `test_fixed_palette_cleanup_uses_registered_custom_palette` |
| `pipeline.gd` | 真实样本烟测 | 三张真实 AI fixture 不崩溃、色数和尺寸达标 | `test_real_ai_fixture_samples_cleanup_smoke` |
| `pipeline.gd` | 批量清洗 UI 不冻结口径 | 50 张分帧 Apply、主线程峰值帧时间和总耗时断言 | `test_batch_cleanup_keeps_main_thread_frame_time_under_budget` |

## project format / persistence 覆盖

| 模块 | API / 行为 | 分支与边界 | 自动化测试 |
|---|---|---|---|
| `project_service.gd` | `.pxproj` roundtrip | manifest/canvas/assets 保存打开一致 | `test_project_save_open_roundtrip_matches_manifest_canvas_and_assets` |
| `project_service.gd` | 格式版本保护 | 未来版本拒开 | `test_project_open_rejects_future_format_version` |
| `project_service.gd` | 清洗 provenance | `provenance.cleanup` 保存打开后保留 | `test_cleanup_provenance_survives_project_roundtrip` |
| `project_service.gd` | 自定义调色板持久化 | `palettes/{id}.json` 写入 ZIP，重新打开后 registry 可 resolve | `test_custom_palette_survives_project_roundtrip` |

## 人工评审项

| 项 | 状态 | 证据 |
|---|---|---|
| 真实 AI 样本肉眼质量 | 已登记 | `pixel/tests/fixtures/real/REAL_AI_REVIEW.md` |
| 非技术用户导入 Lospec JSON 流程 | 待人工走查 | 走查脚本与签字区：`pixel/docs/manual-test-m1_1.md`（含调色板视觉区分检查项）；自动化已覆盖解析、持久化与清洗使用路径。 |

## 附录：core/pixel 公开 API 名称映射（反向完整性检查口径）

> `check_m1_1_coverage_matrix.sh` 会枚举 `core/pixel/*.gd` 的全部 `static func` 公开方法，
> 断言其名称出现在本文件中（上方行为矩阵或本表）。新增公开 API 而不更新本文件会让出口脚本失败。
> 确无独立测试价值的项使用 `EXEMPT(理由)` 显式豁免——禁止留空。

| 模块 | 公开 API | 覆盖来源 / 豁免 |
|---|---|---|
| `color_space.gd` | `byte_from_unit` | EXEMPT(纯算术换算，经 `color_to_rgba32` 路径间接覆盖) |
| `color_space.gd` | `color_to_hex` / `hex_to_color` | hex 往返行 → `test_custom_palette_can_be_resolved_from_hex_values` |
| `color_space.gd` | `color_to_rgba32` / `rgba32_to_color` | 经 `map_image` / `count_colors` 全路径间接覆盖 |
| `color_space.gd` | `color_to_oklab` / `oklab_to_color` / `oklab_distance` / `rgb_distance` | 距离边界行 → `test_rgb_and_oklab_nearest_color_boundaries` |
| `ditherer.gd` | `is_ordered` / `ordered_adjust` / `ordered_threshold` | Bayer 行 → `test_fixed_palette_bayer4_outputs_two_color_periodic_pattern` |
| `ditherer.gd` | `chromatic_adjust` | chromatic 行 → `test_chromatic_dither_keeps_palette_constraint` |
| `grid_detector.gd` | `detect` | 上方 grid_detector 两行 |
| `palette.gd` | `load_builtin` | 内置板行 → `test_builtin_palettes_load_with_contract_counts` |
| `palette.gd` | `extract_palette` / `map_image` / `from_json` | 上方 palette 行 |
| `palette.gd` | `from_color_values` | `test_custom_palette_can_be_resolved_from_hex_values` |
| `palette.gd` | `color_to_hex` / `hex_to_color` / `color_to_rgba32` / `rgba32_to_color` | color_space 同名转发，同上间接覆盖 |
| `palette_registry.gd` | `resolve` / `parse_palette_file` / `parse_palette_text` / `parse_palette_data` | 上方 registry 行 |
| `palette_registry.gd` | `import_custom_from_path` / `register_custom_palette` | `test_custom_palette_import_registers_palette_from_json` |
| `palette_registry.gd` | `load_builtin` / `get_builtin_ids` / `get_custom_ids` / `get_palette_name` / `is_custom_palette` | 经导入/下拉刷新路径间接覆盖（`test_custom_palette_import_registers_palette_from_json`） |
| `palette_registry.gd` | `load_from_path` | `test_custom_palette_survives_project_roundtrip` 间接 |
| `palette_registry.gd` | `unregister_custom_palette` | EXEMPT(UI 删除入口，登记于人工走查清单 manual-test-m1_1.md，M2 前补自动化) |
| `palette_registry.gd` | `clear_custom_palettes` | `test_invalid_custom_palette_reports_reason_and_does_not_pollute_registry` 前置清理使用 |
| `palette_registry.gd` | `get_custom_manifest_entries` / `export_custom_zip_entries` / `load_custom_palettes_from_project` | 持久化行 → `test_custom_palette_survives_project_roundtrip` |
| `pipeline.gd` | `apply` / `default_params` / `normalize_params` | 上方 pipeline 行 |
| `pipeline.gd` | `get_default_step_ids` | `test_explicit_step_order_runs_only_requested_algorithms` 间接 |
| `quantizer.gd` | `quantize` / `quantize_to_palette` | 上方 quantizer 行 |
| `quantizer.gd` | `count_colors` | `test_auto_k_quantization_limits_color_count` 断言路径使用 |
| `quantizer.gd` | `normalize_auto_k_strategy` | `test_auto_k_invalid_strategy_falls_back_to_median_cut` |
| `resampler.gd` | `resample` | 上方 resampler 行 |
