# macOS 显示过小二次修复完成报告

完成日期：2026-06-13  
修复目标：PixelForge 在 macOS Retina/高分屏上暂时恢复到 UI 和文字可正常看清。  
背景：M1.1 改进期已经做过 inspector 缩放、残留 `interface_scale=1.0` 迁移和决策链日志，但用户截图显示窗口和项目 UI 仍然过小。

---

## 1. 修复前诊断记录

### 1.1 本机设置排查

检查路径：

`~/Library/Application Support/Godot/app_userdata/PixelForge/settings.cfg`

结果：

```ini
[ui]
language="en"
interface_scale=0.0
```

结论：这次复发不是 `interface_scale=1.0` 残留配置单独导致。自动检测路径仍然会被执行。

### 1.2 修复前日志证据

检查 `user://logs/app_2026-06-12.log`，上一轮修复后的真实启动日志显示：

```text
reported_screen_scale: 1.0, usable_rect: [1244, 778], resolved: 1.0
reported_screen_scale: 1.0, usable_rect: [1334, 834], resolved: 1.0
reported_screen_scale: 1.0, usable_rect: [1440, 900], resolved: 1.0
reported_screen_scale: 1.0, usable_rect: [1440, 900], resolved: 1.0
```

结论：

1. Godot 在 macOS 上仍可能把 `DisplayServer.screen_get_scale()` 报成 `1.0`。
2. 当 `usable_rect` 返回的是 macOS 点口径（例如 1440×900）时，旧兜底阈值只识别 3200/1800、4800/2800 这类物理像素尺寸，必然落回 `1.0`。
3. 因为 `settings.cfg` 已是 `0.0`，这说明 M1.1 的“残留配置迁移”不是充分修复；自动检测本身还需要 mac 点口径兜底。

### 1.3 窗口尺寸二次问题

旧逻辑在 `_ui_scale=2.0` 时会把默认窗口尺寸放大，但又用未换算的 `usable_rect.size` 作为上限和居中依据。若 `usable_rect` 是点口径，窗口像素尺寸与屏幕点尺寸混用，会导致窗口被过早截断或居中偏移。

---

## 2. 本次修复内容

### 2.1 mac Retina 点口径自动识别

修改文件：`ui/shell/main.gd`

新增 `should_use_macos_retina_fallback()`，在以下情况下把自动界面缩放判定为 `2.0`：

1. `os_name == "macOS"`。
2. `reported_scale < 1.25`。
3. 满足以下任一条件：
   - `screen_dpi >= 160`，直接视为高 DPI。
   - `usable_rect` 落在常见 Retina 点口径范围：宽 1100–1800，高 700–1200，并且 `screen_dpi` 未知或不低于 120。

这覆盖了本次修复前日志里的 `[1244, 778]`、`[1334, 834]`、`[1440, 900]`，同时避免把明确低 DPI 的 1440×900 外接 1x 屏强行放大。

### 2.2 决策链日志补强

`Interface scale resolved` 日志新增字段：

- `screen_dpi`
- `mac_retina_fallback`

后续若再次复发，可从同一行日志判断是：

- Godot 报告了真实高分屏物理尺寸；
- 还是命中了 mac 点口径兜底；
- 或仍然被用户设置覆盖。

### 2.3 mac 窗口尺寸换算

`_apply_window_defaults()` 新增两段换算：

- `_window_pixel_size_from_screen_points()`：macOS 且 `_ui_scale > 1.0` 时，把屏幕点尺寸乘以 `_ui_scale`，作为窗口像素预算。
- `_screen_point_size_from_window_pixels()`：居中时把目标窗口像素尺寸除以 `_ui_scale`，换回点口径，避免位置计算用错单位。

新增 `Window defaults applied` 日志，记录：

- `ui_scale`
- `min_size`
- `target_size`
- `actual_size`
- `position`
- `usable_rect`

---

## 3. 测试与验证

### 3.1 新增自动化用例

修改文件：`tests/smoke/test_main_window_ui.gd`

新增 `test_auto_interface_scale_detects_macos_retina_point_rects()`，覆盖：

- `1244×778 / macOS / dpi 0 -> 2.0`
- `1334×834 / macOS / dpi 0 -> 2.0`
- `1440×900 / macOS / dpi 0 -> 2.0`
- `1440×900 / macOS / dpi 96 -> 1.0`
- `1920×1080 / macOS / dpi 110 -> 1.0`
- `1920×1080 / macOS / dpi 220 -> 2.0`

### 3.2 已执行验证

文件级格式与 lint：

```text
gdformat pixel/ui/shell/main.gd pixel/tests/smoke/test_main_window_ui.gd
gdlint pixel/ui/shell/main.gd pixel/tests/smoke/test_main_window_ui.gd
Success: no problems found
```

全仓 lint：

```text
./scripts/lint.sh
50 files would be left unchanged
Success: no problems found
```

smoke 测试（修复后先跑，用于快速确认新增用例）：

```text
Scripts: 2
Tests: 9
Passing Tests: 9
Asserts: 48
Result: All tests passed
```

说明：本次 smoke 测试仍报告 1 个 GUT orphan 和 Godot 退出时资源 warning，与本次缩放改动无关，且测试结果为通过。

全量 GUT 测试：

```text
./scripts/run_tests.sh
Scripts: 16
Tests: 73
Passing Tests: 73
Asserts: 684
Result: All tests passed
```

说明：全量测试同样报告 1 个 GUT orphan 和 Godot 退出时资源 warning；命令退出码为 0，所有测试通过。

### 3.3 图形模式短跑验证

执行：

```text
Godot --path . --quit-after 5
```

修复后日志：

```text
Interface scale resolved | {
  "configured": 0.0,
  "mac_retina_fallback": false,
  "os": "macOS",
  "reported_screen_scale": 1.0,
  "resolved": 2.0,
  "screen_dpi": 126,
  "source": "auto",
  "usable_rect": [5120, 2982]
}

Window defaults applied | {
  "actual_size": [2880, 1800],
  "min_size": [2560, 1600],
  "target_size": [2880, 1800],
  "ui_scale": 2.0,
  "usable_rect": [5120, 2982]
}
```

结论：在当前图形模式下，启动自动解析为 `2.0`，窗口目标尺寸和实际尺寸均放大到可读口径。该次短跑返回的是物理像素口径 `5120×2982`，因此没有触发 `mac_retina_fallback`；但新增 smoke 测试已固定此前复发的点口径场景。

---

## 4. 仍需后续处理的风险

1. 当前仍是 M0/M1.1 沿用的自研缩放体系，只是补强兜底；长期方案仍建议在 M2 决策卡中评估 Godot `content_scale_factor` 路线。
2. 跨屏拖动后仍不会动态重算 `_ui_scale`，需要后续监听窗口/屏幕变化再重建主题和布局。
3. 外接显示器组合很多，本次只按本机日志和常见 mac Retina 点尺寸做临时兜底；如果遇到特殊屏幕，优先查看 `Interface scale resolved` 与 `Window defaults applied` 两行日志。

---

## 5. 本次涉及文件

- `ui/shell/main.gd`
- `tests/smoke/test_main_window_ui.gd`
- `MAC_DISPLAY_FIX_COMPLETION_REPORT.md`
- `CHANGELOG.md`
