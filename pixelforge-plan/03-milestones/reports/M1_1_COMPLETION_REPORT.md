# M1.1 Completion Report

完成日期：2026-06-13  
Godot 版本：4.6.3.stable.official.7d41c59c4

## 1. 实现功能

### 1.1 auto_k 量化策略扩展

- `PFQuantizer` 新增 `auto_k_strategy`：
  - `median_cut`：默认值，保持 M1 行为和旧参数输出不变。
  - `kmeans`：以 median cut 输出作为初始中心，在 OKLab 空间进行确定性聚类。
- kmeans 约束：
  - 迭代上限 16 次。
  - 中心位移 `< 0.5 / 255` 时提前收敛。
  - 源图超过 65536 像素时按固定 stride 均匀采样，中心确定后仍对完整图映射。
  - 禁止随机初始化，连续运行结果逐像素一致。
- `PFCleanupPipeline.normalize_params()` 已同步 `auto_k_strategy` 默认值和非法值回退。

最终代码入口：

| 文件 | 入口 |
|---|---|
| `core/pixel/quantizer.gd` | `normalize_auto_k_strategy()` |
| `core/pixel/quantizer.gd` | `_extract_auto_k_palette()` |
| `core/pixel/quantizer.gd` | `_extract_palette_kmeans()` |
| `core/pixel/quantizer.gd` | `_collect_kmeans_samples()` |
| `core/pixel/pipeline.gd` | `default_params()` / `normalize_params()` / `_step_quantize()` |

### 1.2 自定义调色板 UI 路径与持久化

- `PFPaletteRegistry` 新增自定义调色板运行时注册表。
- 支持从 JSON 文件解析并返回明确错误：
  - JSON 语法错误包含行号。
  - 缺字段、`colors` 非数组、色值越界或非法 hex 会返回具体字段路径，如 `colors[1]`。
- `PFCleanupInspector` 新增：
  - 调色板下拉末尾的 `Import custom palette...`。
  - `*.json` 文件选择器。
  - 导入失败错误弹窗。
  - 选中调色板色条预览。
  - 仅自定义调色板可用的删除按钮。
  - `Auto K Strategy` 下拉框，默认 `Median Cut`，可选 `K-means`。
  - StylePreset `base_size` 先验提示。
- `ProjectService` 保存 `.pxproj` 时写入：
  - `manifest.custom_palettes`
  - `palettes/{palette_id}.json`
- 打开项目时会先恢复自定义调色板 registry，再继续加载资产和画布。

最终代码入口：

| 文件 | 入口 |
|---|---|
| `core/pixel/palette_registry.gd` | `parse_palette_file()` / `parse_palette_text()` / `parse_palette_data()` |
| `core/pixel/palette_registry.gd` | `import_custom_from_path()` / `register_custom_palette()` / `unregister_custom_palette()` |
| `core/pixel/palette_registry.gd` | `get_custom_manifest_entries()` / `export_custom_zip_entries()` / `load_custom_palettes_from_project()` |
| `ui/inspector/cleanup_inspector.gd` | `refresh_palette_options()` / `set_style_preset()` |
| `ui/inspector/cleanup_inspector.gd` | `_on_palette_file_selected()` / `_delete_selected_custom_palette()` / `_update_palette_preview()` |
| `services/project_service.gd` | `open_project()` / `_save_to_path()` / `_update_manifest_before_save()` / `mark_dirty()` |
| `ui/shell/main.gd` | `_sync_cleanup_inspector_with_project()` / `_on_custom_palettes_changed()` |

### 1.3 core 覆盖率可验证统计

- 调研当前 vendored GUT 后，未发现可直接接入 Godot 4.6.3 headless 门控的 coverage 输出。
- 未伪造行覆盖率数字，改用 public API / 分支覆盖矩阵：
  - `../pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md`
- 新增脚本抽查矩阵引用的 `test_*` 名称全部真实存在：
  - `scripts/check_m1_1_coverage_matrix.sh`
- 新增 M1.1 出口脚本：
  - `scripts/verify_m1_1.sh`

### 1.4 顺延加固项

- `base_size` 先验：
  - M1 已实现参数流入。
  - M1.1 补充 `base_size ±30%` 搜索窗口断言。
- 批量帧时间：
  - 新增 50 张 fixture 分帧 Apply 性能断言。
  - 断言主线程峰值处理时间 `< 200ms`，总耗时 `< 120s`，对应自动化环境 2 倍裕量。

## 2. 修改文件清单

### 核心代码

- `core/pixel/quantizer.gd`
- `core/pixel/pipeline.gd`
- `core/pixel/palette_registry.gd`
- `services/project_service.gd`
- `ui/inspector/cleanup_inspector.gd`
- `ui/shell/main.gd`

### 测试

- `tests/unit/test_pixel_quantizer.gd`
- `tests/unit/test_pixel_palette.gd`
- `tests/unit/test_pixel_grid_detector.gd`
- `tests/integration/test_cleanup_pipeline.gd`
- `tests/integration/test_project_roundtrip.gd`
- `tests/integration/test_cleanup_batch_performance.gd`
- `tests/integration/test_cleanup_batch_performance.gd.uid`

### 脚本

- `scripts/check_m1_1_coverage_matrix.sh`
- `scripts/verify_m1_1.sh`

### 文档与契约

- `CHANGELOG.md`
- `M1_1_COMPLETION_REPORT.md`
- `../pixelforge-plan/02-contracts/STYLE-PRESETS.md`
- `../pixelforge-plan/02-contracts/PROJECT-FORMAT.md`
- `../pixelforge-plan/04-research/RESEARCH-NOTES.md`
- `../pixelforge-plan/05-quality/QUALITY.md`
- `../pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md`

## 3. 新增/更新测试覆盖

| 验收点 | 测试 |
|---|---|
| kmeans 质量不劣于 median cut | `test_auto_k_kmeans_error_is_not_worse_than_median_cut` |
| 非法 `auto_k_strategy` 回退 median cut | `test_auto_k_invalid_strategy_falls_back_to_median_cut` |
| kmeans 确定性 | `test_auto_k_kmeans_is_deterministic` |
| 512×512 k=32 kmeans 性能 | `test_auto_k_kmeans_512_finishes_within_budget` |
| 合法自定义调色板 JSON 注册 | `test_custom_palette_import_registers_palette_from_json` |
| 非法 JSON 明确报错且 registry 无污染 | `test_invalid_custom_palette_reports_reason_and_does_not_pollute_registry` |
| fixed_palette 清洗使用自定义调色板 | `test_fixed_palette_cleanup_uses_registered_custom_palette` |
| 自定义调色板保存/打开后仍可 resolve | `test_custom_palette_survives_project_roundtrip` |
| base_size 搜索窗口 | `test_base_size_prior_limits_search_range_to_thirty_percent_window` |
| 50 张批量清洗帧时间 | `test_batch_cleanup_keeps_main_thread_frame_time_under_budget` |
| 覆盖矩阵引用测试真实存在 | `scripts/check_m1_1_coverage_matrix.sh` |

## 4. 验证结果

已通过：

```bash
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_m1_1_coverage_matrix.sh
./scripts/verify_m1_1.sh
```

关键结果：

- lint：`Success: no problems found`
- GUT：`72 tests / 678 asserts` 全部通过
- orphan：`1 Orphans`，保持 M1 `verify_m1.sh` 固定断言口径
- 覆盖矩阵：`Coverage matrix references 41 existing tests.`
- M1 性能采样 p95：
  - `palette_map_p95_ms`: 156.92
  - `grid_detect_p95_ms`: 76.94
  - `cleanup_pipeline_p95_ms`: 221.95
- export templates：本机未安装 Godot 4.6.3 export templates，脚本按 M1 口径提示并验证 headless 启动，未阻断门控。

## 5. 说明与风险登记

- GUT coverage：当前 vendored GUT 9.6.0 未发现可用 coverage 出口，已采用覆盖矩阵替代并写入 `QUALITY.md` 与 `RESEARCH-NOTES.md`。
- 批量帧时间自动化：曾尝试用 `WorkerThreadPool` 跑 Image 清洗压测，但 Godot 4.6.3 headless 下图像操作在线程中不稳定，测试改为分帧 Apply 口径。产品现有 TaskQueue 路径未在本次改为分帧执行，建议后续若做大批量生产任务，再专项验证 Image 在线程内的安全边界。
- 人工评审：自定义调色板导入的自动化覆盖了 JSON 解析、错误、registry、清洗使用和项目持久化；图形界面的“非技术用户完整走查”仍建议在下一次人工验收中执行。

## 6. 变更附录（git diff 模式）

> M1.1 改进期决定：完成报告不再内联全量代码（原 §6 约 3900 行）。代码以仓库为准，
> 报告只保留 `git diff --stat` 摘要与新增文件清单；逐行内容用 `git diff` / 文件历史审阅。
> 本次改进的逐文件 diff 见《M1_1_IMPROVEMENT_REPORT.md》§4。

### 6.1 已跟踪文件变更摘要（git diff --stat，基线 commit `3860717` M0 finish）

```
pixel/CHANGELOG.md                                 |   5 +
 pixel/README.md                                    |   6 +-
 pixel/docs/manual-test-m0.md                       |   2 +-
 pixel/project.godot                                |   5 +-
 pixel/services/project_service.gd                  |  22 +-
 pixel/tests/integration/test_project_roundtrip.gd  |  72 ++++
 pixel/tests/smoke/test_infinite_canvas.gd          |  48 ++-
 pixel/ui/canvas/infinite_canvas.gd                 | 129 +++++++
 pixel/ui/shell/main.gd                             | 394 ++++++++++++++++++++-
 pixel/ui/shell/strings.gd                          |  39 ++
 pixelforge-plan/02-contracts/PROJECT-FORMAT.md     |  17 +-
 pixelforge-plan/02-contracts/STYLE-PRESETS.md      |   4 +-
 .../03-milestones/M2-matting-slicing.md            |  16 +
 pixelforge-plan/04-research/RESEARCH-NOTES.md      |  14 +
 pixelforge-plan/05-quality/QUALITY.md              |   4 +
 pixelforge-plan/README.md                          |   1 +
 16 files changed, 752 insertions(+), 26 deletions(-)
```

### 6.2 M1/M1.1 新增文件（基线后未跟踪，.uid 略）

| 文件 | 行数 |
|---|---|
| `pixel/assets/palettes/aap64.json` | 72 |
| `pixel/assets/palettes/bw_2.json` | 10 |
| `pixel/assets/palettes/db16.json` | 24 |
| `pixel/assets/palettes/db32.json` | 40 |
| `pixel/assets/palettes/endesga32.json` | 40 |
| `pixel/assets/palettes/endesga64.json` | 72 |
| `pixel/assets/palettes/gb_4.json` | 12 |
| `pixel/assets/palettes/nes_full.json` | 63 |
| `pixel/assets/palettes/pico8.json` | 24 |
| `pixel/assets/presets/` | (目录) |
| `pixel/core/pixel/color_space.gd` | 118 |
| `pixel/core/pixel/ditherer.gd` | 96 |
| `pixel/core/pixel/grid_detector.gd` | 270 |
| `pixel/core/pixel/image_pipeline_step.gd` | 33 |
| `pixel/core/pixel/palette.gd` | 312 |
| `pixel/core/pixel/palette_registry.gd` | 330 |
| `pixel/core/pixel/pipeline.gd` | 352 |
| `pixel/core/pixel/quantizer.gd` | 341 |
| `pixel/core/pixel/resampler.gd` | 186 |
| `pixel/docs/manual-test-m1_1.md` | 37 |
| `pixel/scripts/check_m1_1_coverage_matrix.sh` | 58 |
| `pixel/scripts/measure_m1.gd` | 72 |
| `pixel/scripts/verify_m1.sh` | 32 |
| `pixel/scripts/verify_m1_1.sh` | 45 |
| `pixel/tests/fixtures/generators/` | (目录) |
| `pixel/tests/fixtures/real/` | (目录) |
| `pixel/tests/integration/test_cleanup_batch_performance.gd` | 65 |
| `pixel/tests/integration/test_cleanup_pipeline.gd` | 171 |
| `pixel/tests/unit/test_pixel_grid_detector.gd` | 161 |
| `pixel/tests/unit/test_pixel_palette.gd` | 131 |
| `pixel/tests/unit/test_pixel_quantizer.gd` | 255 |
| `pixel/tests/unit/test_pixel_resampler.gd` | 85 |
| `pixel/ui/canvas/cleanup_grid_overlay.gd` | 128 |
| `pixel/ui/inspector/cleanup_inspector.gd` | 548 |
| `pixelforge-plan/03-milestones/M1.1-cleanup-enhancements.md` | 98 |
| `pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md` | 71 |
| `pixelforge-plan/06-algorithm-refs/` | (目录) |

### 6.3 审阅方式

```bash
git diff 3860717 -- pixel/ pixelforge-plan/      # 已跟踪文件逐行 diff
git status --porcelain | grep '^??'              # 新增文件清单
```

> 工程提醒：M1 与 M1.1 两个里程碑的全部变更目前仍未提交（最后提交为 M0 finish）。
> 建议尽快按里程碑分批 commit，否则"diff 模式报告"的基线会持续膨胀。
