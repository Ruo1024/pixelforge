# M1.1 改进报告（M1_1_IMPROVEMENT_REPORT）

改进日期：2026-06-13
基线：M1.1 完成报告（2026-06-13）+ M1.1 完成度外部评审意见
Godot 版本：4.6.3.stable.official.7d41c59c4

---

## 1. 改进背景与决策过程

M1.1 关门后进行了一次外部评审，结论为"完成度高（约 85~90 分）但存在若干缺口"。
本次改进按评审意见逐项处置，处置原则：

1. **修复确定的缺陷**（mac 缩放回归、空簇死色）。
2. **加固验证体系中"形同空转"的部分**（压测负载、单向矩阵检查、性能只采样不门控）。
3. **成本过高或重要性不足的项显式延后**，登记在 §5，不静默丢弃。

### 1.1 评审意见 → 处置决定对照表

| # | 评审意见 | 处置 | 理由 |
|---|---|---|---|
| 1 | kmeans 空簇中心被跳过，产生死色/重复色 | ✅ 本次修复 | 算法正确性缺陷，修复成本低且可保持确定性 |
| 2 | 收敛阈值 0.5/255 用在 OKLab 空间量纲含混 | ✅ 注释说明（不改值） | 改值会破坏"默认路径逐像素一致"硬线；先把语义写清，调值走契约变更流程 |
| 3 | 性能测试只用放宽 2 倍后的上限，真实回归不报警 | ✅ 本次修复 | 加实测值日志 + `PF_PERF_STRICT=1` 严格档，零额外 CI 成本 |
| 4 | 批量压测 8×8 基底负载过轻，断言空转 | ✅ 本次修复 | 改 32×32 基底放大 4 倍（128×128 输入），贴近真实清洗负载 |
| 5 | inspector 硬编码英文裸字符串，违反 Strings 约定 | ✅ 本次修复 | 顺手项；i18n 债务越晚还越贵 |
| 6 | 覆盖矩阵只防"引用不存在的测试"，不防"漏列新 API" | ✅ 本次修复 | 加反向 API 完整性检查 + EXEMPT 豁免口径 |
| 7 | 人工走查停留在"建议下次执行"，无 checklist 载体 | ✅ 本次修复 | 新建 `docs/manual-test-m1_1.md` 含签字区，矩阵指向它 |
| 8 | p95 性能只采样不门控 | ✅ 本次修复 | `verify_m1_1.sh` 加基线 ×1.3 回归带 |
| 9 | WorkerThreadPool/Image 线程安全发现只留在报告风险区 | ✅ 本次修复 | 升格写入 RESEARCH-NOTES 附录 B，M2+ 架构决策可引用 |
| 10 | 完成报告 3900 行全量代码附录难以审阅 | ✅ 本次修复 | 报告 §6 改为 git diff --stat 模式（4160 行 → 240 行） |
| 11 | mac 窗口/检查器缩放过小复发 | ✅ 初步修复 | 见 §3 专节；目标"mac 上暂时正确显示浏览" |
| 12 | 自研缩放体系是约定式负担，应评估官方 content_scale_factor 路线 | ✅ 立决策卡入 M2 | 经同意，决策卡已写入 `M2-matting-slicing.md` |
| 13 | "M1 评估报告 17 项闭环表"缺交付物 | ⏸ 延后（§5） | 需回溯 M1 评估原始清单逐项核对，半天级工作量，不阻塞当前质量 |
| 14 | M1/M1.1 全部变更未 commit | ⏸ 延后提醒（§5） | 提交策略（单 commit / 按里程碑拆分）应由项目负责人定，本次只在报告中强提醒 |
| 15 | 矩阵需"人工评审签字" | ⏸ 部分处置 | 签字区已随走查清单建立（见 #7），实际签字待人工执行 |

### 1.2 改进流程

1. **备份快照**：修改前复制全部 16 个目标文件到隔离目录，结束后逐文件 `diff -u` 生成 §4 的精确变更记录（项目当前有大量未提交变更，不能依赖 git 区分本次改动）。
2. **按依赖序实施**：core 算法（quantizer）→ 测试（quantizer 单测、批量压测）→ UI（inspector 缩放 + 字符串、main.gd）→ 脚本（矩阵检查、verify）→ 文档（矩阵附录、RESEARCH-NOTES、走查清单、M2 决策卡）→ 报告改造。
3. **静态验证**：gdformat --check 全仓 50 文件通过；gdlint 全仓 Success；bare-print 检查通过；两个 bash 脚本 `bash -n` 语法通过且矩阵检查脚本实际运行通过（41 个测试名 + 全部公开 API 在位）。
4. **登记无法在本环境验证的项**：见 §6。

---

## 2. 逐项改进说明（思路与实现）

### 2.1 kmeans 空簇重播种（quantizer.gd）

**问题**：原实现中权重为 0 的簇直接 `continue`，中心停留原地。该中心若再无样本靠近，
最终调色板会输出与初始 median cut 中心重复或无样本支持的"死色"，浪费 k 预算——
恰恰是 kmeans 主打的"k 较大时分布更均匀"场景受损最重。

**方案选择**：候选有 a) 丢弃空簇（输出 < k 色，违反"不劣于基线"语义）、b) 随机重播种
（违反确定性硬线）、c) **重播种到"距全部非空中心最近距离最大"的样本**（farthest-point
口径，确定性、且把预算花在覆盖最差的颜色上）。选 c。

**确定性保障**：样本列表本身按 RGBA32 升序构建（M1.1 既有逻辑），遍历取首个最大值，
并列时结果稳定；重播种产生的位移并入 max_shift，防止"重播种当轮即假收敛"。

**影响面**：仅 `auto_k_strategy=kmeans` 路径；median_cut 默认路径零变化（零回归硬线保持）。

### 2.2 收敛阈值量纲注释（quantizer.gd）

不改值，只在常量处写明：`0.5/255 ≈ 0.002` 在 OKLab 中略低于一般可感知差异（JND
约 0.01–0.02），语义是"宁可多迭代也不提前停"；调值须先走契约变更。

### 2.3 性能测试加固（两个测试文件）

- 实测毫秒值通过 `gut.p()` 输出，回归趋势可从 CI 日志追踪。
- `PF_PERF_STRICT=1` 环境变量启用计划原文的严格预算（kmeans 1.5s；批量峰值 100ms/总 60s），
  本地复核用；CI 维持放宽 2 倍口径不引入抖动失败。
- 批量压测基底 8×8 → 32×32（输入 128×128），50 张总像素量提升 16 倍，断言开始有真实约束力。
- 顺带消除 `"scale": 4.0` 与放大倍数的魔数重复（统一 `SPRITE_SCALE`）。

### 2.4 inspector 字符串迁入 Strings（strings.gd + cleanup_inspector.gd）

30 处硬编码英文字符串全部迁移为 `PFStrings` 常量（含格式串），与 M0 建立的
"v1.0 前英文集中、后续 i18n 只换一处"约定对齐。纯机械替换，无行为变化。

### 2.5 覆盖矩阵反向完整性检查（check 脚本 + 矩阵附录）

- 矩阵新增附录表：core/pixel 全部 49 个公开 `static func` 逐项映射到覆盖来源，
  确无独立测试价值的 2 项（`byte_from_unit`、`unregister_custom_palette` 的 UI 路径）
  使用 `EXEMPT(理由)` 显式豁免——禁止留空。
- 脚本新增反向检查：枚举 `core/pixel/*.gd` 公开方法名，缺席矩阵即门控失败。
  M2 新增 API 而不更新矩阵将无法通过出口脚本，矩阵不再会无声过时。
- 已实际运行通过：`41 existing tests` + `All core/pixel public APIs are present`。

### 2.6 p95 性能回归带（verify_m1_1.sh）

以 M1.1 完成报告实测值为基线，cap = 基线 × 1.3（palette_map 204ms / grid_detect
100ms / cleanup_pipeline 289ms）。解析 `measure_m1.gd` 输出，缺指标或超带即 exit 1。
基线与日期、机器写入脚本注释，后续换基线有据可查。

### 2.7 知识沉淀（RESEARCH-NOTES 附录 B + 走查清单 + manual-test-m0 修订）

- WorkerThreadPool/Image headless 不稳定的发现从完成报告风险区升格至
  RESEARCH-NOTES 附录 B，并写明对 M2+ 批量任务架构的约束与候选方案。
- 新建 `docs/manual-test-m1_1.md`：调色板全流程（含计划要求的"视觉区分"检查项）、
  mac 显示走查、Auto K Strategy 走查，文末签字区作为矩阵人工评审项的闭环证据载体。
- `manual-test-m0.md` 第 6 条补充"测试后必须还原 0.0"警告——该指引正是 mac 缩放
  复发的最可能根因（见 §3）。

---

## 3. mac 窗口缩放问题：根因分析与初步修复

### 3.1 三层根因

| 层 | 定性 | 说明 |
|---|---|---|
| 残留配置 | 最可能触发器 | `manual-test-m0.md` 曾指导把 `ui/interface_scale` 写成 1.0 测试；该值残留 `user://settings.cfg` 后**永久旁路**自动检测（`_ensure_defaults` 只补缺省不重置）。Windows 上 1.0 恰好正确，所以只有 mac 复发 |
| M1.1 回归 | 确定缺陷 | `cleanup_inspector.gd`（M1.x 新增）全部硬编码像素值，`add_theme_font_size_override` 还会覆盖继承主题，即使主窗口缩放正确，检查器面板在 2x 屏也是一半尺寸 |
| 结构弱点 | 长期债务 | 自研"约定式缩放"无法被 lint/测试守护，每个新 UI 组件都可能忘记接线 → 已立 M2 决策卡评估迁移官方 content_scale_factor 路线 |

### 3.2 本次落地的初步修复（目标：mac 暂时正确显示浏览）

1. **inspector 接入缩放体系**：新增 `ui_scale` 属性（shell 在 `add_child` 前注入），
   全部 8 类尺寸/字号经 `_scaled_int()`。2x 屏下面板 600px 宽、字号 26~32，与主界面一致。
2. **残留配置一次性迁移**：启动时若 `OS == macOS` 且 `configured_scale == 1.0` 且
   自动检测值更大，判定为 M0 测试残留，重置回 0.0（自动）并写警告日志。
   **边界**：显式设置 1.5/2.0 的用户不受影响；非 mac 平台不受影响；外接 1x 显示器上
   auto==1.0 不触发迁移（用户在 1x 屏显式要 1.0 被尊重）。
3. **决策链日志**：`Interface scale resolved | source/resolved/configured/
   reported_screen_scale/usable_rect/os`——下次再出现缩放问题，一行日志即可定位是
   配置旁路、检测失效还是阈值兜底失败。
4. **Cmd 快捷键**：`ctrl_pressed` → `is_command_or_control_pressed()`，mac 映射 Cmd，
   其余平台 Ctrl，Windows 行为不变。

### 3.3 已知未解决（归入 M2 决策卡范围）

- 跨屏拖动不重算缩放（启动时一次性决策）。
- `compute_auto_interface_scale` 的 4800/2800 兜底阈值依赖"usable_rect 为物理像素"
  假设，`screen_get_scale` 失效时 MacBook 内置屏仍可能落回 1.0——决策链日志已能
  暴露这种情况，根治依赖 content_scale_factor 迁移评估结论。
- FileDialog 等原生弹窗的字号继承主题，但布局尺寸未逐项核查。

---

## 4. 逐文件精确 diff

> 由备份快照 `diff -u` 生成（gdformat 格式化后口径）。项目存在大量 M1/M1.1 未提交
> 变更，故不使用 `git diff`（无法区分本次改动）。

### `pixel/core/pixel/quantizer.gd`

```diff
--- a/pixel/core/pixel/quantizer.gd
+++ b/pixel/core/pixel/quantizer.gd
@@ -19,6 +19,10 @@
 const ALPHA_LIMIT := 128
 const KMEANS_SAMPLE_LIMIT := 65536
 const KMEANS_MAX_ITERATIONS := 16
+# 收敛阈值沿用 M1.1 计划原文的 0.5/255（8bit RGB 半个色阶的保守口径）。
+# 注意它作用在 OKLab 欧氏距离上：OKLab 的 L 范围约 0..1、a/b 约 ±0.4，
+# 0.5/255 ≈ 0.002 在 OKLab 中略低于一般可感知差异（JND ~0.01–0.02），
+# 即"宁可多迭代也不提前停"。如需调整请先更新 M1.1 契约说明再改值。
 const KMEANS_CONVERGENCE_DISTANCE := 0.5 / 255.0
 
 
@@ -130,14 +134,22 @@
 			weights[cluster] = float(weights[cluster]) + weight
 
 		var max_shift := 0.0
+		var empty_clusters := []
 		for index in range(centers.size()):
 			if float(weights[index]) <= 0.0:
+				empty_clusters.append(index)
 				continue
 			var old_center: Vector3 = centers[index]
 			var new_center := Vector3(sums[index]) / float(weights[index])
 			centers[index] = new_center
 			max_shift = maxf(max_shift, old_center.distance_to(new_center))
 
+		# 空簇重播种：丢弃的中心会造成调色板死色/重复色。把每个空簇移动到
+		# "距当前所有非空中心最近距离最大"的样本上（即覆盖最差的颜色），
+		# 样本按 RGBA32 升序枚举、并列取首个，保证逐像素确定性。
+		if not empty_clusters.is_empty():
+			max_shift = maxf(max_shift, _reseed_empty_clusters(centers, empty_clusters, samples))
+
 		if max_shift < KMEANS_CONVERGENCE_DISTANCE:
 			break
 
@@ -182,6 +194,31 @@
 	return samples
 
 
+static func _reseed_empty_clusters(centers: Array, empty_clusters: Array, samples: Array) -> float:
+	var reseed_shift := 0.0
+	for empty_index in empty_clusters:
+		var best_sample_lab := Vector3.ZERO
+		var best_distance := -1.0
+		for sample in samples:
+			var lab: Vector3 = sample["lab"]
+			var nearest := INF
+			for center_index in range(centers.size()):
+				if center_index == empty_index:
+					continue
+				nearest = minf(
+					nearest, ColorSpace.oklab_distance(lab, Vector3(centers[center_index]))
+				)
+			if nearest > best_distance:
+				best_distance = nearest
+				best_sample_lab = lab
+		if best_distance < 0.0:
+			continue
+		var old_center: Vector3 = centers[empty_index]
+		centers[empty_index] = best_sample_lab
+		reseed_shift = maxf(reseed_shift, old_center.distance_to(best_sample_lab))
+	return reseed_shift
+
+
 static func _nearest_lab_index(sample: Vector3, centers: Array) -> int:
 	var best_index := 0
 	var best_distance := INF
```

### `pixel/tests/unit/test_pixel_quantizer.gd`

```diff
--- a/pixel/tests/unit/test_pixel_quantizer.gd
+++ b/pixel/tests/unit/test_pixel_quantizer.gd
@@ -120,8 +120,11 @@
 	)
 	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
 
+	# 计划口径 1.5s，自动化环境放宽 2 倍；本地可 PF_PERF_STRICT=1 启用严格预算。
+	var budget_ms := 1500.0 if OS.get_environment("PF_PERF_STRICT") == "1" else 3000.0
+	gut.p("kmeans 512x512 k=32 elapsed_ms=%.2f budget_ms=%.0f" % [elapsed_ms, budget_ms])
 	assert_lte(int(result["color_count"]), 32)
-	assert_lt(elapsed_ms, 3000.0)
+	assert_lt(elapsed_ms, budget_ms)
 
 
 func test_strength_zero_matches_no_dither() -> void:
```

### `pixel/tests/integration/test_cleanup_batch_performance.gd`

```diff
--- a/pixel/tests/integration/test_cleanup_batch_performance.gd
+++ b/pixel/tests/integration/test_cleanup_batch_performance.gd
@@ -5,19 +5,32 @@
 const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")
 
 const BATCH_SIZE := 50
-const PEAK_FRAME_BUDGET_MS := 200.0
-const TOTAL_BUDGET_MS := 120000
+# 计划口径：峰值帧 < 100ms、总耗时 < 60s；自动化环境放宽 2 倍。
+# 本地复核可 PF_PERF_STRICT=1 启用严格预算。
+const PEAK_FRAME_BUDGET_STRICT_MS := 100.0
+const PEAK_FRAME_BUDGET_RELAXED_MS := 200.0
+const TOTAL_BUDGET_STRICT_MS := 60000
+const TOTAL_BUDGET_RELAXED_MS := 120000
+# M1.1 复盘：8×8 基底放大 4 倍（32×32 输入）对预算毫无压力，断言形同空转。
+# 改为 32×32 基底放大 4 倍（128×128 输入），更接近真实 AI 生成图的清洗负载。
+const SPRITE_BASE_SIZE := Vector2i(32, 32)
+const SPRITE_SCALE := 4
 
 
 func test_batch_cleanup_keeps_main_thread_frame_time_under_budget() -> void:
+	var strict := OS.get_environment("PF_PERF_STRICT") == "1"
+	var peak_budget_ms := PEAK_FRAME_BUDGET_STRICT_MS if strict else PEAK_FRAME_BUDGET_RELAXED_MS
+	var total_budget_ms := TOTAL_BUDGET_STRICT_MS if strict else TOTAL_BUDGET_RELAXED_MS
 	var encoded_images := []
 	for index in range(BATCH_SIZE):
-		var original := FixtureGenerator.make_base_sprite(Vector2i(8, 8), index % 3)
-		encoded_images.append(FixtureGenerator.scale_nearest(original, 4).save_png_to_buffer())
+		var original := FixtureGenerator.make_base_sprite(SPRITE_BASE_SIZE, index % 3)
+		encoded_images.append(
+			FixtureGenerator.scale_nearest(original, SPRITE_SCALE).save_png_to_buffer()
+		)
 
 	var params := {
 		"detect": Pipeline.DETECT_MANUAL,
-		"scale": 4.0,
+		"scale": float(SPRITE_SCALE),
 		"quantize": Quantizer.MODE_AUTO_K,
 		"k": 8,
 	}
@@ -41,6 +54,12 @@
 		peak_process_ms = maxf(peak_process_ms, maxf(item_ms, process_ms))
 
 	var elapsed_ms := Time.get_ticks_msec() - started
+	gut.p(
+		(
+			"batch cleanup peak_ms=%.2f total_ms=%d peak_budget_ms=%.0f total_budget_ms=%d"
+			% [peak_process_ms, elapsed_ms, peak_budget_ms, total_budget_ms]
+		)
+	)
 	assert_eq(count, BATCH_SIZE)
-	assert_lt(peak_process_ms, PEAK_FRAME_BUDGET_MS)
-	assert_lt(elapsed_ms, TOTAL_BUDGET_MS)
+	assert_lt(peak_process_ms, peak_budget_ms)
+	assert_lt(elapsed_ms, total_budget_ms)
```

### `pixel/ui/inspector/cleanup_inspector.gd`

```diff
--- a/pixel/ui/inspector/cleanup_inspector.gd
+++ b/pixel/ui/inspector/cleanup_inspector.gd
@@ -15,6 +15,7 @@
 const Quantizer := preload("res://core/pixel/quantizer.gd")
 const Ditherer := preload("res://core/pixel/ditherer.gd")
 const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
+const Strings := preload("res://ui/shell/strings.gd")
 
 const PANEL_WIDTH := 300
 const CONTROL_HEIGHT := 30
@@ -45,6 +46,14 @@
 const IMPORT_PALETTE_ID := "__import_custom_palette__"
 const PALETTE_PREVIEW_WIDTH := 192
 const PALETTE_PREVIEW_HEIGHT := 18
+const TITLE_FONT_SIZE := 16
+const LABEL_FONT_SIZE := 13
+const PRIOR_FONT_SIZE := 12
+
+# 由 shell 在 add_child 之前注入（见 main.gd::_build_ui）。
+# M1.1 复盘：本面板曾全部使用硬编码像素值，绕过了 M0 建立的界面缩放体系，
+# 在 macOS Retina（2x）上呈现为一半物理尺寸。所有尺寸/字号必须经 _scaled_int()。
+var ui_scale := 1.0
 
 var _selection_label: Label = null
 var _auto_detect_check: CheckBox = null
@@ -78,7 +87,7 @@
 
 
 func _ready() -> void:
-	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
+	custom_minimum_size = Vector2(_scaled_int(PANEL_WIDTH), 0)
 	_build_ui()
 	set_selection_count(0)
 
@@ -120,7 +129,7 @@
 func set_selection_count(count: int) -> void:
 	if _selection_label == null:
 		return
-	_selection_label.text = "%d selected" % count
+	_selection_label.text = Strings.CLEANUP_SELECTED_FORMAT % count
 	_apply_button.disabled = count <= 0
 	_schedule_preview()
 	_emit_manual_grid_changed()
@@ -148,7 +157,7 @@
 
 	var base_size := int(style_preset.get("base_size", 0))
 	_style_prior_label.visible = base_size > 0
-	_style_prior_label.text = "Preset prior: %dpx" % base_size
+	_style_prior_label.text = Strings.CLEANUP_PRESET_PRIOR_FORMAT % base_size
 
 	var quantize: Dictionary = get_params().get(Pipeline.STEP_QUANTIZE, {})
 	var palette_data: Variant = style_preset.get("palette", {})
@@ -185,11 +194,14 @@
 
 	for palette_id in PaletteRegistry.get_custom_ids():
 		_palette_options.add_item(
-			"Custom: %s" % PaletteRegistry.get_palette_name(String(palette_id))
+			(
+				Strings.CLEANUP_CUSTOM_PALETTE_PREFIX
+				% PaletteRegistry.get_palette_name(String(palette_id))
+			)
 		)
 		_palette_ids.append(String(palette_id))
 
-	_palette_options.add_item("Import custom palette...")
+	_palette_options.add_item(Strings.CLEANUP_IMPORT_PALETTE_ITEM)
 	_palette_ids.append(IMPORT_PALETTE_ID)
 
 	var selected_index := _palette_ids.find(selected_id)
@@ -206,10 +218,10 @@
 	var detect: Dictionary = report.get("detect", {})
 	var quantize: Dictionary = report.get("quantize", {})
 	var warning := (
-		"\nNon-square grid warning" if bool(detect.get("non_square_warning", false)) else ""
+		Strings.CLEANUP_NON_SQUARE_WARNING if bool(detect.get("non_square_warning", false)) else ""
 	)
 	_report_label.text = (
-		"Scale %.2f | Confidence %.2f\nColors %d | Output %s%s"
+		Strings.CLEANUP_REPORT_FORMAT
 		% [
 			float(detect.get("scale", 0.0)),
 			float(detect.get("confidence", 0.0)),
@@ -222,98 +234,102 @@
 
 func _build_ui() -> void:
 	var root := VBoxContainer.new()
-	root.add_theme_constant_override("separation", 8)
+	root.add_theme_constant_override("separation", _scaled_int(8))
 	add_child(root)
 
 	var title := Label.new()
-	title.text = "Pixel Cleanup"
-	title.add_theme_font_size_override("font_size", 16)
+	title.text = Strings.CLEANUP_TITLE
+	title.add_theme_font_size_override("font_size", _scaled_int(TITLE_FONT_SIZE))
 	root.add_child(title)
 
 	_selection_label = Label.new()
 	root.add_child(_selection_label)
 
-	_auto_detect_check = _make_check("Auto detect grid", true)
+	_auto_detect_check = _make_check(Strings.CLEANUP_AUTO_DETECT, true)
 	root.add_child(_auto_detect_check)
 
 	_style_prior_label = Label.new()
-	_style_prior_label.add_theme_font_size_override("font_size", 12)
+	_style_prior_label.add_theme_font_size_override("font_size", _scaled_int(PRIOR_FONT_SIZE))
 	_style_prior_label.visible = false
 	root.add_child(_style_prior_label)
 
-	_resample_check = _make_check("Run resample", true)
+	_resample_check = _make_check(Strings.CLEANUP_RUN_RESAMPLE, true)
 	root.add_child(_resample_check)
 
-	_quantize_check = _make_check("Run quantize", true)
+	_quantize_check = _make_check(Strings.CLEANUP_RUN_QUANTIZE, true)
 	root.add_child(_quantize_check)
 
 	_scale_spin = _make_spin(1.0, 64.0, 0.1, 4.0)
-	_add_labeled_control(root, "Scale", _scale_spin)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_SCALE, _scale_spin)
 
 	_offset_x_spin = _make_spin(0.0, 64.0, 0.25, 0.0)
-	_add_labeled_control(root, "Offset X", _offset_x_spin)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_OFFSET_X, _offset_x_spin)
 
 	_offset_y_spin = _make_spin(0.0, 64.0, 0.25, 0.0)
-	_add_labeled_control(root, "Offset Y", _offset_y_spin)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_OFFSET_Y, _offset_y_spin)
 
 	_resample_options = _make_options(RESAMPLE_LABELS)
-	_add_labeled_control(root, "Resample", _resample_options)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_RESAMPLE, _resample_options)
 
 	_quantize_options = _make_options(QUANTIZE_LABELS)
-	_add_labeled_control(root, "Quantize", _quantize_options)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_QUANTIZE, _quantize_options)
 
 	_auto_k_strategy_options = _make_options(AUTO_K_STRATEGY_LABELS)
-	_auto_k_strategy_options.tooltip_text = "K-means is smoother for larger K, but slower."
-	_auto_k_strategy_row = _add_labeled_control(root, "Auto K Strategy", _auto_k_strategy_options)
+	_auto_k_strategy_options.tooltip_text = Strings.CLEANUP_AUTO_K_TOOLTIP
+	_auto_k_strategy_row = _add_labeled_control(
+		root, Strings.CLEANUP_LABEL_AUTO_K_STRATEGY, _auto_k_strategy_options
+	)
 
 	_palette_options = _make_options([])
-	_add_labeled_control(root, "Palette", _palette_options)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_PALETTE, _palette_options)
 	refresh_palette_options("db32")
 
 	_palette_preview = TextureRect.new()
-	_palette_preview.custom_minimum_size = Vector2(PALETTE_PREVIEW_WIDTH, PALETTE_PREVIEW_HEIGHT)
+	_palette_preview.custom_minimum_size = Vector2(
+		_scaled_int(PALETTE_PREVIEW_WIDTH), _scaled_int(PALETTE_PREVIEW_HEIGHT)
+	)
 	_palette_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
 	root.add_child(_palette_preview)
 
 	_delete_palette_button = Button.new()
-	_delete_palette_button.text = "Delete Custom Palette"
-	_delete_palette_button.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
+	_delete_palette_button.text = Strings.CLEANUP_DELETE_PALETTE
+	_delete_palette_button.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
 	_delete_palette_button.disabled = true
 	_delete_palette_button.pressed.connect(_delete_selected_custom_palette)
 	root.add_child(_delete_palette_button)
 	_update_palette_controls()
 
 	_k_spin = _make_spin(2.0, 256.0, 1.0, 16.0)
-	_add_labeled_control(root, "Max Colors", _k_spin)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_MAX_COLORS, _k_spin)
 
 	_dither_options = _make_options(DITHER_LABELS)
-	_add_labeled_control(root, "Dither", _dither_options)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_DITHER, _dither_options)
 
 	_strength_slider = _make_slider(0.0, 1.0, 0.05, 0.0)
-	_add_labeled_control(root, "Strength", _strength_slider)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_STRENGTH, _strength_slider)
 
 	_chroma_slider = _make_slider(0.0, 0.25, 0.01, 0.0)
-	_add_labeled_control(root, "Chroma", _chroma_slider)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_CHROMA, _chroma_slider)
 
 	_density_slider = _make_slider(0.0, 1.0, 0.05, 1.0)
-	_add_labeled_control(root, "Density", _density_slider)
+	_add_labeled_control(root, Strings.CLEANUP_LABEL_DENSITY, _density_slider)
 
 	_apply_button = Button.new()
-	_apply_button.text = "Apply Cleanup"
-	_apply_button.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
+	_apply_button.text = Strings.CLEANUP_APPLY
+	_apply_button.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
 	_apply_button.pressed.connect(func() -> void: apply_requested.emit(get_params()))
 	root.add_child(_apply_button)
 
 	_cancel_button = Button.new()
-	_cancel_button.text = "Cancel Cleanup"
-	_cancel_button.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
+	_cancel_button.text = Strings.CLEANUP_CANCEL
+	_cancel_button.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
 	_cancel_button.disabled = true
 	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
 	root.add_child(_cancel_button)
 
 	_report_label = Label.new()
 	_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
-	_report_label.text = "No cleanup report"
+	_report_label.text = Strings.CLEANUP_NO_REPORT
 	root.add_child(_report_label)
 
 	_preview_timer = Timer.new()
@@ -328,10 +344,10 @@
 
 func _add_labeled_control(parent: Control, label_text: String, control: Control) -> Control:
 	var row := VBoxContainer.new()
-	row.add_theme_constant_override("separation", 2)
+	row.add_theme_constant_override("separation", _scaled_int(2))
 	var label := Label.new()
 	label.text = label_text
-	label.add_theme_font_size_override("font_size", 13)
+	label.add_theme_font_size_override("font_size", _scaled_int(LABEL_FONT_SIZE))
 	row.add_child(label)
 	row.add_child(control)
 	parent.add_child(row)
@@ -351,7 +367,7 @@
 	spin.max_value = maximum
 	spin.step = step
 	spin.value = value
-	spin.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
+	spin.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
 	return spin
 
 
@@ -361,21 +377,25 @@
 	slider.max_value = maximum
 	slider.step = step
 	slider.value = value
-	slider.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
+	slider.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
 	return slider
 
 
 func _make_options(labels: Array) -> OptionButton:
 	var options := OptionButton.new()
-	options.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
+	options.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
 	for label in labels:
 		options.add_item(String(label))
 	return options
 
 
+func _scaled_int(value: int) -> int:
+	return int(round(value * maxf(ui_scale, 1.0)))
+
+
 func _create_palette_dialogs() -> void:
 	_palette_import_dialog = FileDialog.new()
-	_palette_import_dialog.title = "Import Custom Palette"
+	_palette_import_dialog.title = Strings.DIALOG_IMPORT_PALETTE
 	_palette_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
 	_palette_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 	_palette_import_dialog.filters = PackedStringArray(["*.json ; Palette JSON"])
@@ -383,7 +403,7 @@
 	add_child(_palette_import_dialog)
 
 	_palette_error_dialog = AcceptDialog.new()
-	_palette_error_dialog.title = "Palette Import Error"
+	_palette_error_dialog.title = Strings.DIALOG_PALETTE_ERROR
 	add_child(_palette_error_dialog)
 
 
@@ -411,7 +431,7 @@
 func _on_palette_file_selected(path: String) -> void:
 	var result := PaletteRegistry.import_custom_from_path(path)
 	if not bool(result.get("ok", false)):
-		_show_palette_error(String(result.get("error", "Palette import failed.")))
+		_show_palette_error(String(result.get("error", Strings.PALETTE_IMPORT_FAILED)))
 		return
 
 	var palette: PFPalette = result["palette"]
```

### `pixel/ui/shell/main.gd`

```diff
--- a/pixel/ui/shell/main.gd
+++ b/pixel/ui/shell/main.gd
@@ -72,13 +72,15 @@
 	if not (event is InputEventKey) or not event.pressed or event.echo:
 		return
 
-	if event.ctrl_pressed and event.keycode == KEY_S:
+	# macOS 习惯 Cmd+S/O/N；is_command_or_control_pressed() 在 mac 映射 Cmd、
+	# 其余平台映射 Ctrl，Windows 行为不变。
+	if event.is_command_or_control_pressed() and event.keycode == KEY_S:
 		_save_current_project()
 		get_viewport().set_input_as_handled()
-	elif event.ctrl_pressed and event.keycode == KEY_O:
+	elif event.is_command_or_control_pressed() and event.keycode == KEY_O:
 		_open_dialog.popup_centered_ratio(0.7)
 		get_viewport().set_input_as_handled()
-	elif event.ctrl_pressed and event.keycode == KEY_N:
+	elif event.is_command_or_control_pressed() and event.keycode == KEY_N:
 		_create_new_project()
 		get_viewport().set_input_as_handled()
 
@@ -97,17 +99,53 @@
 
 
 func _resolve_interface_scale() -> float:
-	var configured_scale := float(SettingsService.get_setting("ui", "interface_scale", 0.0))
-	if configured_scale >= MIN_INTERFACE_SCALE:
-		return clampf(configured_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)
-
 	if DisplayServer.get_name() == "headless":
 		return MIN_INTERFACE_SCALE
 
 	var screen := DisplayServer.window_get_current_screen()
 	var reported_scale := DisplayServer.screen_get_scale(screen)
 	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
-	return compute_auto_interface_scale(reported_scale, usable_rect.size)
+	var auto_scale := compute_auto_interface_scale(reported_scale, usable_rect.size)
+
+	var configured_scale := float(SettingsService.get_setting("ui", "interface_scale", 0.0))
+	# M0 复发复盘：manual-test-m0.md 曾指导测试者把 interface_scale 写成 1.0，
+	# 该值残留在 user://settings.cfg 后会永久旁路自动检测，在 Retina 屏表现为
+	# 界面缩小一半。一次性迁移：检测到 macOS Retina（自动检测 > 残留值）时
+	# 把残留的 1.0 重置回 0.0（自动），其他显式覆盖值仍然尊重用户选择。
+	if (
+		OS.get_name() == "macOS"
+		and is_equal_approx(configured_scale, 1.0)
+		and auto_scale > configured_scale
+	):
+		Log.warn(
+			"Stale interface_scale=1.0 override on a scaled display; resetting to auto.",
+			{"auto_scale": auto_scale}
+		)
+		SettingsService.set_setting("ui", "interface_scale", 0.0)
+		configured_scale = 0.0
+
+	var resolved := auto_scale
+	var source := "auto"
+	if configured_scale >= MIN_INTERFACE_SCALE:
+		resolved = clampf(configured_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)
+		source = "settings"
+
+	# 决策链日志：mac 缩放问题排查的第一手证据（screen scale / usable rect / 来源）。
+	(
+		Log
+		. info(
+			"Interface scale resolved",
+			{
+				"source": source,
+				"resolved": resolved,
+				"configured": configured_scale,
+				"reported_screen_scale": reported_scale,
+				"usable_rect": [usable_rect.size.x, usable_rect.size.y],
+				"os": OS.get_name(),
+			}
+		)
+	)
+	return resolved
 
 
 func _apply_viewport_scale_policy() -> void:
@@ -219,6 +257,8 @@
 	_cleanup_inspector = CleanupInspectorScript.new()
 	_cleanup_inspector.name = "CleanupInspector"
 	_cleanup_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
+	# 缩放注入必须在 add_child 之前完成：inspector 在 _ready 中按 ui_scale 构建 UI。
+	_cleanup_inspector.ui_scale = _ui_scale
 	content.add_child(_cleanup_inspector)
 
 	var bottom_bar := HBoxContainer.new()
```

### `pixel/ui/shell/strings.gd`

```diff
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -19,6 +19,36 @@
 const STATUS_PREVIEW_QUEUED := "Preview queued"
 const STATUS_EXPORT_EMPTY := "Select one sprite to export"
 const STATUS_EXPORTED := "PNG exported"
+const CLEANUP_TITLE := "Pixel Cleanup"
+const CLEANUP_SELECTED_FORMAT := "%d selected"
+const CLEANUP_PRESET_PRIOR_FORMAT := "Preset prior: %dpx"
+const CLEANUP_AUTO_DETECT := "Auto detect grid"
+const CLEANUP_RUN_RESAMPLE := "Run resample"
+const CLEANUP_RUN_QUANTIZE := "Run quantize"
+const CLEANUP_LABEL_SCALE := "Scale"
+const CLEANUP_LABEL_OFFSET_X := "Offset X"
+const CLEANUP_LABEL_OFFSET_Y := "Offset Y"
+const CLEANUP_LABEL_RESAMPLE := "Resample"
+const CLEANUP_LABEL_QUANTIZE := "Quantize"
+const CLEANUP_LABEL_AUTO_K_STRATEGY := "Auto K Strategy"
+const CLEANUP_LABEL_PALETTE := "Palette"
+const CLEANUP_LABEL_MAX_COLORS := "Max Colors"
+const CLEANUP_LABEL_DITHER := "Dither"
+const CLEANUP_LABEL_STRENGTH := "Strength"
+const CLEANUP_LABEL_CHROMA := "Chroma"
+const CLEANUP_LABEL_DENSITY := "Density"
+const CLEANUP_AUTO_K_TOOLTIP := "K-means is smoother for larger K, but slower."
+const CLEANUP_CUSTOM_PALETTE_PREFIX := "Custom: %s"
+const CLEANUP_IMPORT_PALETTE_ITEM := "Import custom palette..."
+const CLEANUP_DELETE_PALETTE := "Delete Custom Palette"
+const CLEANUP_APPLY := "Apply Cleanup"
+const CLEANUP_CANCEL := "Cancel Cleanup"
+const CLEANUP_NO_REPORT := "No cleanup report"
+const CLEANUP_NON_SQUARE_WARNING := "\nNon-square grid warning"
+const CLEANUP_REPORT_FORMAT := "Scale %.2f | Confidence %.2f\nColors %d | Output %s%s"
+const DIALOG_IMPORT_PALETTE := "Import Custom Palette"
+const DIALOG_PALETTE_ERROR := "Palette Import Error"
+const PALETTE_IMPORT_FAILED := "Palette import failed."
 const DIALOG_OPEN_PROJECT := "Open PixelForge Project"
 const DIALOG_SAVE_PROJECT := "Save PixelForge Project"
 const DIALOG_EXPORT_PNG := "Export PNG"
```

### `pixel/scripts/check_m1_1_coverage_matrix.sh`

```diff
--- a/pixel/scripts/check_m1_1_coverage_matrix.sh
+++ b/pixel/scripts/check_m1_1_coverage_matrix.sh
@@ -37,3 +37,22 @@
 fi
 
 echo "Coverage matrix references ${#TEST_NAMES[@]} existing tests."
+
+# 反向完整性检查（M1.1 改进新增）：
+# 正向检查只防"矩阵引用了不存在的测试"，不防"新增公开 API 漏列入矩阵"。
+# 这里枚举 core/pixel/*.gd 全部 static func 公开方法（下划线开头的私有方法除外），
+# 断言其名称出现在矩阵（行为矩阵或附录映射表，含 EXEMPT 豁免）中。
+missing_api=()
+while IFS= read -r api_name; do
+  if ! grep -q "${api_name}" "${MATRIX}"; then
+    missing_api+=("${api_name}")
+  fi
+done < <(grep -h '^static func [a-z]' core/pixel/*.gd | sed 's/static func \([a-z_0-9]*\).*/\1/' | sort -u)
+
+if [[ "${#missing_api[@]}" -gt 0 ]]; then
+  printf 'core/pixel public APIs missing from coverage matrix (add row or EXEMPT with reason):\n' >&2
+  printf ' - %s\n' "${missing_api[@]}" >&2
+  exit 1
+fi
+
+echo "All core/pixel public APIs are present in the coverage matrix."
```

### `pixel/scripts/verify_m1_1.sh`

```diff
--- a/pixel/scripts/verify_m1_1.sh
+++ b/pixel/scripts/verify_m1_1.sh
@@ -9,4 +9,37 @@
 echo "[M1.1 verify] coverage matrix"
 ./scripts/check_m1_1_coverage_matrix.sh
 
+echo "[M1.1 verify] p95 performance regression band"
+# M1.1 改进新增：性能此前只采样不门控。以 M1.1 完成报告实测 p95 为基线，
+# 允许 1.3 倍漂移带；超出说明引入了真实性能回归（或环境异常，需人工确认）。
+# 基线（2026-06-13，Apple M5 / Godot 4.6.3）：
+#   palette_map_p95_ms      156.92 -> cap 204
+#   grid_detect_p95_ms       76.94 -> cap 100
+#   cleanup_pipeline_p95_ms 221.95 -> cap 289
+PERF_LOG="$(mktemp)"
+trap 'rm -f "${PERF_LOG}"' EXIT
+source scripts/_godot_path.sh
+GODOT="$(find_godot)"
+prepare_godot_env
+"${GODOT}" --headless --script res://scripts/measure_m1.gd 2>&1 | tee "${PERF_LOG}"
+
+check_p95() {
+  local key="$1" cap="$2"
+  local value
+  value="$(grep -Eo "\"${key}\": *[0-9.]+" "${PERF_LOG}" | tail -n 1 | grep -Eo '[0-9.]+$' || true)"
+  if [[ -z "${value}" ]]; then
+    echo "p95 metric ${key} not found in measure output." >&2
+    exit 1
+  fi
+  if awk -v v="${value}" -v c="${cap}" 'BEGIN { exit !(v > c) }'; then
+    echo "p95 regression: ${key}=${value}ms exceeds cap ${cap}ms (baseline x1.3)." >&2
+    exit 1
+  fi
+  echo "p95 ok: ${key}=${value}ms (cap ${cap}ms)"
+}
+
+check_p95 "palette_map_p95_ms" 204
+check_p95 "grid_detect_p95_ms" 100
+check_p95 "cleanup_pipeline_p95_ms" 289
+
 echo "[M1.1 verify] completed"
```

### `pixel/docs/manual-test-m0.md`

```diff
--- a/pixel/docs/manual-test-m0.md
+++ b/pixel/docs/manual-test-m0.md
@@ -9,7 +9,7 @@
 3. 使用 Godot 编辑器或可执行程序打开项目，确认窗口标题为 `Untitled - PixelForge`。
 4. 在 macOS Retina / 5K 物理分辨率屏幕上确认窗口按自动 UI scale 放大：视觉上约为 1440x900 逻辑尺寸，字体边缘清晰，不再被 1440px viewport 压缩成小窗口。
 5. 确认顶部工具栏、按钮和状态栏文字可正常阅读；在 5K/Retina 环境下工具栏应使用 2x scale，在 4K 环境下应使用 1.5x scale。
-6. 如需手动覆盖界面缩放，可在 `user://settings.cfg` 中将 `ui/interface_scale` 设置为 `1.0`、`1.5` 或 `2.0`；`0.0` 表示自动检测。
+6. 如需手动覆盖界面缩放，可在 `user://settings.cfg` 中将 `ui/interface_scale` 设置为 `1.0`、`1.5` 或 `2.0`；`0.0` 表示自动检测。**测试结束后必须把该值还原为 `0.0`**——残留的显式覆盖会永久旁路自动检测，曾导致 macOS Retina 下界面缩小一半复发（M1.1 改进期已加入针对 mac 残留 `1.0` 的一次性自动迁移，但其他值仍会被尊重）。
 
 ## 2. 新建、拖入、画布交互
 
```

### `pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md`

```diff
--- a/pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md
+++ b/pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md
@@ -35,4 +35,37 @@
 | 项 | 状态 | 证据 |
 |---|---|---|
 | 真实 AI 样本肉眼质量 | 已登记 | `pixel/tests/fixtures/real/REAL_AI_REVIEW.md` |
-| 非技术用户导入 Lospec JSON 流程 | 待人工走查 | M1.1 UI 已提供导入、错误弹窗、色条预览、删除自定义项；自动化覆盖解析、持久化与清洗使用路径。 |
+| 非技术用户导入 Lospec JSON 流程 | 待人工走查 | 走查脚本与签字区：`pixel/docs/manual-test-m1_1.md`（含调色板视觉区分检查项）；自动化已覆盖解析、持久化与清洗使用路径。 |
+
+## 附录：core/pixel 公开 API 名称映射（反向完整性检查口径）
+
+> `check_m1_1_coverage_matrix.sh` 会枚举 `core/pixel/*.gd` 的全部 `static func` 公开方法，
+> 断言其名称出现在本文件中（上方行为矩阵或本表）。新增公开 API 而不更新本文件会让出口脚本失败。
+> 确无独立测试价值的项使用 `EXEMPT(理由)` 显式豁免——禁止留空。
+
+| 模块 | 公开 API | 覆盖来源 / 豁免 |
+|---|---|---|
+| `color_space.gd` | `byte_from_unit` | EXEMPT(纯算术换算，经 `color_to_rgba32` 路径间接覆盖) |
+| `color_space.gd` | `color_to_hex` / `hex_to_color` | hex 往返行 → `test_custom_palette_can_be_resolved_from_hex_values` |
+| `color_space.gd` | `color_to_rgba32` / `rgba32_to_color` | 经 `map_image` / `count_colors` 全路径间接覆盖 |
+| `color_space.gd` | `color_to_oklab` / `oklab_to_color` / `oklab_distance` / `rgb_distance` | 距离边界行 → `test_rgb_and_oklab_nearest_color_boundaries` |
+| `ditherer.gd` | `is_ordered` / `ordered_adjust` / `ordered_threshold` | Bayer 行 → `test_fixed_palette_bayer4_outputs_two_color_periodic_pattern` |
+| `ditherer.gd` | `chromatic_adjust` | chromatic 行 → `test_chromatic_dither_keeps_palette_constraint` |
+| `grid_detector.gd` | `detect` | 上方 grid_detector 两行 |
+| `palette.gd` | `load_builtin` | 内置板行 → `test_builtin_palettes_load_with_contract_counts` |
+| `palette.gd` | `extract_palette` / `map_image` / `from_json` | 上方 palette 行 |
+| `palette.gd` | `from_color_values` | `test_custom_palette_can_be_resolved_from_hex_values` |
+| `palette.gd` | `color_to_hex` / `hex_to_color` / `color_to_rgba32` / `rgba32_to_color` | color_space 同名转发，同上间接覆盖 |
+| `palette_registry.gd` | `resolve` / `parse_palette_file` / `parse_palette_text` / `parse_palette_data` | 上方 registry 行 |
+| `palette_registry.gd` | `import_custom_from_path` / `register_custom_palette` | `test_custom_palette_import_registers_palette_from_json` |
+| `palette_registry.gd` | `load_builtin` / `get_builtin_ids` / `get_custom_ids` / `get_palette_name` / `is_custom_palette` | 经导入/下拉刷新路径间接覆盖（`test_custom_palette_import_registers_palette_from_json`） |
+| `palette_registry.gd` | `load_from_path` | `test_custom_palette_survives_project_roundtrip` 间接 |
+| `palette_registry.gd` | `unregister_custom_palette` | EXEMPT(UI 删除入口，登记于人工走查清单 manual-test-m1_1.md，M2 前补自动化) |
+| `palette_registry.gd` | `clear_custom_palettes` | `test_invalid_custom_palette_reports_reason_and_does_not_pollute_registry` 前置清理使用 |
+| `palette_registry.gd` | `get_custom_manifest_entries` / `export_custom_zip_entries` / `load_custom_palettes_from_project` | 持久化行 → `test_custom_palette_survives_project_roundtrip` |
+| `pipeline.gd` | `apply` / `default_params` / `normalize_params` | 上方 pipeline 行 |
+| `pipeline.gd` | `get_default_step_ids` | `test_explicit_step_order_runs_only_requested_algorithms` 间接 |
+| `quantizer.gd` | `quantize` / `quantize_to_palette` | 上方 quantizer 行 |
+| `quantizer.gd` | `count_colors` | `test_auto_k_quantization_limits_color_count` 断言路径使用 |
+| `quantizer.gd` | `normalize_auto_k_strategy` | `test_auto_k_invalid_strategy_falls_back_to_median_cut` |
+| `resampler.gd` | `resample` | 上方 resampler 行 |
```

### `pixelforge-plan/04-research/RESEARCH-NOTES.md`

```diff
--- a/pixelforge-plan/04-research/RESEARCH-NOTES.md
+++ b/pixelforge-plan/04-research/RESEARCH-NOTES.md
@@ -72,3 +72,11 @@
 - 调研时间：2026-06-13。
 - 当前仓库 vendored GUT 未包含可搜索到的 `coverage` 命令、报告器或 headless 参数；`addons/gut/gut_cmdln.gd` 的现有出口参数只覆盖收集/运行/退出等流程。
 - 结论：M1.1 不把“代码行数比”包装成覆盖率数字，采用 `05-quality/COVERAGE-MATRIX-M1.md` 的 public API / 分支矩阵替代，并用 `pixel/scripts/check_m1_1_coverage_matrix.sh` 在出口脚本中校验矩阵引用的测试名真实存在。
+
+## 附录 B. Godot 4.6.3 headless 下 Image 线程安全调研（M1.1 批量压测）
+
+- 调研时间：2026-06-13（M1.1 批量帧时间测试实现期间），M1.1 改进期从完成报告风险区升格至此，供 M2+ 架构决策引用。
+- 现象：用 `WorkerThreadPool` 在 headless 模式下并行执行 `Image` 清洗（resample/quantize 全管线）不稳定——存在偶发崩溃/挂起，无可复现的最小用例但复现率足以阻断 CI。
+- 当前结论：M1.1 批量压测改为主线程分帧 Apply 口径（每帧处理一张 + `await` 一帧）；产品现有 TaskQueue 路径暂未改分帧。
+- 对 M2+ 的影响：若做大批量生产任务（批量抠图/切分/导出），必须先专项验证 `Image` 在线程内的安全边界（候选方案：每线程独立 `Image` 副本、仅在线程内做纯字节数组运算后主线程回写、或 Godot 官方 `Image` 线程安全声明确认后放开）。
+- 关联：`pixel/tests/integration/test_cleanup_batch_performance.gd` 头部注释、M1.1 完成报告 §5。
```

### `pixelforge-plan/03-milestones/M2-matting-slicing.md`

```diff
--- a/pixelforge-plan/03-milestones/M2-matting-slicing.md
+++ b/pixelforge-plan/03-milestones/M2-matting-slicing.md
@@ -93,6 +93,22 @@
 
 ---
 
+## 决策卡：界面缩放体系迁移到 content_scale_factor（M1.1 改进期立卡）
+
+**背景**：M0 为解决 macOS Retina 下窗口/界面缩小一半的问题，建立了自研缩放体系：启动时读 `DisplayServer.screen_get_scale()` 得出 `_ui_scale`，由各 UI 组件自觉调用 `_scaled_int()` 放大字号与尺寸。M1.x 新增的 `cleanup_inspector.gd` 未遵守该约定（硬编码像素值），导致 mac 缩放问题复发——这暴露了"约定式缩放"的结构性弱点：每个新 UI 组件都可能忘记接线，且无法被 lint/测试自动发现。
+
+**提议**：迁移到 Godot 官方推荐路线（godot-proposals#7968 口径）：`Window.content_scale_factor = screen_scale` + 窗口尺寸同乘，让全部 UI（含未来 M2+ 新面板）自动继承缩放，删除 `_scaled_int()` 约定体系。
+
+**决策点（M2 开工前评估，timebox 半天）**：
+1. `content_scale_factor` 对 `FileDialog`/`Popup` 等原生窗口部件的缩放是否一致（M0 时未验证，是当时选择自研体系的原因之一，需复测 4.6.3 行为）。
+2. 无限画布的像素网格渲染在 fractional scale（1.5x）下是否出现接缝/模糊；`CONTENT_SCALE_STRETCH_FRACTIONAL` 与画布 `scale_factor` 的叠加语义。
+3. 多显示器跨屏拖动：`content_scale_factor` 路线需监听 `window_changed` 类信号重算，评估改造点数量。
+4. 迁移成本：`main.gd` 主题字号体系、`cleanup_inspector.gd` 刚接入的 `ui_scale` 注入、测试影响面。
+
+**验收口径**：决策卡输出"迁移 / 维持自研体系并补 lint 守护"二选一结论与理由，写入本文件；若选迁移，M2 期间完成并在 mac Retina + Windows 100%/150% 三种环境人工走查。
+
+**临时缓解（M1.1 改进期已落地）**：`cleanup_inspector.gd` 已接入 `ui_scale` 注入；`_resolve_interface_scale()` 已加决策链日志与 mac 残留覆盖值迁移。
+
 ## M2 整体验收
 
 - v0.1 对外 alpha 完整故事：AI 图拖入 → 清洗 → 抠图 → 切分 → 描边统一 → 导出 spritesheet。手动测试脚本 docs/manual-test-m2.md 在双平台过。
```

### 新增文件（无 diff 基线）

- `pixel/docs/manual-test-m1_1.md`（37 行）：M1.1 人工走查清单 + 签字区。

---

## 5. 显式延后项（成本过高或需更高层决策，不静默丢弃）

| 项 | 延后理由 | 建议时点 |
|---|---|---|
| M1 评估报告 17 项闭环状态表 | 需回溯 M1 评估原始清单逐项核对补丁 A/B/C、M1.1、M2 移交归属，半天级工作量，不影响当前代码质量 | M2 开工前置项一并做 |
| M1/M1.1 变更 commit 拆分 | 提交粒度策略应由项目负责人决定；本次在完成报告 §6.3 强提醒 | 立即（人工） |
| 矩阵/走查实际签字 | 签字区与清单已就位，签字本身须人工执行 | 下次人工验收 |
| 跨屏拖动重算缩放、兜底阈值根治 | 依赖 content_scale_factor 决策卡结论，先改会做两遍 | M2 决策卡落地时 |
| TaskQueue 批量路径分帧化 / Image 线程安全专项 | RESEARCH-NOTES 附录 B 已登记约束与候选方案，属 M2+ 架构工作 | M2 批量功能设计时 |
| Lospec `.hex` / GIMP `.gpl` 格式 | M1.1 计划明确 future，维持不做 | 按计划 |

## 6. 验证记录与限制

| 验证项 | 结果 |
|---|---|
| gdformat --check（core/infra/services/ui/tests 全部 50 文件） | ✅ 通过 |
| gdlint（同范围） | ✅ Success: no problems found |
| bare print 检查（lint.sh 第三段口径） | ✅ 无裸 print |
| `bash -n` verify_m1_1.sh / check_m1_1_coverage_matrix.sh | ✅ 语法通过 |
| check_m1_1_coverage_matrix.sh 实际执行 | ✅ 41 tests + 全部公开 API 在位 |
| GUT 测试套件（72 tests） | ⚠ 本环境无 Godot 二进制，无法执行 |
| mac Retina 实机显示走查 | ⚠ 需按 `docs/manual-test-m1_1.md` §2 人工执行 |
| p95 回归带实跑 | ⚠ 随下次 `./scripts/verify_m1_1.sh` 验证 |

**改进后必须在开发机执行**：`./scripts/lint.sh && ./scripts/run_tests.sh && ./scripts/verify_m1_1.sh`，
并按 `docs/manual-test-m1_1.md` 完成 mac 显示走查。特别注意：批量压测负载加重后，
若 200ms 峰值预算在真实机器上失败，按 §2.3 的 strict/relaxed 口径先确认是预算还是回归。
