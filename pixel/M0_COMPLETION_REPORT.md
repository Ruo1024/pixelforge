# M0 完成报告
生成时间：2026-06-12 03:15:06 UTC+08:00，Godot 版本：4.6.3 stable。
## 结论
M0 基础开发、首次复审优化和第二次审批加固均已完成。当前自动化结果：`./scripts/lint.sh` 通过，`./scripts/run_tests.sh` 通过 29 tests / 224 asserts，`./scripts/check_export_templates.sh` headless 启动通过。
本地副本没有 `.git` 目录和 GitHub remote，因此仍不能确认真实 GitHub Actions 历史状态，也不能生成有效 CI badge URL。这个边界已写入 README 和本文后续注意事项。
Windows 实测不在当前 macOS 本机环境内完成，`docs/manual-test-m0.md` 已保留 Windows 11 + Godot 4.6.3 人工验证清单；M0 严格里程碑出口仍需要补这项。
## 第二次审批处理结果
- TaskQueue running cancel：新增完整生命周期测试，覆盖提交长任务、cancel、worker 自然返回、只收到 `task_canceled`、不收到 `task_finished`、最终 `is_idle() == true`。
- ProjectService format_version：代码已存在高版本拒开分支；本轮新增未来版本 `.pxproj` 集成测试，确保返回 `ERR_FILE_UNRECOGNIZED`。
- Logger 7 天滚动：原本已有清理逻辑；本轮改为公开 `cleanup_old_logs()`，按 `app_YYYY-MM-DD.log` 文件名日期判断，并新增过期日志删除测试。
- 视口剔除：`_update_item_visibility()` 现在同步设置 `visible`、`set_process()` 和 `set_physics_process()`，避免 M1/M2 给元素加动画或进度后视口外仍耗 CPU。
- AssetLibrary LRU：原本已有 `_lru_order`；本轮新增 `configure_cache_limit()` 和 `get_cached_asset_ids()` 诊断入口，并测试命中缓存后最近使用项不会被淘汰。
- HTTP/WebSocket stub：补齐稳定接口签名和返回结构，新增测试保证 M4/M7 接手时不用改调用方。WebSocket 避开 Godot `Object.is_connected()` 命名冲突，使用 `is_socket_connected()`。
- UndoService 内存约定：在 API 注释中明确 M1 图像快照必须传入 `estimate_snapshot_cost()`，否则内存上限无法生效。
- M1 交接：新增 `docs/m1-handoff-notes.md`，解释架构边界、关键设计意图、已知债务和验证命令。

## 已核查但不重复改造的点
- ProjectService 已经在 `_migrate_manifest()` 中拒绝高于 `AppInfo.PROJECT_FORMAT_VERSION` 的项目；本轮重点补测试而不是重复实现。
- Logger 已经按 7 天保留策略清理日志；本轮让行为更可测试，并改用文件名日期避免依赖平台 mtime。
- AssetLibrary 已经不是 Dictionary 随机淘汰，而是 `_lru_order` 控制顺序；本轮补可观测测试证明它是真 LRU。

## M0 功能实现摘要
- 工程骨架：Godot 4.6 项目结构、autoload 服务、CI workflow、lint/test/export-check 脚本。
- 主窗口：菜单/工具栏/状态栏、New/Open/Save/Save As、拖拽 PNG 导入、自动 UI scale 和 1440x900 默认可读窗口。
- 无限画布：平移、鼠标锚点缩放、像素网格、sprite 元素增删选移、Shift 多选、框选、视口剔除、整数坐标吸附。
- 项目格式：`.pxproj` 使用标准 ZIP，包含 `manifest.json`、`canvas/canvas.json`、`assets/*.png`、`assets/*.meta.json`，可被 `unzip -l` 人工检查。
- 基础服务：Logger、FileIO、HTTP/WebSocket stub、SettingsService、EventBus、UndoService、TaskQueue、AssetLibrary、ProjectService。
- 自动保存/恢复基础：ProjectService 提供 autosave、session lock、恢复提示信号和项目脏状态管理。
- 测试体系：unit/integration/smoke 三层 GUT 测试，覆盖文件 IO、撤销、任务队列、素材缓存、选择状态、项目 roundtrip、画布和窗口 UI。

## 验证记录
- `./scripts/lint.sh`：通过，输出 `32 files would be left unchanged` 与 `Success: no problems found`。
- `./scripts/run_tests.sh`：通过，10 scripts / 29 tests / 224 asserts。GUT 仍报告 1 个 `error_tracker.gd` orphan 和退出时资源警告，命令退出码为 0。
- `./scripts/check_export_templates.sh`：通过 headless 启动；本机未安装 Godot 4.6.3 export templates，脚本提示 CI 会安装模板。
- macOS 自动化入口继续使用项目内 `.godot/home` 作为临时 HOME，避免 `user://logs` 写入系统目录造成沙箱或权限环境崩溃。

## 行数与边界
- 当前一方 GDScript 行数：约 3379 行，不含 `addons/gut` 和 `.godot` 临时环境。
- `ui/canvas/infinite_canvas.gd` 当前低于 `.gdlintrc` 的 900 行上限；选择状态已拆到 `ui/canvas/canvas_selection.gd`。
- `.gdlintrc` 设置 `max-file-lines: 900`、`max-line-length: 120`；M1/M3 继续扩展画布时应继续按交互职责拆分。

## 本轮文件变更
第二次审批新增文件：
- `docs/m1-handoff-notes.md`
- `tests/unit/test_infra_clients.gd`

第二次审批修改文件：
- `CHANGELOG.md`
- `docs/manual-test-m0.md`
- `infra/logger.gd`
- `infra/http_client.gd`
- `infra/ws_client.gd`
- `services/asset_library.gd`
- `services/undo_service.gd`
- `ui/canvas/infinite_canvas.gd`
- `tests/unit/test_task_queue.gd`
- `tests/unit/test_file_io.gd`
- `tests/unit/test_asset_library.gd`
- `tests/integration/test_project_roundtrip.gd`
- `tests/smoke/test_infinite_canvas.gd`

首次复审/既有 M0 相关文件仍保留在最终附录：
- `.gdlintrc`
- `.gitignore`
- `README.md`
- `scripts/_godot_path.sh`
- `scripts/lint.sh`
- `scripts/run_tests.sh`
- `scripts/check_export_templates.sh`
- `services/event_bus.gd`
- `services/task_queue.gd`
- `services/pf_project.gd`
- `services/project_service.gd`
- `ui/canvas/canvas_item_frame.gd`
- `ui/canvas/canvas_item_sprite.gd`
- `ui/canvas/canvas_selection.gd`
- `ui/shell/main.gd`
- `core/util/id_util.gd`
- `core/util/image_math.gd`
- `core/util/log_util.gd`
- `infra/file_io.gd`
- `tests/unit/test_undo_service.gd`
- `export_presets.cfg.example`

## M1 接手重点
- 批处理任务用 `TaskQueue`，worker 不碰场景树；取消是协作式，必须等完成/取消信号。
- 涉及图像副本的 undo action 必须传 `UndoService.estimate_snapshot_cost(image)` 的累计值。
- 如果 M1 修改 `.pxproj` 格式，要提升 `PROJECT_FORMAT_VERSION` 并补迁移测试。
- 素材读取走 `AssetLibrary.get_image()`，返回副本；缓存 LRU 和字节计费由 AssetLibrary 维护。
- 画布新增状态优先拆到 helper，不要把 M1 清洗预览状态直接塞进 `infinite_canvas.gd`。
- HTTP/WebSocket 仍是 M4/M7 stub，M1 不应把 Provider 网络逻辑提前写进 infra。

## 登记债务
- 像素网格仍是 GDScript `draw_line` 循环。M0 性能测试通过；M1 末尾或 M3 前建议改成 shader/ColorRect。
- Windows 11 + Godot 4.6.3 实测仍未完成，需要按 `docs/manual-test-m0.md` 执行。
- 测试覆盖数量提升到 29 tests / 224 asserts，但 M1 开始前仍建议按任务卡逐条做验收覆盖盘点。
- 真实 GitHub Actions 状态无法从当前无 `.git`/无 remote 的本地副本确认；接入远端后补 CI badge 并保存 Actions 绿灯记录。

## 最终代码与文件路径附录

### `.editorconfig`

```ini
root = true

[*]
charset = utf-8
```

### `.gitattributes`

```gitattributes
# Normalize EOL for all files that Git considers text files.
* text=auto eol=lf
```

### `.gdlintrc`

```yaml
class-definitions-order:
- tools
- classnames
- extends
- docstrings
- signals
- enums
- consts
- staticvars
- exports
- pubvars
- prvvars
- onreadypubvars
- onreadyprvvars
- others
class-load-variable-name: (([A-Z][a-z0-9]*)+|_?[a-z][a-z0-9]*(_[a-z0-9]+)*)
class-name: ([A-Z][a-z0-9]*)+
class-variable-name: _?[a-z][a-z0-9]*(_[a-z0-9]+)*
comparison-with-itself: null
constant-name: _?[A-Z][A-Z0-9]*(_[A-Z0-9]+)*
disable: []
duplicated-load: null
enum-element-name: '[A-Z][A-Z0-9]*(_[A-Z0-9]+)*'
enum-name: ([A-Z][a-z0-9]*)+
excluded_directories: !!set
  .git: null
  .godot: null
  addons: null
expression-not-assigned: null
function-argument-name: _?[a-z][a-z0-9]*(_[a-z0-9]+)*
function-arguments-number: 10
function-name: (_on_([A-Z][a-z0-9]*)+(_[a-z0-9]+)*|_?[a-z][a-z0-9]*(_[a-z0-9]+)*)
function-preload-variable-name: ([A-Z][a-z0-9]*)+
function-variable-name: '[a-z][a-z0-9]*(_[a-z0-9]+)*'
load-constant-name: (([A-Z][a-z0-9]*)+|_?[A-Z][A-Z0-9]*(_[A-Z0-9]+)*)
loop-variable-name: _?[a-z][a-z0-9]*(_[a-z0-9]+)*
max-file-lines: 900
max-line-length: 120
max-public-methods: 20
max-returns: 6
mixed-tabs-and-spaces: null
no-elif-return: null
no-else-return: null
signal-name: '[a-z][a-z0-9]*(_[a-z0-9]+)*'
sub-class-name: _?([A-Z][a-z0-9]*)+
tab-characters: 1
trailing-whitespace: null
unnecessary-pass: null
unused-argument: null
```

### `.gitignore`

```gitignore
# Godot 4+ specific ignores
.godot/
/android/
/.import/
export.cfg
export_presets.cfg
export_presets.cfg.bak
*.translation
*.tmp
*.ziptmp
*.log
*.pxproj.tmp
/build/*
!/build/.gitkeep
/user/
.DS_Store
```

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
  pull_request:

jobs:
  lint-test-export-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Godot
        uses: chickensoft-games/setup-godot@v2
        with:
          version: 4.6.3
          use-dotnet: false
          include-templates: true

      - name: Install gdtoolkit
        run: python -m pip install gdtoolkit

      - name: Lint
        run: ./scripts/lint.sh

      - name: Tests
        run: ./scripts/run_tests.sh

      - name: Export template check
        run: ./scripts/check_export_templates.sh
```

### `project.godot`

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]

config/name="PixelForge"
run/main_scene="res://ui/shell/main.tscn"
config/features=PackedStringArray("4.6", "Forward Plus")
run/low_processor_mode=true
config/icon="res://icon.svg"

[autoload]

Logger="*res://infra/logger.gd"
SettingsService="*res://services/settings_service.gd"
EventBus="*res://services/event_bus.gd"
AssetLibrary="*res://services/asset_library.gd"
UndoService="*res://services/undo_service.gd"
TaskQueue="*res://services/task_queue.gd"
ProjectService="*res://services/project_service.gd"

[display]

window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1440
window/size/window_height_override=900
window/size/min_width=1280
window/size/min_height=800
window/stretch/mode="disabled"
window/stretch/aspect="ignore"
window/stretch/scale=1.0
window/stretch/scale_mode="fractional"

[physics]

3d/physics_engine="Jolt Physics"

[rendering]

textures/canvas_textures/default_texture_filter=0
rendering_device/driver.windows="d3d12"
```

### `export_presets.cfg.example`

```ini
[preset.0]

name="Linux"
platform="Linux"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/pixelforge-linux.x86_64"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=true

[preset.1]

name="Windows"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/PixelForge.exe"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.1.options]

binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=true
codesign/enable=false

[preset.2]

name="macOS"
platform="macOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/PixelForge.zip"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.2.options]

export/distribution_type=1
binary_format/architecture="universal"
codesign/codesign=1
codesign/identity_type=0
codesign/timestamp=false
notarization/notarization=0
```

### `scripts/_godot_path.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

find_godot() {
  if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then
    printf "%s\n" "${GODOT_BIN}"
    return 0
  fi

  if command -v godot >/dev/null 2>&1; then
    command -v godot
    return 0
  fi

  if command -v godot4 >/dev/null 2>&1; then
    command -v godot4
    return 0
  fi

  if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    printf "%s\n" "/Applications/Godot.app/Contents/MacOS/Godot"
    return 0
  fi

  if [[ -x "/Applications/godot/Godot.app/Contents/MacOS/Godot" ]]; then
    printf "%s\n" "/Applications/godot/Godot.app/Contents/MacOS/Godot"
    return 0
  fi

  printf "Godot executable not found. Set GODOT_BIN=/path/to/Godot.\n" >&2
  return 1
}

prepare_godot_home() {
  local godot_home="${GODOT_HOME:-$(pwd)/.godot/home}"
  mkdir -p "${godot_home}/Library/Application Support/Godot/app_userdata/PixelForge/logs"
  mkdir -p "${godot_home}/.local/share/godot/app_userdata/PixelForge/logs"
  printf "%s\n" "${godot_home}"
}
```

### `scripts/lint.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
gdscript_paths=(core infra services ui tests)
local_gdtoolkit_bin="$(pwd)/.godot/gdtoolkit-venv/bin"

if [[ -d "${local_gdtoolkit_bin}" ]]; then
  PATH="${local_gdtoolkit_bin}:${PATH}"
fi

if ! command -v gdformat >/dev/null 2>&1; then
  echo "gdformat not found. Install gdtoolkit before running lint: python -m pip install gdtoolkit" >&2
  exit 127
fi

if ! command -v gdlint >/dev/null 2>&1; then
  echo "gdlint not found. Install gdtoolkit before running lint: python -m pip install gdtoolkit" >&2
  exit 127
fi

gdformat --check "${gdscript_paths[@]}"
gdlint "${gdscript_paths[@]}"

if rg --line-number --glob '*.gd' --glob '!addons/gut/**' --glob '!infra/logger.gd' '\bprint(_rich|_verbose)?\s*\(' .; then
  echo "Bare print calls are only allowed inside infra/logger.gd. Use Logger instead." >&2
  status=1
fi

exit "${status}"
```

### `scripts/run_tests.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

GODOT="$(find_godot)"
GODOT_HOME="$(prepare_godot_home)"
HOME="${GODOT_HOME}" "${GODOT}" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gno_error_tracking -gexit
```

### `scripts/check_export_templates.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

GODOT="$(find_godot)"
GODOT_HOME="$(prepare_godot_home)"
version="$(HOME="${GODOT_HOME}" "${GODOT}" --version | cut -d. -f1-3)"
template_root="${HOME}/Library/Application Support/Godot/export_templates/${version}.stable"

if [[ -d "${template_root}" ]]; then
  echo "Export templates found: ${template_root}"
else
  echo "Export templates not found for Godot ${version}. CI installs them before export checks."
fi

HOME="${GODOT_HOME}" "${GODOT}" --headless --quit
```

### `core/util/app_info.gd`

```gdscript
class_name PFAppInfo
extends RefCounted

## 应用元信息的唯一入口。
## UI 标题、项目 manifest 和报告都应从这里读取名称与版本，避免散落硬编码。

const APP_NAME := "PixelForge"
const APP_VERSION := "0.1.0-m0"
const PROJECT_FORMAT_VERSION := 1
```

### `core/util/id_util.gd`

```gdscript
class_name PFIdUtil
extends RefCounted

## 小型 ID/时间工具。
## 输出契约：UUID 使用小写连字符格式；时间使用 UTC ISO8601，匹配 PROJECT-FORMAT.md。


static func uuid_v4() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var bytes := PackedByteArray()
	for index in range(16):
		bytes.append(rng.randi_range(0, 255))

	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	var parts := [
		_bytes_to_hex(bytes.slice(0, 4)),
		_bytes_to_hex(bytes.slice(4, 6)),
		_bytes_to_hex(bytes.slice(6, 8)),
		_bytes_to_hex(bytes.slice(8, 10)),
		_bytes_to_hex(bytes.slice(10, 16)),
	]
	return "-".join(parts)


static func utc_now_iso() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return (
		"%04d-%02d-%02dT%02d:%02d:%02dZ"
		% [
			int(date["year"]),
			int(date["month"]),
			int(date["day"]),
			int(date["hour"]),
			int(date["minute"]),
			int(date["second"]),
		]
	)


static func filesystem_stamp() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return (
		"%04d%02d%02d_%02d%02d%02d"
		% [
			int(date["year"]),
			int(date["month"]),
			int(date["day"]),
			int(date["hour"]),
			int(date["minute"]),
			int(date["second"]),
		]
	)


static func _bytes_to_hex(bytes: PackedByteArray) -> String:
	var text := ""
	for byte in bytes:
		text += "%02x" % int(byte)
	return text
```

### `core/util/image_math.gd`

```gdscript
class_name PFImageMath
extends RefCounted

## 图像数学公共函数。
## contract: 01-architecture/ARCHITECTURE.md §4.1，所有函数不修改入参，返回新的 Image。


static func duplicate_rgba8(source: Image) -> Image:
	var copy := source.duplicate()
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy


static func estimate_rgba8_bytes(image: Image) -> int:
	return image.get_width() * image.get_height() * 4


static func snapshot_region(source: Image, rect: Rect2i) -> Image:
	var image_bounds := Rect2i(Vector2i.ZERO, source.get_size())
	var clipped := rect.intersection(image_bounds)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)

	var snapshot := Image.create(clipped.size.x, clipped.size.y, false, source.get_format())
	snapshot.blit_rect(source, clipped, Vector2i.ZERO)
	return snapshot


static func color_set(image: Image) -> Dictionary:
	var colors := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			colors[image.get_pixel(x, y).to_html(true)] = true
	return colors
```

### `core/util/log_util.gd`

```gdscript
class_name PFLogUtil
extends RefCounted

## 日志转发工具。
## 用途：避免 autoload 解析顺序导致 `Logger.warn()` 被当作静态类调用。


static func debug(message: String, detail: Variant = null) -> void:
	_call_logger("debug", message, detail)


static func info(message: String, detail: Variant = null) -> void:
	_call_logger("info", message, detail)


static func warn(message: String, detail: Variant = null) -> void:
	_call_logger("warn", message, detail)


static func error(message: String, detail: Variant = null) -> void:
	_call_logger("error", message, detail)


static func _call_logger(method: String, message: String, detail: Variant) -> void:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree := main_loop as SceneTree
		var logger := tree.root.get_node_or_null("Logger")
		if logger != null:
			logger.call(method, message, detail)
			return

	var text := message
	if detail != null:
		text += " | " + var_to_str(detail)

	if method == "error":
		push_error(text)
	elif method == "warn":
		push_warning(text)
```

### `infra/logger.gd`

```gdscript
class_name PFLogger
extends Node

## 分级日志 autoload。
## 职责：统一写控制台和 user://logs/app_YYYY-MM-DD.log，并滚动保留最近 7 天。

enum Level { DEBUG, INFO, WARN, ERROR }

const LOG_DIR := "user://logs"
const LOG_RETENTION_DAYS := 7
const IdUtil := preload("res://core/util/id_util.gd")

var _log_path := ""
var _minimum_level := Level.DEBUG


func _ready() -> void:
	_prepare_log_file()
	info("Logger ready")


func set_minimum_level(level: int) -> void:
	_minimum_level = clampi(level, Level.DEBUG, Level.ERROR)


func debug(message: String, detail: Variant = null) -> void:
	_write(Level.DEBUG, message, detail)


func info(message: String, detail: Variant = null) -> void:
	_write(Level.INFO, message, detail)


func warn(message: String, detail: Variant = null) -> void:
	_write(Level.WARN, message, detail)


func error(message: String, detail: Variant = null) -> void:
	_write(Level.ERROR, message, detail)


func get_current_log_path() -> String:
	if _log_path.is_empty():
		_prepare_log_file()
	return _log_path


func cleanup_old_logs(now_unix: float = -1.0) -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return

	var current_time := now_unix
	if current_time < 0.0:
		current_time = Time.get_unix_time_from_system()

	var cutoff := current_time - float(LOG_RETENTION_DAYS * 24 * 60 * 60)
	for file_name in dir.get_files():
		if not file_name.begins_with("app_") or not file_name.ends_with(".log"):
			continue

		var file_path := "%s/%s" % [LOG_DIR, file_name]
		if _log_file_time(file_name, file_path) < cutoff:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


func _prepare_log_file() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	_log_path = "%s/app_%s.log" % [LOG_DIR, _date_stamp()]
	cleanup_old_logs()


func _write(level: int, message: String, detail: Variant) -> void:
	if level < _minimum_level:
		return

	if _log_path.is_empty():
		_prepare_log_file()

	var level_name := _level_to_name(level)
	var line := "[%s] [%s] %s" % [_timestamp(), level_name, message]
	if detail != null:
		line += " | " + var_to_str(detail)

	# Logger 是唯一允许直接写控制台的位置；其他模块都通过本服务记录。
	print(line)

	var file := _open_log_for_append()
	if file != null:
		file.store_line(line)


func _open_log_for_append() -> FileAccess:
	if FileAccess.file_exists(_log_path):
		var existing := FileAccess.open(_log_path, FileAccess.READ_WRITE)
		if existing != null:
			existing.seek_end()
		return existing
	return FileAccess.open(_log_path, FileAccess.WRITE)


func _log_file_time(file_name: String, file_path: String) -> float:
	var date_text := file_name.substr(4, file_name.length() - 8)
	var parts := date_text.split("-")
	if parts.size() == 3:
		return (
			Time
			. get_unix_time_from_datetime_dict(
				{
					"year": int(parts[0]),
					"month": int(parts[1]),
					"day": int(parts[2]),
					"hour": 0,
					"minute": 0,
					"second": 0,
				}
			)
		)

	return float(FileAccess.get_modified_time(file_path))


func _level_to_name(level: int) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
		_:
			return "UNKNOWN"


func _date_stamp() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


func _timestamp() -> String:
	return IdUtil.utc_now_iso()
```

### `infra/file_io.gd`

```gdscript
class_name FileIO
extends RefCounted

## 文件 IO 工具类。
## contract: 02-contracts/PROJECT-FORMAT.md §1/§5，项目保存必须 ZIP 可检查且原子写。


static func save_png(image: Image, path: String) -> Error:
	_ensure_parent_dir(path)
	return image.save_png(path)


static func load_png(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


static func atomic_write(path: String, bytes: PackedByteArray) -> Error:
	_ensure_parent_dir(path)
	var temp_path := "%s.tmp-%s" % [path, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_buffer(bytes)
	file.flush()
	file.close()

	var target_global := _global_path(path)
	var temp_global := _global_path(temp_path)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(target_global)
		if remove_error != OK and remove_error != ERR_DOES_NOT_EXIST:
			DirAccess.remove_absolute(temp_global)
			return remove_error

	var rename_error := DirAccess.rename_absolute(temp_global, target_global)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_global)
	return rename_error


static func zip_pack(dir_map: Dictionary, path: String) -> Error:
	_ensure_parent_dir(path)
	var temp_path := "%s.ziptmp-%s" % [path, str(Time.get_ticks_usec())]
	var packer := ZIPPacker.new()
	var open_error := packer.open(temp_path)
	if open_error != OK:
		return open_error

	var file_names := dir_map.keys()
	file_names.sort()
	for file_name in file_names:
		var start_error := packer.start_file(String(file_name))
		if start_error != OK:
			packer.close()
			DirAccess.remove_absolute(_global_path(temp_path))
			return start_error

		var bytes := _variant_to_bytes(dir_map[file_name])
		packer.write_file(bytes)
		packer.close_file()

	packer.close()
	return _replace_file(temp_path, path)


static func zip_unpack(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error := reader.open(path)
	if open_error != OK:
		return {"ok": false, "error": open_error, "files": {}}

	var files := {}
	for file_name in reader.get_files():
		files[file_name] = reader.read_file(file_name)
	reader.close()

	return {"ok": true, "error": OK, "files": files}


static func json_to_bytes(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "\t").to_utf8_buffer()


static func bytes_to_json(bytes: PackedByteArray) -> Variant:
	var parser := JSON.new()
	var error := parser.parse(bytes.get_string_from_utf8())
	if error != OK:
		return null
	return parser.data


static func _replace_file(temp_path: String, target_path: String) -> Error:
	var target_global := _global_path(target_path)
	var temp_global := _global_path(temp_path)
	if FileAccess.file_exists(target_path):
		var remove_error := DirAccess.remove_absolute(target_global)
		if remove_error != OK and remove_error != ERR_DOES_NOT_EXIST:
			DirAccess.remove_absolute(temp_global)
			return remove_error
	return DirAccess.rename_absolute(temp_global, target_global)


static func _variant_to_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if value is Image:
		return value.save_png_to_buffer()
	if value is Dictionary or value is Array:
		return json_to_bytes(value)
	return str(value).to_utf8_buffer()


static func _ensure_parent_dir(path: String) -> void:
	var parent := _global_path(path).get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)


static func _global_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
```

### `infra/http_client.gd`

```gdscript
class_name PFHttpClient
extends RefCounted

## HTTP 客户端接口占位。
## M4 会实现重试、超时和 Provider 鉴权；M0 先固定调用形状，避免后续移动 infra 目录。
## 设计意图：上层只依赖 request_raw/request_json 的结果字典，不直接绑定 Godot HTTPRequest 节点。
## M4 实现时保持返回字段 ok/status_code/headers/body/error，调用方就不需要改签名。

signal request_started(url: String, method: int)
signal request_completed(result: Dictionary)


func request_raw(
	url: String,
	method: int = HTTPClient.METHOD_GET,
	headers: PackedStringArray = PackedStringArray(),
	body: PackedByteArray = PackedByteArray(),
	timeout_seconds: float = 30.0
) -> Dictionary:
	request_started.emit(url, method)
	var result := _unavailable_result(url, method, headers, body, timeout_seconds)
	request_completed.emit(result)
	return result


func request_json(
	url: String,
	method: int = HTTPClient.METHOD_GET,
	headers: PackedStringArray = PackedStringArray(),
	body: Variant = null,
	timeout_seconds: float = 30.0
) -> Dictionary:
	var body_bytes := PackedByteArray()
	if body != null:
		body_bytes = JSON.stringify(body).to_utf8_buffer()
	return request_raw(url, method, headers, body_bytes, timeout_seconds)


func cancel_all() -> void:
	return


func _unavailable_result(
	url: String,
	method: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	timeout_seconds: float
) -> Dictionary:
	return {
		"ok": false,
		"status_code": 0,
		"headers": PackedStringArray(),
		"body": PackedByteArray(),
		"error": "HTTP client is reserved for M4.",
		"url": url,
		"method": method,
		"request_headers": headers,
		"request_body": body,
		"timeout_seconds": timeout_seconds,
	}
```

### `infra/ws_client.gd`

```gdscript
class_name PFWsClient
extends RefCounted

## WebSocket 客户端接口占位。
## M7 ComfyUI 桥接会在这里补连接、心跳和消息分发。
## 设计意图：先固定连接、发送、轮询和关闭签名；M7 只替换内部实现，不改变调用方。

signal connected(url: String)
signal connection_failed(error: Dictionary)
signal message_received(message: Variant)
signal closed(code: int, reason: String)

const Log := preload("res://core/util/log_util.gd")


func connect_to_endpoint(url: String) -> Error:
	Log.debug("WebSocket client is reserved for M7", {"url": url})
	connection_failed.emit({"error": ERR_UNAVAILABLE, "url": url})
	return ERR_UNAVAILABLE


func is_socket_connected() -> bool:
	return false


func send_text(message: String) -> Error:
	Log.debug("WebSocket send_text ignored before M7", {"bytes": message.length()})
	return ERR_UNAVAILABLE


func send_json(message: Variant) -> Error:
	return send_text(JSON.stringify(message))


func poll() -> void:
	return


func close() -> void:
	closed.emit(0, "not connected")
```

### `services/event_bus.gd`

```gdscript
class_name PFEventBus
extends Node

## 全局事件总线。
## UI 模块之间不直接互相引用；跨模块消息集中在这里声明，便于新手查找事件来源。
## 命名约定：按 project / asset / canvas / task 分组；事件用过去式或状态变化后缀
## （如 saved、added、changed）；参数顺序优先 id/path，再放结果对象或状态值。

signal project_created(project_id: String)
signal project_opened(path: String)
signal project_saved(path: String)
signal project_dirty_changed(is_dirty: bool)
signal recovery_available(autosaves: Array)
signal asset_added(asset_id: String)
signal asset_removed(asset_id: String)
signal canvas_changed
signal task_started(task_id: String, kind: String)
signal task_progressed(task_id: String, ratio: float, message: String)
signal task_finished(task_id: String, result: Variant)
signal task_failed(task_id: String, error: Dictionary)
signal task_canceled(task_id: String)
```

### `services/settings_service.gd`

```gdscript
class_name PFSettingsService
extends Node

## 用户设置服务。
## 使用 ConfigFile 包装 user://settings.cfg，并通过 setting_changed 信号通知 UI 刷新。

signal setting_changed(section: String, key: String, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"
const Log := preload("res://core/util/log_util.gd")

var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> Error:
	var error := _config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		Log.warn("Failed to load settings", {"error": error})
		return error

	_ensure_defaults()
	return OK


func save_settings() -> Error:
	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		Log.warn("Failed to save settings", {"error": error})
	return error


func get_setting(section: String, key: String, default_value: Variant = null) -> Variant:
	return _config.get_value(section, key, default_value)


func set_setting(section: String, key: String, value: Variant, save_now: bool = true) -> void:
	var old_value: Variant = _config.get_value(section, key, null)
	_config.set_value(section, key, value)
	if old_value != value:
		setting_changed.emit(section, key, value)

	if save_now:
		save_settings()


func get_recent_projects() -> Array:
	return _config.get_value("project", "recent_projects", [])


func add_recent_project(path: String) -> void:
	if path.is_empty():
		return

	var recent := get_recent_projects()
	recent.erase(path)
	recent.push_front(path)
	while recent.size() > 10:
		recent.pop_back()
	set_setting("project", "recent_projects", recent)


func _ensure_defaults() -> void:
	var changed := false
	changed = _set_default("ui", "language", "en") or changed
	changed = _set_default("ui", "interface_scale", 0.0) or changed
	changed = _set_default("project", "recent_projects", []) or changed
	changed = _set_default("tasks", "max_concurrency", 2) or changed
	if changed:
		save_settings()


func _set_default(section: String, key: String, value: Variant) -> bool:
	if _config.has_section_key(section, key):
		return false
	_config.set_value(section, key, value)
	return true
```

### `services/pf_task.gd`

```gdscript
class_name PFTask
extends RefCounted

## 任务队列的任务对象。
## contract: 01-architecture/ARCHITECTURE.md §4.2；工作线程只运行 work_callable，信号由 TaskQueue 回主线程转发。

signal progress_reported(task_id: String, ratio: float, message: String)
signal finished(result: Variant)
signal failed(error: Dictionary)
signal canceled

const IdUtil := preload("res://core/util/id_util.gd")

var id := ""
var kind := ""
var payload := {}
var work_callable := Callable()
var cancel_requested := false
var queue_sequence := -1

var _queue: Node = null


func _init(
	p_kind: String = "", p_payload: Dictionary = {}, p_work_callable: Callable = Callable()
) -> void:
	id = IdUtil.uuid_v4()
	kind = p_kind
	payload = p_payload.duplicate(true)
	work_callable = p_work_callable


func cancel() -> void:
	cancel_requested = true


func report_progress(ratio: float, message: String = "") -> void:
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	if _queue != null:
		_queue.call_deferred("_emit_task_progress", id, clamped_ratio, message)
	else:
		progress_reported.emit(id, clamped_ratio, message)


func execute() -> Variant:
	if cancel_requested:
		return null
	if work_callable.is_valid():
		return work_callable.call(self)
	return payload


func _assign_queue(queue: Node) -> void:
	_queue = queue
```

### `services/task_queue.gd`

```gdscript
class_name PFTaskQueue
extends Node

## 简单 FIFO 并发任务队列。
## 关键约束：WorkerThreadPool 内不碰场景树；所有进度/完成信号都用 call_deferred 回主线程发出。

signal task_started(task_id: String, kind: String)
signal task_progressed(task_id: String, ratio: float, message: String)
signal task_finished(task_id: String, result: Variant)
signal task_failed(task_id: String, error: Dictionary)
signal task_canceled(task_id: String)

const DEFAULT_MAX_CONCURRENCY := 2

var _max_concurrency := DEFAULT_MAX_CONCURRENCY
var _pending: Array = []
var _running := {}
var _worker_ids := {}
var _completed_by_sequence := {}
var _next_sequence := 0
var _next_finish_sequence := 0
var _main_thread_id := ""


func _ready() -> void:
	_main_thread_id = str(OS.get_thread_caller_id())
	_max_concurrency = int(
		SettingsService.get_setting("tasks", "max_concurrency", DEFAULT_MAX_CONCURRENCY)
	)


func set_max_concurrency(value: int) -> void:
	_max_concurrency = maxi(1, value)
	SettingsService.set_setting("tasks", "max_concurrency", _max_concurrency)
	_pump_queue()


func get_max_concurrency() -> int:
	return _max_concurrency


func get_main_thread_id() -> String:
	return _main_thread_id


func submit(task: Variant) -> String:
	task._assign_queue(self)
	task.queue_sequence = _next_sequence
	_next_sequence += 1
	_pending.append(task)
	_pump_queue()
	return task.id


func cancel(task_id: String) -> void:
	for index in range(_pending.size()):
		var task: Variant = _pending[index]
		if task.id == task_id:
			task.cancel()
			_pending.remove_at(index)
			_store_completion(task, "canceled", null, {})
			_flush_completed_in_order()
			return

	if _running.has(task_id):
		var running_task: Variant = _running[task_id]
		# WorkerThreadPool 不能被安全抢占。这里仅设置取消标志；
		# _running 清理和 task_canceled 信号会在 worker 返回后的主线程回调中完成。
		running_task.cancel()


func clear() -> void:
	for task in _pending:
		task.cancel()
	for task_id in _running.keys():
		_running[task_id].cancel()
	_pending.clear()
	_completed_by_sequence.clear()
	_next_sequence = 0
	_next_finish_sequence = 0


func is_idle() -> bool:
	return _pending.is_empty() and _running.is_empty() and _completed_by_sequence.is_empty()


func get_running_count() -> int:
	return _running.size()


func get_pending_count() -> int:
	return _pending.size()


func _pump_queue() -> void:
	while _running.size() < _max_concurrency and not _pending.is_empty():
		var task: Variant = _pending.pop_front()
		if task.cancel_requested:
			_store_completion(task, "canceled", null, {})
			continue
		_start_task(task)
	_flush_completed_in_order()


func _start_task(task: Variant) -> void:
	_running[task.id] = task
	task_started.emit(task.id, task.kind)
	EventBus.task_started.emit(task.id, task.kind)

	var worker_callable := func() -> void:
		var result: Variant = task.execute()
		call_deferred("_complete_task_from_worker", task.id, result)

	var worker_id := WorkerThreadPool.add_task(worker_callable, false, "PFTask:%s" % task.kind)
	_worker_ids[task.id] = worker_id


func _complete_task_from_worker(task_id: String, result: Variant) -> void:
	if not _running.has(task_id):
		return

	var task: Variant = _running[task_id]
	_running.erase(task_id)
	if _worker_ids.has(task_id):
		WorkerThreadPool.wait_for_task_completion(int(_worker_ids[task_id]))
		_worker_ids.erase(task_id)

	if task.cancel_requested:
		_store_completion(task, "canceled", null, {})
	else:
		_store_completion(task, "finished", result, {})

	_flush_completed_in_order()
	_pump_queue()


func _emit_task_progress(task_id: String, ratio: float, message: String) -> void:
	if not _running.has(task_id):
		return

	var task: Variant = _running[task_id]
	if task.cancel_requested:
		return

	task.progress_reported.emit(task_id, ratio, message)
	task_progressed.emit(task_id, ratio, message)
	EventBus.task_progressed.emit(task_id, ratio, message)


func _store_completion(task: Variant, status: String, result: Variant, error: Dictionary) -> void:
	_completed_by_sequence[task.queue_sequence] = {
		"task": task,
		"status": status,
		"result": result,
		"error": error,
	}


func _flush_completed_in_order() -> void:
	while _completed_by_sequence.has(_next_finish_sequence):
		var completion: Dictionary = _completed_by_sequence[_next_finish_sequence]
		_completed_by_sequence.erase(_next_finish_sequence)
		_next_finish_sequence += 1

		var task: Variant = completion["task"]
		match String(completion["status"]):
			"finished":
				task.finished.emit(completion["result"])
				task_finished.emit(task.id, completion["result"])
				EventBus.task_finished.emit(task.id, completion["result"])
			"failed":
				task.failed.emit(completion["error"])
				task_failed.emit(task.id, completion["error"])
				EventBus.task_failed.emit(task.id, completion["error"])
			"canceled":
				task.canceled.emit()
				task_canceled.emit(task.id)
				EventBus.task_canceled.emit(task.id)
```

### `services/undo_service.gd`

```gdscript
class_name PFUndoService
extends Node

## 全局撤销/重做服务。
## 说明：对外提供动作级 API；图像快照按字节估算计费，超过步数或内存上限时丢弃最旧动作。
## 约定：任何 undo action 如果持有 Image 或 Image 副本，调用方必须把
## estimate_snapshot_cost(image) 的结果传入 add_memory_cost()/perform_action()。
## 这样 M1 的清洗、量化、裁切步骤才不会绕过内存上限。

signal action_committed(name: String)
signal undone(name: String)
signal redone(name: String)
signal history_changed

const DEFAULT_MAX_STEPS := 100
const DEFAULT_MAX_MEMORY_BYTES := 512 * 1024 * 1024
const ImageMath := preload("res://core/util/image_math.gd")
const Log := preload("res://core/util/log_util.gd")


class PFUndoAction:
	var name := ""
	var do_callbacks: Array = []
	var undo_callbacks: Array = []
	var memory_cost_bytes := 0

	func run_do() -> void:
		for callback in do_callbacks:
			callback.call()

	func run_undo() -> void:
		var index := undo_callbacks.size() - 1
		while index >= 0:
			undo_callbacks[index].call()
			index -= 1


var _stack: Array = []
var _cursor := 0
var _current_action: PFUndoAction = null
var _max_steps := DEFAULT_MAX_STEPS
var _max_memory_bytes := DEFAULT_MAX_MEMORY_BYTES
var _memory_bytes := 0


func configure_limits(max_steps: int, max_memory_bytes: int) -> void:
	_max_steps = maxi(1, max_steps)
	_max_memory_bytes = maxi(1, max_memory_bytes)
	_trim_limits()
	history_changed.emit()


func reset_limits() -> void:
	_max_steps = DEFAULT_MAX_STEPS
	_max_memory_bytes = DEFAULT_MAX_MEMORY_BYTES
	_trim_limits()
	history_changed.emit()


func begin_action(name: String) -> void:
	if _current_action != null:
		Log.warn(
			"Undo action was open; committing it before starting another.",
			{"name": _current_action.name}
		)
		commit()

	_current_action = PFUndoAction.new()
	_current_action.name = name


func add_do_callable(callback: Callable) -> void:
	if _current_action == null:
		Log.warn("add_do_callable ignored because no undo action is open")
		return
	_current_action.do_callbacks.append(callback)


func add_undo_callable(callback: Callable) -> void:
	if _current_action == null:
		Log.warn("add_undo_callable ignored because no undo action is open")
		return
	_current_action.undo_callbacks.append(callback)


func add_memory_cost(bytes: int) -> void:
	if _current_action == null:
		Log.warn("add_memory_cost ignored because no undo action is open")
		return
	_current_action.memory_cost_bytes += maxi(0, bytes)


func commit(execute_do: bool = true) -> void:
	if _current_action == null:
		return

	var action := _current_action
	_current_action = null
	if execute_do:
		action.run_do()

	_drop_redo_tail()
	_stack.append(action)
	_cursor = _stack.size()
	_memory_bytes += action.memory_cost_bytes
	_trim_limits()

	action_committed.emit(action.name)
	history_changed.emit()


func perform_action(
	name: String,
	do_callback: Callable,
	undo_callback: Callable,
	memory_cost_bytes: int = 0,
	execute_do: bool = true
) -> void:
	begin_action(name)
	add_do_callable(do_callback)
	add_undo_callable(undo_callback)
	add_memory_cost(memory_cost_bytes)
	commit(execute_do)


func undo() -> bool:
	if not can_undo():
		return false

	_cursor -= 1
	var action: PFUndoAction = _stack[_cursor]
	action.run_undo()
	undone.emit(action.name)
	history_changed.emit()
	return true


func redo() -> bool:
	if not can_redo():
		return false

	var action: PFUndoAction = _stack[_cursor]
	action.run_do()
	_cursor += 1
	redone.emit(action.name)
	history_changed.emit()
	return true


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _stack.size()


func clear() -> void:
	_stack.clear()
	_cursor = 0
	_current_action = null
	_memory_bytes = 0
	history_changed.emit()


func snapshot_region(image: Image, rect: Rect2i) -> Image:
	return ImageMath.snapshot_region(image, rect)


func estimate_snapshot_cost(image: Image) -> int:
	# 统一按 RGBA8 快照估算，即 width * height * 4 字节。
	# 调用方持有多个图像副本时，应逐张相加后传入 action 的 memory_cost。
	return ImageMath.estimate_rgba8_bytes(image)


func get_memory_bytes() -> int:
	return _memory_bytes


func get_undo_count() -> int:
	return _cursor


func get_redo_count() -> int:
	return _stack.size() - _cursor


func _drop_redo_tail() -> void:
	while _stack.size() > _cursor:
		var dropped: PFUndoAction = _stack.pop_back()
		_memory_bytes -= dropped.memory_cost_bytes
	_memory_bytes = maxi(0, _memory_bytes)


func _trim_limits() -> void:
	while _stack.size() > _max_steps or _memory_bytes > _max_memory_bytes:
		if _stack.is_empty():
			break
		var dropped: PFUndoAction = _stack.pop_front()
		_memory_bytes -= dropped.memory_cost_bytes
		if _cursor > 0:
			_cursor -= 1
	_memory_bytes = maxi(0, _memory_bytes)
```

### `services/asset_library.gd`

```gdscript
class_name PFAssetLibrary
extends Node

## 项目素材库。
## 职责：注册 Image、维护 meta、PNG 字节和一个简单 LRU 图像缓存；保存时导出 assets/{id}.png/meta.json。

signal asset_added(asset_id: String)
signal asset_removed(asset_id: String)

const CACHE_LIMIT_BYTES := 256 * 1024 * 1024
const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const Log := preload("res://core/util/log_util.gd")

var _metadata := {}
var _png_bytes := {}
var _image_cache := {}
var _lru_order: Array = []
var _ref_counts := {}
var _cache_limit_bytes := CACHE_LIMIT_BYTES
var _cache_bytes := 0


func clear() -> void:
	_metadata.clear()
	_png_bytes.clear()
	_image_cache.clear()
	_lru_order.clear()
	_ref_counts.clear()
	_cache_limit_bytes = CACHE_LIMIT_BYTES
	_cache_bytes = 0


func register_image(image: Image, name: String, extra_meta: Dictionary = {}) -> String:
	var asset_id := String(extra_meta.get("id", IdUtil.uuid_v4()))
	var rgba: Image = ImageMath.duplicate_rgba8(image)
	var now: String = IdUtil.utc_now_iso()
	var default_provenance := {
		"provider": null,
		"model": null,
		"prompt": "",
		"seed": null,
		"parent_asset": null,
		"graph_id": null,
		"created_at": now,
	}

	var meta := {
		"id": asset_id,
		"name": name,
		"tags": extra_meta.get("tags", []),
		"size": [rgba.get_width(), rgba.get_height()],
		"origin": extra_meta.get("origin", "imported"),
		"provenance": extra_meta.get("provenance", default_provenance),
		"palette_ref": extra_meta.get("palette_ref", null),
		"anim": extra_meta.get("anim", null),
	}

	_metadata[asset_id] = meta
	_png_bytes[asset_id] = rgba.save_png_to_buffer()
	_store_in_cache(asset_id, rgba)
	_ref_counts[asset_id] = int(_ref_counts.get(asset_id, 0))

	asset_added.emit(asset_id)
	EventBus.asset_added.emit(asset_id)
	return asset_id


func load_from_zip_files(files: Dictionary) -> Error:
	clear()
	for file_name in files.keys():
		var path := String(file_name)
		if path.begins_with("assets/") and path.ends_with(".meta.json"):
			var meta: Variant = FileIOScript.bytes_to_json(files[file_name])
			if meta is Dictionary and meta.has("id"):
				_metadata[String(meta["id"])] = meta

	for asset_id in _metadata.keys():
		var png_path := "assets/%s.png" % asset_id
		if not files.has(png_path):
			Log.warn("Asset PNG missing from project", {"asset_id": asset_id})
			continue

		var bytes: PackedByteArray = files[png_path]
		_png_bytes[asset_id] = bytes
		var image := Image.new()
		var load_error := image.load_png_from_buffer(bytes)
		if load_error == OK:
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			_store_in_cache(asset_id, image)
		else:
			return load_error

	return OK


func export_zip_entries() -> Dictionary:
	var entries := {}
	for asset_id in _metadata.keys():
		entries["assets/%s.meta.json" % asset_id] = _metadata[asset_id]
		entries["assets/%s.png" % asset_id] = _png_bytes[asset_id]
	return entries


func has_asset(asset_id: String) -> bool:
	return _metadata.has(asset_id)


func get_image(asset_id: String) -> Image:
	if _image_cache.has(asset_id):
		_touch_lru(asset_id)
		return _image_cache[asset_id].duplicate()

	if not _png_bytes.has(asset_id):
		return null

	var image := Image.new()
	var error := image.load_png_from_buffer(_png_bytes[asset_id])
	if error != OK:
		Log.warn("Failed to decode asset PNG", {"asset_id": asset_id, "error": error})
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	_store_in_cache(asset_id, image)
	return image.duplicate()


func get_asset_meta(asset_id: String) -> Dictionary:
	return _metadata.get(asset_id, {}).duplicate(true)


func get_all_meta() -> Dictionary:
	return _metadata.duplicate(true)


func add_ref(asset_id: String) -> void:
	_ref_counts[asset_id] = int(_ref_counts.get(asset_id, 0)) + 1


func release_ref(asset_id: String) -> void:
	_ref_counts[asset_id] = maxi(0, int(_ref_counts.get(asset_id, 0)) - 1)


func get_ref_count(asset_id: String) -> int:
	return int(_ref_counts.get(asset_id, 0))


func get_cache_bytes() -> int:
	return _cache_bytes


func get_cache_limit_bytes() -> int:
	return _cache_limit_bytes


func configure_cache_limit(max_bytes: int) -> void:
	_cache_limit_bytes = maxi(1, max_bytes)
	_prune_cache()


func get_cached_asset_ids() -> Array:
	return _lru_order.duplicate()


func estimate_cache_bytes(image: Image) -> int:
	var rgba: Image = ImageMath.duplicate_rgba8(image)
	return ImageMath.estimate_rgba8_bytes(rgba)


func remove_asset(asset_id: String) -> Error:
	if get_ref_count(asset_id) > 0:
		return ERR_BUSY

	_metadata.erase(asset_id)
	_png_bytes.erase(asset_id)
	_remove_from_cache(asset_id)
	_ref_counts.erase(asset_id)
	asset_removed.emit(asset_id)
	EventBus.asset_removed.emit(asset_id)
	return OK


func _store_in_cache(asset_id: String, image: Image) -> void:
	_remove_from_cache(asset_id)
	var copy: Image = ImageMath.duplicate_rgba8(image)
	_image_cache[asset_id] = copy
	# 缓存统一保存 RGBA8 图像。width * height * 4 与 Image.get_data().size()
	# 的字节单位一致，但不会为计费额外创建 PackedByteArray。
	_cache_bytes += estimate_cache_bytes(copy)
	_touch_lru(asset_id)
	_prune_cache()


func _touch_lru(asset_id: String) -> void:
	_lru_order.erase(asset_id)
	_lru_order.append(asset_id)


func _remove_from_cache(asset_id: String) -> void:
	if not _image_cache.has(asset_id):
		return

	var old_image: Image = _image_cache[asset_id]
	_cache_bytes -= estimate_cache_bytes(old_image)
	_image_cache.erase(asset_id)
	_lru_order.erase(asset_id)
	_cache_bytes = maxi(0, _cache_bytes)


func _prune_cache() -> void:
	while _cache_bytes > _cache_limit_bytes and not _lru_order.is_empty():
		var oldest_id := String(_lru_order.pop_front())
		_remove_from_cache(oldest_id)
```

### `services/pf_project.gd`

```gdscript
class_name PFProject
extends RefCounted

## 内存项目模型。
## contract: 02-contracts/PROJECT-FORMAT.md；manifest/canvas 保持 Dictionary，方便和 JSON 一一对应。

const AppInfo := preload("res://core/util/app_info.gd")
const IdUtil := preload("res://core/util/id_util.gd")

var project_path := ""
var manifest := {}
var canvas := {}
var dirty := false


func reset(name: String = "Untitled") -> void:
	var now: String = IdUtil.utc_now_iso()
	manifest = {
		"format_version": AppInfo.PROJECT_FORMAT_VERSION,
		"app_version": AppInfo.APP_VERSION,
		"id": IdUtil.uuid_v4(),
		"name": name,
		"created_at": now,
		"modified_at": now,
		"style_preset": {},
		"entries":
		{
			"canvases": ["canvas"],
			"graphs": [],
			"boards": [],
			"asset_count": 0,
		},
	}
	canvas = {
		"camera":
		{
			"center": [0, 0],
			"zoom": 1.0,
		},
		"items": [],
	}
	project_path = ""
	dirty = false


func get_id() -> String:
	return String(manifest.get("id", "untitled"))


func get_name() -> String:
	return String(manifest.get("name", "Untitled"))


func set_dirty(value: bool) -> void:
	dirty = value
```

### `services/project_service.gd`

```gdscript
class_name PFProjectService
extends Node

## 项目服务。
## contract: 02-contracts/PROJECT-FORMAT.md；负责新建、保存、打开、自动保存和版本迁移框架。

signal project_loaded(project: Variant)
signal project_saved(path: String)
signal dirty_changed(is_dirty: bool)
signal recovery_available(autosaves: Array)

const AUTOSAVE_INTERVAL_SECONDS := 180.0
const AUTOSAVE_KEEP_COUNT := 5
const LOCK_PATH := "user://pixelforge_session.lock"
const ProjectModel := preload("res://services/pf_project.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const Log := preload("res://core/util/log_util.gd")
const MIGRATIONS: Array = []

var current_project: Variant = ProjectModel.new()

var _autosave_timer: Timer = null


func _ready() -> void:
	current_project.reset()
	_setup_autosave_timer()
	_check_recovery_state()
	_write_session_lock()


func new_project(name: String = "Untitled") -> void:
	AssetLibrary.clear()
	UndoService.clear()
	current_project.reset(name)
	project_loaded.emit(current_project)
	EventBus.project_created.emit(current_project.get_id())
	_emit_dirty(false)


func set_canvas_data(canvas_data: Dictionary, mark_dirty: bool = true) -> void:
	current_project.canvas = canvas_data.duplicate(true)
	if mark_dirty:
		_emit_dirty(true)
		EventBus.canvas_changed.emit()


func get_canvas_data() -> Dictionary:
	return current_project.canvas.duplicate(true)


func save_project(path: String = "") -> Error:
	var target_path := path
	if target_path.is_empty():
		target_path = current_project.project_path
	if target_path.is_empty():
		return ERR_FILE_BAD_PATH

	var error := _save_to_path(target_path)
	if error == OK:
		current_project.project_path = target_path
		SettingsService.add_recent_project(target_path)
		_emit_dirty(false)
		project_saved.emit(target_path)
		EventBus.project_saved.emit(target_path)
	return error


func open_project(path: String) -> Error:
	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	if not bool(unpacked.get("ok", false)):
		return int(unpacked.get("error", ERR_FILE_CANT_OPEN))

	var files: Dictionary = unpacked["files"]
	if not files.has("manifest.json") or not files.has("canvas/canvas.json"):
		return ERR_FILE_CORRUPT

	var manifest: Variant = FileIOScript.bytes_to_json(files["manifest.json"])
	var canvas: Variant = FileIOScript.bytes_to_json(files["canvas/canvas.json"])
	if not (manifest is Dictionary) or not (canvas is Dictionary):
		return ERR_PARSE_ERROR

	var migration_error := _migrate_manifest(manifest)
	if migration_error != OK:
		return migration_error

	_normalize_loaded_project(manifest, canvas)

	var asset_error := AssetLibrary.load_from_zip_files(files)
	if asset_error != OK:
		return asset_error

	current_project = ProjectModel.new()
	current_project.manifest = manifest
	current_project.canvas = canvas
	current_project.project_path = path
	current_project.dirty = false

	SettingsService.add_recent_project(path)
	UndoService.clear()
	project_loaded.emit(current_project)
	EventBus.project_opened.emit(path)
	_emit_dirty(false)
	return OK


func autosave_now() -> Error:
	if current_project.get_id().is_empty():
		return ERR_UNCONFIGURED

	var autosave_dir := "user://autosave/%s" % current_project.get_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(autosave_dir))
	var autosave_path := "%s/%s.pxproj" % [autosave_dir, IdUtil.filesystem_stamp()]
	var error := _save_to_path(autosave_path)
	if error == OK:
		_prune_autosaves(autosave_dir)
	return error


func list_autosaves(project_id: String = "") -> Array:
	var root := "user://autosave"
	var autosaves: Array = []
	var root_dir := DirAccess.open(root)
	if root_dir == null:
		return autosaves

	var project_dirs: Array = []
	if project_id.is_empty():
		project_dirs = root_dir.get_directories()
	else:
		project_dirs = [project_id]

	for dir_name in project_dirs:
		var autosave_dir := "%s/%s" % [root, dir_name]
		var dir := DirAccess.open(autosave_dir)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".pxproj"):
				autosaves.append("%s/%s" % [autosave_dir, file_name])

	autosaves.sort()
	return autosaves


func mark_clean_shutdown() -> void:
	if FileAccess.file_exists(LOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))


func _save_to_path(path: String) -> Error:
	_update_manifest_before_save()
	var entries := {
		"manifest.json": current_project.manifest,
		"canvas/canvas.json": current_project.canvas,
	}
	var asset_entries := AssetLibrary.export_zip_entries()
	for asset_path in asset_entries.keys():
		entries[asset_path] = asset_entries[asset_path]
	return FileIOScript.zip_pack(entries, path)


func _update_manifest_before_save() -> void:
	current_project.manifest["modified_at"] = IdUtil.utc_now_iso()
	current_project.manifest["app_version"] = AppInfo.APP_VERSION
	current_project.manifest["format_version"] = AppInfo.PROJECT_FORMAT_VERSION
	var entries: Dictionary = current_project.manifest.get("entries", {})
	entries["canvases"] = ["canvas"]
	entries["asset_count"] = AssetLibrary.get_all_meta().size()
	current_project.manifest["entries"] = entries


func _migrate_manifest(manifest: Dictionary) -> Error:
	var version := int(manifest.get("format_version", 0))
	if version <= 0:
		return ERR_FILE_CORRUPT
	if version > AppInfo.PROJECT_FORMAT_VERSION:
		return ERR_FILE_UNRECOGNIZED

	while version < AppInfo.PROJECT_FORMAT_VERSION:
		var migration_index := version - 1
		if migration_index < 0 or migration_index >= MIGRATIONS.size():
			return ERR_UNAVAILABLE
		var migration: Callable = MIGRATIONS[migration_index]
		manifest = migration.call(manifest)
		version = int(manifest.get("format_version", version + 1))

	return OK


func _normalize_loaded_project(manifest: Dictionary, canvas: Dictionary) -> void:
	manifest["format_version"] = int(manifest.get("format_version", AppInfo.PROJECT_FORMAT_VERSION))
	var entries: Dictionary = manifest.get("entries", {})
	entries["asset_count"] = int(entries.get("asset_count", 0))
	manifest["entries"] = entries

	var camera: Dictionary = canvas.get("camera", {})
	var center: Variant = camera.get("center", [0, 0])
	camera["center"] = [int(round(float(center[0]))), int(round(float(center[1])))]
	camera["zoom"] = float(camera.get("zoom", 1.0))
	canvas["camera"] = camera

	var normalized_items := []
	for item in canvas.get("items", []):
		if not (item is Dictionary):
			continue
		var item_data: Dictionary = item
		var position: Variant = item_data.get("position", [0, 0])
		item_data["position"] = [int(round(float(position[0]))), int(round(float(position[1])))]
		item_data["scale_factor"] = int(item_data.get("scale_factor", 1))
		item_data["z_index"] = int(item_data.get("z_index", 0))
		item_data["locked"] = bool(item_data.get("locked", false))
		normalized_items.append(item_data)
	canvas["items"] = normalized_items


func _emit_dirty(value: bool) -> void:
	if current_project.dirty == value:
		return
	current_project.set_dirty(value)
	dirty_changed.emit(value)
	EventBus.project_dirty_changed.emit(value)


func _setup_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)


func _on_autosave_timeout() -> void:
	if current_project.dirty:
		var error := autosave_now()
		if error != OK:
			Log.warn("Autosave failed", {"error": error})


func _check_recovery_state() -> void:
	if not FileAccess.file_exists(LOCK_PATH):
		return

	var autosaves := list_autosaves()
	if not autosaves.is_empty():
		recovery_available.emit(autosaves)
		EventBus.recovery_available.emit(autosaves)


func _write_session_lock() -> void:
	var file := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(IdUtil.utc_now_iso())


func _prune_autosaves(autosave_dir: String) -> void:
	var dir := DirAccess.open(autosave_dir)
	if dir == null:
		return

	var files := Array(dir.get_files())
	files.sort()
	while files.size() > AUTOSAVE_KEEP_COUNT:
		var file_name := String(files.pop_front())
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [autosave_dir, file_name])
		)
```

### `ui/shell/strings.gd`

```gdscript
class_name PFStrings
extends RefCounted

## UI 文案集中入口。
## v1.0 前界面先使用英文，后续 i18n 只需要替换这里和对应翻译资源。

const ACTION_NEW := "New"
const ACTION_OPEN := "Open"
const ACTION_SAVE := "Save"
const ACTION_SAVE_AS := "Save As"
const STATUS_READY := "Ready"
const STATUS_SAVED := "Saved"
const STATUS_DIRTY := "Unsaved changes"
const DIALOG_OPEN_PROJECT := "Open PixelForge Project"
const DIALOG_SAVE_PROJECT := "Save PixelForge Project"
const DIALOG_RECOVERY := "Recover Autosave"
```

### `ui/shell/main.gd`

```gdscript
class_name PFMain
extends Control

## 应用主窗口。
## UI 只负责命令分发和状态展示；项目状态由 ProjectService 管，画布状态由 PFInfiniteCanvas 管。

const Strings := preload("res://ui/shell/strings.gd")
const InfiniteCanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const Log := preload("res://core/util/log_util.gd")

const DEFAULT_WINDOW_WIDTH := 1440
const DEFAULT_WINDOW_HEIGHT := 900
const MIN_WINDOW_WIDTH := 1280
const MIN_WINDOW_HEIGHT := 800
const WINDOW_SCREEN_MARGIN := 80
const UI_FONT_SIZE := 16
const UI_SMALL_FONT_SIZE := 14
const MIN_INTERFACE_SCALE := 1.0
const MAX_INTERFACE_SCALE := 2.0
const RETINA_WIDTH_THRESHOLD := 4800
const RETINA_HEIGHT_THRESHOLD := 2800
const LARGE_DISPLAY_WIDTH_THRESHOLD := 3200
const LARGE_DISPLAY_HEIGHT_THRESHOLD := 1800
const TOP_BAR_HEIGHT := 48
const BOTTOM_BAR_HEIGHT := 32
const TOOLBAR_BUTTON_WIDTH := 84
const TOOLBAR_BUTTON_HEIGHT := 34

var _project_filters := PackedStringArray(["*.pxproj ; PixelForge Project"])
var _ui_scale := 1.0
var _canvas: Control = null
var _title_label: Label = null
var _status_label: Label = null
var _save_dialog: FileDialog = null
var _open_dialog: FileDialog = null
var _recovery_dialog: ConfirmationDialog = null
var _pending_recovery_path := ""


func _ready() -> void:
	_ui_scale = _resolve_interface_scale()
	_apply_viewport_scale_policy()
	_apply_runtime_theme()
	_apply_window_defaults()
	_build_ui()
	_connect_services()
	_update_window_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ProjectService.mark_clean_shutdown()
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.ctrl_pressed and event.keycode == KEY_S:
		_save_current_project()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_O:
		_open_dialog.popup_centered_ratio(0.7)
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_N:
		_create_new_project()
		get_viewport().set_input_as_handled()


static func compute_auto_interface_scale(reported_scale: float, usable_size: Vector2i) -> float:
	var scale := maxf(reported_scale, MIN_INTERFACE_SCALE)
	if scale < 1.25:
		if usable_size.x >= RETINA_WIDTH_THRESHOLD or usable_size.y >= RETINA_HEIGHT_THRESHOLD:
			scale = 2.0
		elif (
			usable_size.x >= LARGE_DISPLAY_WIDTH_THRESHOLD
			or usable_size.y >= LARGE_DISPLAY_HEIGHT_THRESHOLD
		):
			scale = 1.5
	return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)


func _resolve_interface_scale() -> float:
	var configured_scale := float(SettingsService.get_setting("ui", "interface_scale", 0.0))
	if configured_scale >= MIN_INTERFACE_SCALE:
		return clampf(configured_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)

	if DisplayServer.get_name() == "headless":
		return MIN_INTERFACE_SCALE

	var screen := DisplayServer.window_get_current_screen()
	var reported_scale := DisplayServer.screen_get_scale(screen)
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	return compute_auto_interface_scale(reported_scale, usable_rect.size)


func _apply_viewport_scale_policy() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_factor = 1.0
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _apply_runtime_theme() -> void:
	theme = _build_app_theme()


func _build_app_theme() -> Theme:
	var app_theme := Theme.new()
	app_theme.default_font_size = _scaled_int(UI_FONT_SIZE)

	for type_name in [
		"Button",
		"CheckBox",
		"ConfirmationDialog",
		"FileDialog",
		"ItemList",
		"Label",
		"LineEdit",
		"MenuButton",
		"OptionButton",
		"PopupMenu",
		"TabBar",
		"Tree",
		"Window",
	]:
		app_theme.set_font_size("font_size", type_name, _scaled_int(UI_FONT_SIZE))

	app_theme.set_font_size("font_size", "Button", _scaled_int(UI_SMALL_FONT_SIZE))
	app_theme.set_font_size("font_size", "PopupMenu", _scaled_int(UI_SMALL_FONT_SIZE))
	app_theme.set_constant("h_separation", "HBoxContainer", _scaled_int(8))
	app_theme.set_constant("v_separation", "VBoxContainer", 0)
	return app_theme


func _apply_window_defaults() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return

	window.min_size = _scaled_vec2i(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)
	var target_size := _scaled_vec2i(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT)
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable_rect.size.x > 0 and usable_rect.size.y > 0:
		var margin := _scaled_int(WINDOW_SCREEN_MARGIN)
		var max_width := maxi(_scaled_int(960), usable_rect.size.x - margin)
		var max_height := maxi(_scaled_int(640), usable_rect.size.y - margin)
		target_size.x = mini(target_size.x, max_width)
		target_size.y = mini(target_size.y, max_height)
		target_size.x = maxi(target_size.x, mini(window.min_size.x, max_width))
		target_size.y = maxi(target_size.y, mini(window.min_size.y, max_height))

		window.size = target_size
		window.position = usable_rect.position + (usable_rect.size - target_size) / 2
	else:
		window.size = target_size


func _build_ui() -> void:
	custom_minimum_size = _scaled_vec2(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(0, _scaled_int(TOP_BAR_HEIGHT))
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(top_bar)

	_title_label = Label.new()
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", _scaled_int(UI_FONT_SIZE))
	top_bar.add_child(_title_label)

	_add_toolbar_button(top_bar, Strings.ACTION_NEW, _create_new_project)
	_add_toolbar_button(
		top_bar, Strings.ACTION_OPEN, func() -> void: _open_dialog.popup_centered_ratio(0.7)
	)
	_add_toolbar_button(top_bar, Strings.ACTION_SAVE, _save_current_project)
	_add_toolbar_button(
		top_bar, Strings.ACTION_SAVE_AS, func() -> void: _save_dialog.popup_centered_ratio(0.7)
	)

	_canvas = InfiniteCanvasScript.new()
	_canvas.name = "InfiniteCanvas"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_canvas)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.custom_minimum_size = Vector2(0, _scaled_int(BOTTOM_BAR_HEIGHT))
	root.add_child(bottom_bar)

	_status_label = Label.new()
	_status_label.text = Strings.STATUS_READY
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", _scaled_int(UI_SMALL_FONT_SIZE))
	bottom_bar.add_child(_status_label)

	_create_file_dialogs()


func _add_toolbar_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = _scaled_vec2(TOOLBAR_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", _scaled_int(UI_SMALL_FONT_SIZE))
	button.pressed.connect(callback)
	parent.add_child(button)


func _scaled_int(value: int) -> int:
	return maxi(1, int(round(float(value) * _ui_scale)))


func _scaled_vec2(width: int, height: int) -> Vector2:
	return Vector2(_scaled_int(width), _scaled_int(height))


func _scaled_vec2i(width: int, height: int) -> Vector2i:
	return Vector2i(_scaled_int(width), _scaled_int(height))


func _create_file_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.title = Strings.DIALOG_OPEN_PROJECT
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = _project_filters
	_open_dialog.file_selected.connect(_open_project_path)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.title = Strings.DIALOG_SAVE_PROJECT
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = _project_filters
	_save_dialog.file_selected.connect(_save_project_path)
	add_child(_save_dialog)

	_recovery_dialog = ConfirmationDialog.new()
	_recovery_dialog.title = Strings.DIALOG_RECOVERY
	_recovery_dialog.confirmed.connect(_recover_pending_autosave)
	add_child(_recovery_dialog)


func _connect_services() -> void:
	_canvas.canvas_changed.connect(_on_canvas_changed)
	ProjectService.project_loaded.connect(_on_project_loaded)
	ProjectService.project_saved.connect(_on_project_saved)
	ProjectService.dirty_changed.connect(_on_dirty_changed)
	ProjectService.recovery_available.connect(_on_recovery_available)

	var window := get_window()
	if window != null:
		window.files_dropped.connect(_on_files_dropped)


func _create_new_project() -> void:
	ProjectService.new_project("Untitled")
	_canvas.clear_canvas()
	_status_label.text = Strings.STATUS_READY
	_update_window_title()


func _save_current_project() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	if ProjectService.current_project.project_path.is_empty():
		_save_dialog.current_file = "%s.pxproj" % ProjectService.current_project.get_name()
		_save_dialog.popup_centered_ratio(0.7)
		return

	var error := ProjectService.save_project()
	if error != OK:
		Log.warn("Project save failed", {"error": error})


func _save_project_path(path: String) -> void:
	var target_path := path
	if not target_path.ends_with(".pxproj"):
		target_path += ".pxproj"

	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	var error := ProjectService.save_project(target_path)
	if error != OK:
		Log.warn("Project save failed", {"path": target_path, "error": error})


func _open_project_path(path: String) -> void:
	var error := ProjectService.open_project(path)
	if error != OK:
		Log.warn("Project open failed", {"path": path, "error": error})


func _on_project_loaded(project: Variant) -> void:
	_canvas.load_canvas_data(project.canvas)
	_status_label.text = Strings.STATUS_READY
	_update_window_title()


func _on_project_saved(_path: String) -> void:
	_status_label.text = Strings.STATUS_SAVED
	_update_window_title()


func _on_dirty_changed(is_dirty: bool) -> void:
	_status_label.text = Strings.STATUS_DIRTY if is_dirty else Strings.STATUS_READY
	_update_window_title()


func _on_canvas_changed() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), true)


func _on_files_dropped(files: PackedStringArray) -> void:
	var drop_position: Vector2 = _canvas.get_mouse_world_position()
	for file_path in files:
		if not String(file_path).to_lower().ends_with(".png"):
			continue

		var image: Image = FileIOScript.load_png(file_path)
		if image == null:
			Log.warn("Dropped PNG could not be loaded", {"path": file_path})
			continue

		if image.get_width() * image.get_height() > 1024 * 1024:
			(
				Log
				. warn(
					"Large PNG imported without M1 cleanup",
					{
						"path": file_path,
						"size": [image.get_width(), image.get_height()],
					}
				)
			)

		var asset_name := String(file_path).get_file().get_basename()
		var asset_id := AssetLibrary.register_image(image, asset_name, {"origin": "imported"})
		_canvas.add_sprite_item(image, asset_id, drop_position)
		drop_position += Vector2(image.get_width() + 8, 0)


func _on_recovery_available(autosaves: Array) -> void:
	if autosaves.is_empty():
		return

	_pending_recovery_path = String(autosaves.back())
	_recovery_dialog.dialog_text = "Autosave found:\n%s" % _pending_recovery_path
	_recovery_dialog.popup_centered()


func _recover_pending_autosave() -> void:
	if _pending_recovery_path.is_empty():
		return
	_open_project_path(_pending_recovery_path)
	_pending_recovery_path = ""


func _update_window_title() -> void:
	var dirty_marker := "*" if ProjectService.current_project.dirty else ""
	var project_name: String = ProjectService.current_project.get_name()
	var title := "%s%s - %s" % [dirty_marker, project_name, AppInfo.APP_NAME]
	_title_label.text = "%s  %s" % [AppInfo.APP_NAME, dirty_marker]

	var window := get_window()
	if window != null:
		window.title = title
```

### `ui/shell/main.tscn`

```ini
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://ui/shell/main.gd" id="1_main"]

[node name="Main" type="Control"]
layout_mode=3
anchors_preset=15
anchor_right=1.0
anchor_bottom=1.0
grow_horizontal=2
grow_vertical=2
custom_minimum_size=Vector2(1280, 800)
script=ExtResource("1_main")
```

### `ui/canvas/canvas_item_sprite.gd`

```gdscript
class_name PFCanvasItemSprite
extends Sprite2D

## 无限画布上的 sprite 元素。
## contract: 02-contracts/PROJECT-FORMAT.md §4；position 始终是整数世界坐标，texture_filter 始终最近邻。

const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")

var item_id := ""
var asset_id := ""
var scale_factor := 1
var locked := false
var frame_id: Variant = null
var source_image: Image = null


func setup_from_image(item_data: Dictionary, image: Image) -> void:
	item_id = String(item_data.get("id", IdUtil.uuid_v4()))
	asset_id = String(item_data.get("asset_id", ""))
	scale_factor = maxi(1, int(item_data.get("scale_factor", 1)))
	locked = bool(item_data.get("locked", false))
	frame_id = item_data.get("frame_id", null)
	z_index = int(item_data.get("z_index", 0))

	var raw_position: Variant = item_data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	scale = Vector2.ONE * float(scale_factor)
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	source_image = ImageMath.duplicate_rgba8(image)
	texture = ImageTexture.create_from_image(source_image)


func get_canvas_bounds() -> Rect2:
	if source_image == null:
		return Rect2(position, Vector2.ZERO)
	return Rect2(
		position, Vector2(source_image.get_width(), source_image.get_height()) * float(scale_factor)
	)


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func to_canvas_data() -> Dictionary:
	return {
		"id": item_id,
		"type": "sprite",
		"asset_id": asset_id,
		"position": [int(round(position.x)), int(round(position.y))],
		"scale_factor": scale_factor,
		"z_index": z_index,
		"locked": locked,
		"frame_id": frame_id,
	}


func duplicate_image() -> Image:
	if source_image == null:
		return null
	return source_image.duplicate()
```

### `ui/canvas/canvas_item_frame.gd`

```gdscript
class_name PFCanvasItemFrame
extends Node2D

## M0 只实现 sprite 元素；frame 在 M3/M5 扩展。
## 保留脚本是为了让目录和未来项目格式中的 frame_id 有稳定落点。
## 当前脚本不承担运行时行为；后续加入地图构图或节点锚点时再扩展字段和绘制逻辑。

var frame_id := ""
```

### `ui/canvas/canvas_selection.gd`

```gdscript
class_name PFCanvasSelection
extends RefCounted

## 画布选择状态容器。
## InfiniteCanvas 负责坐标和绘制，本类只保存选择、拖拽和框选状态，避免交互状态继续堆在主画布脚本中。

signal selection_changed(selected_ids: Array)

var selected_ids: Array = []
var is_dragging_items := false
var is_box_selecting := false
var box_additive := false
var drag_start_world := Vector2.ZERO
var drag_start_positions := {}
var box_start_screen := Vector2.ZERO
var box_end_screen := Vector2.ZERO


func get_selected_ids() -> Array:
	return selected_ids.duplicate()


func is_empty() -> bool:
	return selected_ids.is_empty()


func has(item_id: String) -> bool:
	return selected_ids.has(item_id)


func select_only(ids: Array, available_ids: Array) -> void:
	selected_ids = _filter_ids(ids, available_ids)
	selection_changed.emit(get_selected_ids())


func clear(notify: bool = true) -> void:
	selected_ids.clear()
	if notify:
		selection_changed.emit([])


func remove_item_reference(item_id: String) -> void:
	selected_ids.erase(item_id)


func toggle(item_id: String, available_ids: Array) -> void:
	if not available_ids.has(item_id):
		return
	if selected_ids.has(item_id):
		selected_ids.erase(item_id)
	else:
		selected_ids.append(item_id)
	selection_changed.emit(get_selected_ids())


func start_drag(world_position: Vector2, start_positions: Dictionary) -> void:
	is_dragging_items = true
	drag_start_world = world_position
	drag_start_positions = start_positions.duplicate(true)


func stop_drag() -> void:
	is_dragging_items = false
	drag_start_positions.clear()


func start_box(screen_position: Vector2, additive: bool) -> void:
	is_box_selecting = true
	box_additive = additive
	box_start_screen = screen_position
	box_end_screen = screen_position


func update_box(screen_position: Vector2) -> void:
	box_end_screen = screen_position


func stop_box() -> void:
	is_box_selecting = false


func get_box_rect() -> Rect2:
	return Rect2(box_start_screen, box_end_screen - box_start_screen).abs()


func _filter_ids(ids: Array, available_ids: Array) -> Array:
	var filtered := []
	for item_id in ids:
		var normalized_id := String(item_id)
		if available_ids.has(normalized_id) and not filtered.has(normalized_id):
			filtered.append(normalized_id)
	return filtered
```

### `ui/canvas/infinite_canvas.gd`

```gdscript
class_name PFInfiniteCanvas
extends Control

## 无限画布核心交互。
## 职责：平移、缩放、sprite 元素增删选移、框选、网格和视口剔除；保存格式直接导出 canvas.json 结构。

signal canvas_changed
signal selection_changed(selected_ids: Array)

const ZOOM_LEVELS := [0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]
const DEFAULT_ZOOM_INDEX := 3
const CULL_INTERVAL_SECONDS := 0.1
const CULL_PADDING_PIXELS := 128.0
const GRID_MIN_ZOOM := 4.0
const SELECTION_COLOR := Color(0.1, 0.85, 0.65, 1.0)
const BOX_COLOR := Color(1.0, 0.85, 0.25, 0.35)
const BACKGROUND_COLOR := Color(0.105, 0.11, 0.12, 1.0)
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")
const Log := preload("res://core/util/log_util.gd")

var camera_center := Vector2.ZERO
var zoom_index := DEFAULT_ZOOM_INDEX
var camera_zoom := float(ZOOM_LEVELS[DEFAULT_ZOOM_INDEX])

var item_layer := Node2D.new()

var _items_by_id := {}
var _selection: Variant = CanvasSelectionScript.new()
var _is_panning := false
var _last_mouse_position := Vector2.ZERO
var _cull_elapsed := 0.0
var _suppress_change_signal := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection.selection_changed.connect(_on_selection_changed)

	item_layer.name = "ItemLayer"
	item_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(item_layer)

	_update_layer_transform()
	set_process(true)


func _process(delta: float) -> void:
	_cull_elapsed += delta
	if _cull_elapsed >= CULL_INTERVAL_SECONDS:
		_cull_elapsed = 0.0
		_update_item_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layer_transform()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventPanGesture:
		pan_by_pixels(event.delta)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		delete_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Z and event.ctrl_pressed:
		if event.shift_pressed:
			UndoService.redo()
		else:
			UndoService.undo()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	if camera_zoom >= GRID_MIN_ZOOM:
		_draw_pixel_grid()

	for item_id in _selection.selected_ids:
		if not _items_by_id.has(item_id):
			continue
		var item: Node = _items_by_id[item_id]
		var screen_rect := _world_rect_to_screen(item.get_canvas_bounds())
		draw_rect(screen_rect.grow(2.0), SELECTION_COLOR, false, 2.0)

	if _selection.is_box_selecting:
		var box: Rect2 = _selection.get_box_rect()
		draw_rect(box, BOX_COLOR, true)
		draw_rect(box, Color(1.0, 0.85, 0.25, 1.0), false, 1.0)

	var font := get_theme_default_font()
	if font != null:
		var font_size := maxi(12, get_theme_font_size("font_size", "Label") - 2)
		draw_string(
			font,
			Vector2(12, size.y - float(font_size + 3)),
			"%d%%" % int(round(camera_zoom * 100.0)),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.82, 0.84, 0.84, 1.0)
		)


func add_sprite_item(
	image: Image,
	asset_id: String = "",
	world_position: Vector2 = Vector2.ZERO,
	item_id: String = "",
	record_undo: bool = true
) -> Node:
	var data := {
		"id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
		"type": "sprite",
		"asset_id": asset_id,
		"position": [int(round(world_position.x)), int(round(world_position.y))],
		"scale_factor": 1,
		"z_index": _items_by_id.size(),
		"locked": false,
		"frame_id": null,
	}
	var image_copy: Image = ImageMath.duplicate_rgba8(image)

	var do_add := func() -> void:
		_add_sprite_direct(data, image_copy)
		_select_only([String(data["id"])])
		_emit_canvas_changed()

	var undo_add := func() -> void:
		_remove_item_direct(String(data["id"]))
		_clear_selection()
		_emit_canvas_changed()

	if record_undo:
		UndoService.perform_action(
			"Add sprite", do_add, undo_add, ImageMath.estimate_rgba8_bytes(image_copy)
		)
	else:
		do_add.call()

	return _items_by_id.get(String(data["id"]), null)


func delete_selected(record_undo: bool = true) -> void:
	if _selection.is_empty():
		return

	var snapshots := []
	for item_id in _selection.get_selected_ids():
		if not _items_by_id.has(item_id):
			continue
		var item: Node = _items_by_id[item_id]
		(
			snapshots
			. append(
				{
					"data": item.to_canvas_data(),
					"image": item.duplicate_image(),
				}
			)
		)

	if snapshots.is_empty():
		return

	var do_delete := func() -> void:
		for snapshot in snapshots:
			_remove_item_direct(String(snapshot["data"]["id"]))
		_clear_selection()
		_emit_canvas_changed()

	var undo_delete := func() -> void:
		for snapshot in snapshots:
			_add_sprite_direct(snapshot["data"], snapshot["image"])
		_select_only(_ids_from_snapshots(snapshots))
		_emit_canvas_changed()

	var memory_cost := 0
	for snapshot in snapshots:
		memory_cost += ImageMath.estimate_rgba8_bytes(snapshot["image"])

	if record_undo:
		UndoService.perform_action("Delete sprite", do_delete, undo_delete, memory_cost)
	else:
		do_delete.call()


func clear_canvas() -> void:
	_suppress_change_signal = true
	for item in _items_by_id.values():
		item.queue_free()
	_items_by_id.clear()
	_selection.clear(false)
	_suppress_change_signal = false
	queue_redraw()


func load_canvas_data(canvas_data: Dictionary) -> void:
	clear_canvas()
	_suppress_change_signal = true

	var camera: Dictionary = canvas_data.get("camera", {})
	var center: Variant = camera.get("center", [0, 0])
	camera_center = Vector2(float(center[0]), float(center[1]))
	_set_zoom_to_value(float(camera.get("zoom", 1.0)))

	for item_data in canvas_data.get("items", []):
		if String(item_data.get("type", "")) != "sprite":
			continue
		var asset_id := String(item_data.get("asset_id", ""))
		var image := AssetLibrary.get_image(asset_id)
		if image == null:
			Log.warn("Canvas item skipped because asset image is missing", {"asset_id": asset_id})
			continue
		_add_sprite_direct(item_data, image)

	_suppress_change_signal = false
	_update_layer_transform()
	_update_item_visibility()
	queue_redraw()


func export_canvas_data() -> Dictionary:
	var items := []
	var nodes := item_layer.get_children()
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return a.z_index < b.z_index)

	for node in nodes:
		if node.get_script() == CanvasItemSpriteScript:
			items.append(node.to_canvas_data())

	return {
		"camera":
		{
			"center": [int(round(camera_center.x)), int(round(camera_center.y))],
			"zoom": camera_zoom,
		},
		"items": items,
	}


func screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_center + (screen_position - size * 0.5) / camera_zoom


func world_to_screen(world_position: Vector2) -> Vector2:
	return size * 0.5 + (world_position - camera_center) * camera_zoom


func get_mouse_world_position() -> Vector2:
	return screen_to_world(get_local_mouse_position()).round()


func pan_by_pixels(pixel_delta: Vector2) -> void:
	camera_center += pixel_delta / camera_zoom
	_update_layer_transform()
	_emit_canvas_changed()


func set_camera_zoom(value: float, screen_anchor: Vector2 = size * 0.5) -> void:
	_set_zoom_to_value(value)
	var anchor_world := screen_to_world(screen_anchor)
	camera_center = anchor_world - (screen_anchor - size * 0.5) / camera_zoom
	_update_layer_transform()
	_emit_canvas_changed()


func zoom_by_steps(step_delta: int, screen_anchor: Vector2) -> void:
	var old_zoom := camera_zoom
	var anchor_world := screen_to_world(screen_anchor)
	zoom_index = clampi(zoom_index + step_delta, 0, ZOOM_LEVELS.size() - 1)
	camera_zoom = float(ZOOM_LEVELS[zoom_index])
	if is_equal_approx(old_zoom, camera_zoom):
		return
	camera_center = anchor_world - (screen_anchor - size * 0.5) / camera_zoom
	_update_layer_transform()
	_emit_canvas_changed()


func get_item_count() -> int:
	return _items_by_id.size()


func get_selected_ids() -> Array:
	return _selection.get_selected_ids()


func select_ids(ids: Array) -> void:
	_select_only(ids)


func move_selected_by(delta: Vector2, record_undo: bool = true) -> void:
	if _selection.is_empty():
		return

	var before := _selected_positions()
	var after := {}
	var snapped_delta := delta.round()
	for item_id in before.keys():
		after[item_id] = (Vector2(before[item_id]) + snapped_delta).round()

	if _positions_equal(before, after):
		return

	var ids: Array = _selection.get_selected_ids()
	var do_move := func() -> void:
		_apply_positions(after)
		_select_only(ids)
		_emit_canvas_changed()

	var undo_move := func() -> void:
		_apply_positions(before)
		_select_only(ids)
		_emit_canvas_changed()

	if record_undo:
		UndoService.perform_action("Move sprite", do_move, undo_move)
	else:
		do_move.call()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		zoom_by_steps(1, event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		zoom_by_steps(-1, event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_panning = event.pressed
		_last_mouse_position = event.position
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if Input.is_key_pressed(KEY_SPACE):
			_is_panning = event.pressed
			_last_mouse_position = event.position
		elif event.pressed:
			_begin_left_interaction(event.position, event.shift_pressed)
		else:
			_finish_left_interaction(event.position)
		accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		pan_by_pixels(-event.relative)
		_last_mouse_position = event.position
		accept_event()
	elif _selection.is_dragging_items:
		_drag_selected_to(screen_to_world(event.position))
		accept_event()
	elif _selection.is_box_selecting:
		_selection.update_box(event.position)
		queue_redraw()
		accept_event()


func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
	var world_position := screen_to_world(screen_position)
	var hit_item := _item_at_world(world_position)
	if hit_item != null:
		if additive:
			_selection.toggle(hit_item.item_id, _items_by_id.keys())
		elif not _selection.has(hit_item.item_id):
			_select_only([hit_item.item_id])

		if _selection.has(hit_item.item_id):
			_selection.start_drag(world_position, _selected_positions())
	else:
		if not additive:
			_clear_selection()
		_selection.start_box(screen_position, additive)
	queue_redraw()


func _finish_left_interaction(screen_position: Vector2) -> void:
	if _selection.is_dragging_items:
		_commit_drag_if_needed()
		_selection.stop_drag()
	elif _selection.is_box_selecting:
		_selection.update_box(screen_position)
		_finish_box_selection()
		_selection.stop_box()

	queue_redraw()


func _drag_selected_to(world_position: Vector2) -> void:
	var delta: Vector2 = (world_position - _selection.drag_start_world).round()
	for item_id in _selection.get_selected_ids():
		if _items_by_id.has(item_id) and _selection.drag_start_positions.has(item_id):
			var item: Node = _items_by_id[item_id]
			if not item.locked:
				item.position = (_selection.drag_start_positions[item_id] + delta).round()
	queue_redraw()


func _commit_drag_if_needed() -> void:
	var after_positions := _selected_positions()
	if _positions_equal(_selection.drag_start_positions, after_positions):
		return

	var before: Dictionary = _selection.drag_start_positions.duplicate(true)
	var after: Dictionary = after_positions.duplicate(true)
	var ids: Array = _selection.get_selected_ids()

	var do_move := func() -> void:
		_apply_positions(after)
		_select_only(ids)
		_emit_canvas_changed()

	var undo_move := func() -> void:
		_apply_positions(before)
		_select_only(ids)
		_emit_canvas_changed()

	UndoService.perform_action("Move sprite", do_move, undo_move, 0, false)
	_emit_canvas_changed()


func _finish_box_selection() -> void:
	var screen_box: Rect2 = _selection.get_box_rect()
	var world_a := screen_to_world(screen_box.position)
	var world_b := screen_to_world(screen_box.position + screen_box.size)
	var world_box := Rect2(world_a, world_b - world_a).abs()

	var selected: Array = _selection.get_selected_ids() if _selection.box_additive else []
	for item in _items_by_id.values():
		if world_box.intersects(item.get_canvas_bounds()):
			if not selected.has(item.item_id):
				selected.append(item.item_id)
	_select_only(selected)


func _add_sprite_direct(item_data: Dictionary, image: Image) -> Node:
	var item: Node = CanvasItemSpriteScript.new()
	item.setup_from_image(item_data, image)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	if not item.asset_id.is_empty():
		AssetLibrary.add_ref(item.asset_id)
	_update_item_visibility()
	queue_redraw()
	return item


func _remove_item_direct(item_id: String) -> void:
	if not _items_by_id.has(item_id):
		return

	var item: Node = _items_by_id[item_id]
	if not item.asset_id.is_empty():
		AssetLibrary.release_ref(item.asset_id)
	_items_by_id.erase(item_id)
	_selection.remove_item_reference(item_id)
	item_layer.remove_child(item)
	item.free()
	queue_redraw()


func _item_at_world(world_position: Vector2) -> Node:
	var children := item_layer.get_children()
	for index in range(children.size() - 1, -1, -1):
		var item := children[index]
		if (
			item.get_script() == CanvasItemSpriteScript
			and item.visible
			and item.contains_world_point(world_position)
		):
			return item
	return null


func _selected_positions() -> Dictionary:
	var positions := {}
	for item_id in _selection.get_selected_ids():
		if _items_by_id.has(item_id):
			positions[item_id] = _items_by_id[item_id].position
	return positions


func _apply_positions(positions: Dictionary) -> void:
	for item_id in positions.keys():
		if _items_by_id.has(item_id):
			_items_by_id[item_id].position = Vector2(positions[item_id]).round()
	queue_redraw()


func _positions_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for item_id in left.keys():
		if not right.has(item_id):
			return false
		if Vector2(left[item_id]) != Vector2(right[item_id]):
			return false
	return true


func _select_only(ids: Array) -> void:
	_selection.select_only(ids, _items_by_id.keys())


func _clear_selection() -> void:
	_selection.clear()


func _ids_from_snapshots(snapshots: Array) -> Array:
	var ids := []
	for snapshot in snapshots:
		ids.append(String(snapshot["data"]["id"]))
	return ids


func _set_zoom_to_value(value: float) -> void:
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(ZOOM_LEVELS.size()):
		var distance := absf(float(ZOOM_LEVELS[index]) - value)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	zoom_index = nearest_index
	camera_zoom = float(ZOOM_LEVELS[zoom_index])


func _update_layer_transform() -> void:
	item_layer.position = size * 0.5 - camera_center * camera_zoom
	item_layer.scale = Vector2.ONE * camera_zoom
	queue_redraw()


func _update_item_visibility() -> void:
	var visible_world := Rect2(
		screen_to_world(Vector2.ZERO) - Vector2.ONE * CULL_PADDING_PIXELS / camera_zoom,
		size / camera_zoom + Vector2.ONE * CULL_PADDING_PIXELS * 2.0 / camera_zoom
	)
	for item in _items_by_id.values():
		var is_visible := visible_world.intersects(item.get_canvas_bounds())
		item.visible = is_visible
		item.set_process(is_visible)
		item.set_physics_process(is_visible)


func _world_rect_to_screen(world_rect: Rect2) -> Rect2:
	var position_screen := world_to_screen(world_rect.position)
	return Rect2(position_screen, world_rect.size * camera_zoom)


func _draw_pixel_grid() -> void:
	var top_left := screen_to_world(Vector2.ZERO)
	var bottom_right := screen_to_world(size)
	var start_x := floori(top_left.x)
	var end_x := ceili(bottom_right.x)
	var start_y := floori(top_left.y)
	var end_y := ceili(bottom_right.y)
	var color := Color(1.0, 1.0, 1.0, 0.08)

	for x in range(start_x, end_x + 1):
		var screen_x := world_to_screen(Vector2(float(x), 0.0)).x
		draw_line(Vector2(screen_x, 0.0), Vector2(screen_x, size.y), color, 1.0)

	for y in range(start_y, end_y + 1):
		var screen_y := world_to_screen(Vector2(0.0, float(y))).y
		draw_line(Vector2(0.0, screen_y), Vector2(size.x, screen_y), color, 1.0)


func _emit_canvas_changed() -> void:
	if _suppress_change_signal:
		return
	canvas_changed.emit()


func _on_selection_changed(selected_ids: Array) -> void:
	selection_changed.emit(selected_ids.duplicate())
	queue_redraw()
```

### `tests/unit/test_sanity.gd`

```gdscript
extends "res://addons/gut/test.gd"


func test_math_sanity() -> void:
	assert_eq(1 + 1, 2)
```

### `tests/unit/test_file_io.gd`

```gdscript
extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const ImageMath := preload("res://core/util/image_math.gd")


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))


func test_png_round_trip_keeps_pixels() -> void:
	var image := _make_test_image()
	var path := "user://tests/file_io_roundtrip.png"

	assert_eq(FileIOScript.save_png(image, path), OK)
	var loaded: Image = FileIOScript.load_png(path)

	assert_not_null(loaded)
	assert_eq(loaded.get_size(), image.get_size())
	assert_eq(ImageMath.color_set(loaded), ImageMath.color_set(image))


func test_zip_pack_and_unpack_keeps_content() -> void:
	var bytes := PackedByteArray()
	bytes.append(1)
	bytes.append(2)
	bytes.append(3)

	var path := "user://tests/file_io_zip.pxproj"
	var pack := {
		"manifest.json": {"name": "zip-test"},
		"nested/data.bin": bytes,
		"readme.txt": "hello",
	}

	assert_eq(FileIOScript.zip_pack(pack, path), OK)
	var unpacked: Dictionary = FileIOScript.zip_unpack(path)

	assert_true(unpacked["ok"])
	assert_eq(FileIOScript.bytes_to_json(unpacked["files"]["manifest.json"])["name"], "zip-test")
	assert_eq(unpacked["files"]["nested/data.bin"], bytes)
	assert_eq(unpacked["files"]["readme.txt"].get_string_from_utf8(), "hello")


func test_atomic_write_tmp_does_not_damage_original() -> void:
	var path := "user://tests/atomic_write.txt"
	assert_eq(FileIOScript.atomic_write(path, "old".to_utf8_buffer()), OK)

	var interrupted_tmp := FileAccess.open(path + ".manual-tmp", FileAccess.WRITE)
	interrupted_tmp.store_string("new")
	interrupted_tmp.close()

	var original := FileAccess.open(path, FileAccess.READ)
	assert_eq(original.get_as_text(), "old")

	assert_eq(FileIOScript.atomic_write(path, "new".to_utf8_buffer()), OK)
	var updated := FileAccess.open(path, FileAccess.READ)
	assert_eq(updated.get_as_text(), "new")


func test_logger_creates_date_file() -> void:
	var logger := get_tree().root.get_node("Logger")
	logger.info("test logger file creation")
	assert_true(FileAccess.file_exists(logger.get_current_log_path()))


func test_logger_prunes_logs_older_than_retention_days() -> void:
	var logger := get_tree().root.get_node("Logger")
	var old_path := "user://logs/app_2026-06-01.log"
	var recent_path := "user://logs/app_2026-06-10.log"
	assert_eq(FileIOScript.atomic_write(old_path, "old".to_utf8_buffer()), OK)
	assert_eq(FileIOScript.atomic_write(recent_path, "recent".to_utf8_buffer()), OK)

	var now := (
		Time
		. get_unix_time_from_datetime_dict(
			{
				"year": 2026,
				"month": 6,
				"day": 12,
				"hour": 0,
				"minute": 0,
				"second": 0,
			}
		)
	)
	logger.cleanup_old_logs(now)

	assert_false(FileAccess.file_exists(old_path))
	assert_true(FileAccess.file_exists(recent_path))


func _make_test_image() -> Image:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.RED)
	image.set_pixel(1, 0, Color.GREEN)
	image.set_pixel(0, 1, Color.BLUE)
	image.set_pixel(1, 1, Color.TRANSPARENT)
	return image
```

### `tests/unit/test_task_queue.gd`

```gdscript
extends "res://addons/gut/test.gd"

const TaskScript := preload("res://services/pf_task.gd")


func before_each() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	queue.clear()
	queue.set_max_concurrency(2)


func test_sleep_tasks_finish_in_submission_order() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished := []
	var on_finished := func(_task_id: String, result: Variant) -> void: finished.append(result)

	queue.task_finished.connect(on_finished)
	for index in range(10):
		var task := TaskScript.new(
			"sleep",
			{"index": index},
			func(task_ref: Variant) -> Variant:
				OS.delay_msec(10)
				return task_ref.payload["index"]
		)
		queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return finished.size() == 10))
	assert_eq(finished, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	queue.task_finished.disconnect(on_finished)


func test_cancelled_task_does_not_emit_finished() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished_ids := []
	var canceled_ids := []
	var on_finished := func(task_id: String, _result: Variant) -> void: finished_ids.append(task_id)
	var on_canceled := func(task_id: String) -> void: canceled_ids.append(task_id)

	queue.task_finished.connect(on_finished)
	queue.task_canceled.connect(on_canceled)

	var task := TaskScript.new(
		"slow",
		{},
		func(_task_ref: Variant) -> Variant:
			OS.delay_msec(80)
			return "done"
	)
	queue.submit(task)
	queue.cancel(task.id)

	assert_false(queue.is_idle())
	assert_eq(queue.get_running_count(), 1)
	assert_false(canceled_ids.has(task.id))

	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_false(finished_ids.has(task.id))
	assert_true(canceled_ids.has(task.id))

	queue.task_finished.disconnect(on_finished)
	queue.task_canceled.disconnect(on_canceled)


func test_running_cancel_finishes_as_canceled_and_returns_to_idle() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished_ids := []
	var canceled_ids := []
	var on_finished := func(task_id: String, _result: Variant) -> void: finished_ids.append(task_id)
	var on_canceled := func(task_id: String) -> void: canceled_ids.append(task_id)

	queue.task_finished.connect(on_finished)
	queue.task_canceled.connect(on_canceled)

	var task := TaskScript.new(
		"cancel-full-path",
		{},
		func(_task_ref: Variant) -> Variant:
			OS.delay_msec(120)
			return "worker returned after cancel"
	)
	queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return queue.get_running_count() == 1))
	queue.cancel(task.id)

	assert_false(queue.is_idle())
	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_eq(finished_ids, [])
	assert_eq(canceled_ids, [task.id])

	queue.task_finished.disconnect(on_finished)
	queue.task_canceled.disconnect(on_canceled)


func test_progress_signal_is_emitted_on_main_thread() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var main_thread_id: String = queue.get_main_thread_id()
	var progress_thread_ids := []
	var on_progress := func(_task_id: String, _ratio: float, _message: String) -> void:
		progress_thread_ids.append(str(OS.get_thread_caller_id()))

	queue.task_progressed.connect(on_progress)

	var task := TaskScript.new(
		"progress",
		{},
		func(task_ref: Variant) -> Variant:
			task_ref.report_progress(0.5, "half")
			OS.delay_msec(20)
			return "ok"
	)
	queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_gt(progress_thread_ids.size(), 0)
	for thread_id in progress_thread_ids:
		assert_eq(thread_id, main_thread_id)

	queue.task_progressed.disconnect(on_progress)


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.05)
		elapsed += 0.05
	return false
```

### `tests/unit/test_undo_service.gd`

```gdscript
extends "res://addons/gut/test.gd"


class Counter:
	var value := 0


func before_each() -> void:
	var undo := get_tree().root.get_node("UndoService")
	undo.clear()
	undo.reset_limits()


func test_undo_redo_50_lightweight_actions() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var counter := Counter.new()

	for _index in range(50):
		undo.perform_action(
			"increment", func() -> void: counter.value += 1, func() -> void: counter.value -= 1, 4
		)

	assert_eq(counter.value, 50)
	assert_eq(undo.get_undo_count(), 50)

	for _index in range(50):
		assert_true(undo.undo())
	assert_eq(counter.value, 0)

	for _index in range(50):
		assert_true(undo.redo())
	assert_eq(counter.value, 50)


func test_undo_memory_limit_drops_oldest_actions() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var counter := Counter.new()
	undo.configure_limits(100, 10)

	for _index in range(5):
		undo.perform_action(
			"costly increment",
			func() -> void: counter.value += 1,
			func() -> void: counter.value -= 1,
			4
		)

	assert_lte(undo.get_memory_bytes(), 10)
	assert_lte(undo.get_undo_count(), 2)
	undo.reset_limits()


func test_snapshot_region_returns_expected_pixels() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(2, 2, Color.WHITE)

	var snapshot: Image = undo.snapshot_region(image, Rect2i(2, 2, 1, 1))
	assert_eq(snapshot.get_size(), Vector2i.ONE)
	assert_eq(snapshot.get_pixel(0, 0), Color.WHITE)
```

### `tests/unit/test_asset_library.gd`

```gdscript
extends "res://addons/gut/test.gd"


func before_each() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	asset_library.clear()


func test_cache_byte_estimate_matches_rgba8_buffer_size() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var source := Image.create(4, 3, false, Image.FORMAT_RGB8)
	source.fill(Color(0.25, 0.5, 0.75, 1.0))

	var rgba := source.duplicate()
	rgba.convert(Image.FORMAT_RGBA8)

	assert_eq(asset_library.estimate_cache_bytes(source), rgba.get_data().size())


func test_registered_image_cache_counts_rgba8_bytes() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)

	asset_library.register_image(image, "cache-bytes")

	assert_eq(asset_library.get_cache_bytes(), image.get_data().size())


func test_cache_eviction_uses_least_recently_used_order() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	asset_library.configure_cache_limit(image.get_data().size() * 2)

	var first_id: String = asset_library.register_image(image, "first")
	var second_id: String = asset_library.register_image(image, "second")
	assert_eq(asset_library.get_cached_asset_ids(), [first_id, second_id])

	assert_not_null(asset_library.get_image(first_id))
	var third_id: String = asset_library.register_image(image, "third")

	assert_eq(asset_library.get_cached_asset_ids(), [first_id, third_id])
	assert_false(asset_library.get_cached_asset_ids().has(second_id))
```

### `tests/unit/test_canvas_selection.gd`

```gdscript
extends "res://addons/gut/test.gd"

const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")


func test_select_only_filters_duplicates_and_missing_ids() -> void:
	var selection := CanvasSelectionScript.new()

	selection.select_only(["a", "b", "a", "missing"], ["a", "b"])

	assert_eq(selection.get_selected_ids(), ["a", "b"])


func test_toggle_updates_selection_state() -> void:
	var selection := CanvasSelectionScript.new()

	selection.toggle("a", ["a", "b"])
	selection.toggle("missing", ["a", "b"])
	selection.toggle("a", ["a", "b"])

	assert_true(selection.is_empty())


func test_drag_and_box_state_are_separated_from_selected_ids() -> void:
	var selection := CanvasSelectionScript.new()
	selection.select_only(["sprite_1"], ["sprite_1"])

	selection.start_drag(Vector2(4, 8), {"sprite_1": Vector2(1, 2)})
	assert_true(selection.is_dragging_items)
	assert_eq(selection.drag_start_world, Vector2(4, 8))
	assert_eq(selection.drag_start_positions["sprite_1"], Vector2(1, 2))
	selection.stop_drag()
	assert_false(selection.is_dragging_items)

	selection.start_box(Vector2(10, 20), true)
	selection.update_box(Vector2(30, 40))
	assert_true(selection.is_box_selecting)
	assert_true(selection.box_additive)
	assert_eq(selection.get_box_rect(), Rect2(Vector2(10, 20), Vector2(20, 20)))
```

### `tests/unit/test_infra_clients.gd`

```gdscript
extends "res://addons/gut/test.gd"

const HttpClientScript := preload("res://infra/http_client.gd")
const WsClientScript := preload("res://infra/ws_client.gd")


func test_http_client_stub_keeps_m4_result_shape() -> void:
	var client := HttpClientScript.new()
	var result: Dictionary = client.request_json(
		"https://example.test/api",
		HTTPClient.METHOD_POST,
		PackedStringArray(["Content-Type: application/json"]),
		{"hello": "world"},
		5.0
	)

	assert_false(result["ok"])
	assert_eq(result["status_code"], 0)
	assert_true(result.has("headers"))
	assert_true(result.has("body"))
	assert_eq(result["url"], "https://example.test/api")
	assert_eq(result["method"], HTTPClient.METHOD_POST)
	assert_eq(result["timeout_seconds"], 5.0)


func test_websocket_client_stub_keeps_m7_connection_shape() -> void:
	var client := WsClientScript.new()

	assert_false(client.is_socket_connected())
	assert_eq(client.connect_to_endpoint("ws://example.test/socket"), ERR_UNAVAILABLE)
	assert_eq(client.send_text("hello"), ERR_UNAVAILABLE)
	assert_eq(client.send_json({"hello": "world"}), ERR_UNAVAILABLE)
```

### `tests/integration/test_project_roundtrip.gd`

```gdscript
extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const AppInfo := preload("res://core/util/app_info.gd")


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Round Trip")


func test_project_save_open_roundtrip_matches_manifest_canvas_and_assets() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var ids := []

	for index in range(3):
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(float(index) / 3.0, 0.25, 0.75, 1.0))
		ids.append(asset_library.register_image(image, "asset_%d" % index, {"origin": "imported"}))

	var canvas_data := {
		"camera": {"center": [12, -8], "zoom": 2.0},
		"items":
		[
			_make_item("item_0", ids[0], Vector2(0, 0), 0),
			_make_item("item_1", ids[1], Vector2(16, 8), 1),
			_make_item("item_2", ids[2], Vector2(-4, 24), 2),
		],
	}
	project_service.set_canvas_data(canvas_data)

	var path := "user://tests/roundtrip_m0.pxproj"
	assert_eq(project_service.save_project(path), OK)

	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	assert_true(unpacked["ok"])
	assert_true(unpacked["files"].has("manifest.json"))
	assert_true(unpacked["files"].has("canvas/canvas.json"))

	var manifest: Dictionary = FileIOScript.bytes_to_json(unpacked["files"]["manifest.json"])
	assert_eq(int(manifest["format_version"]), 1)
	assert_eq(int(manifest["entries"]["asset_count"]), 3)

	assert_eq(project_service.open_project(path), OK)
	assert_eq(project_service.current_project.manifest["name"], "Round Trip")
	assert_eq(project_service.current_project.canvas["camera"], canvas_data["camera"])
	assert_eq(project_service.current_project.canvas["items"].size(), 3)

	for asset_id in ids:
		assert_true(asset_library.has_asset(asset_id))
		assert_not_null(asset_library.get_image(asset_id))


func test_project_open_rejects_future_format_version() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var path := "user://tests/future_format.pxproj"
	var manifest := {
		"format_version": AppInfo.PROJECT_FORMAT_VERSION + 1,
		"app_version": "future",
		"id": "future-project",
		"name": "Future Format",
		"entries": {"asset_count": 0},
	}
	var canvas := {
		"camera": {"center": [0, 0], "zoom": 1.0},
		"items": [],
	}

	assert_eq(
		FileIOScript.zip_pack({"manifest.json": manifest, "canvas/canvas.json": canvas}, path), OK
	)
	assert_eq(project_service.open_project(path), ERR_FILE_UNRECOGNIZED)


func _make_item(item_id: String, asset_id: String, position: Vector2, z_index: int) -> Dictionary:
	return {
		"id": item_id,
		"type": "sprite",
		"asset_id": asset_id,
		"position": [int(position.x), int(position.y)],
		"scale_factor": 1,
		"z_index": z_index,
		"locked": false,
		"frame_id": null,
	}
```

### `tests/smoke/test_infinite_canvas.gd`

```gdscript
extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const ImageMath := preload("res://core/util/image_math.gd")


func before_each() -> void:
	get_tree().root.get_node("UndoService").clear()


func test_canvas_handles_500_items_pan_and_zoom() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(1024, 768)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var image := _make_checker_image(64)
	for index in range(500):
		var x := float(index % 50) * 72.0
		var y := float(index / 50) * 72.0
		canvas.add_sprite_item(image, "", Vector2(x, y), "", false)

	canvas.pan_by_pixels(Vector2(120, -80))
	canvas.zoom_by_steps(3, Vector2(320, 240))
	await wait_process_frames(5)

	assert_eq(canvas.get_item_count(), 500)
	assert_lt(Performance.get_monitor(Performance.TIME_PROCESS), 0.033)


func test_zoom_uses_nearest_neighbor_color_set() -> void:
	var source := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	source.set_pixel(0, 0, Color.RED)
	source.set_pixel(1, 0, Color.BLUE)

	var enlarged := source.duplicate()
	enlarged.resize(32, 16, Image.INTERPOLATE_NEAREST)

	assert_eq(ImageMath.color_set(enlarged).size(), ImageMath.color_set(source).size())


func test_add_delete_move_are_undoable() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var image := _make_checker_image(8)
	canvas.add_sprite_item(image, "", Vector2.ZERO, "sprite_1", true)
	assert_eq(canvas.get_item_count(), 1)

	assert_true(undo.undo())
	assert_eq(canvas.get_item_count(), 0)
	assert_true(undo.redo())
	assert_eq(canvas.get_item_count(), 1)

	canvas.select_ids(["sprite_1"])
	canvas.move_selected_by(Vector2(5.2, 3.7), true)
	var moved: Variant = canvas.export_canvas_data()["items"][0]["position"]
	assert_eq(moved, [5, 4])
	assert_true(undo.undo())
	assert_eq(canvas.export_canvas_data()["items"][0]["position"], [0, 0])
	assert_true(undo.redo())
	assert_eq(canvas.export_canvas_data()["items"][0]["position"], [5, 4])

	canvas.delete_selected(true)
	assert_eq(canvas.get_item_count(), 0)
	assert_true(undo.undo())
	assert_eq(canvas.get_item_count(), 1)


func test_culled_items_disable_process_callbacks() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(256, 256)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var image := _make_checker_image(8)
	var visible_item: Node = canvas.add_sprite_item(image, "", Vector2.ZERO, "visible", false)
	var far_item: Node = canvas.add_sprite_item(image, "", Vector2(10000, 10000), "far", false)
	visible_item.set_process(true)
	visible_item.set_physics_process(true)
	far_item.set_process(true)
	far_item.set_physics_process(true)

	await wait_seconds(0.2)

	assert_true(visible_item.visible)
	assert_true(visible_item.is_processing())
	assert_true(visible_item.is_physics_processing())
	assert_false(far_item.visible)
	assert_false(far_item.is_processing())
	assert_false(far_item.is_physics_processing())


func _make_checker_image(size: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			image.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
	return image
```

### `tests/smoke/test_main_window_ui.gd`

```gdscript
extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")


func test_main_window_uses_readable_minimum_sizes() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var root := main.get_node("Root")
	var top_bar: Control = root.get_node("TopBar")
	var bottom_bar: Control = root.get_node("BottomBar")

	assert_eq(main.custom_minimum_size, Vector2(1280, 800))
	assert_eq(top_bar.custom_minimum_size.y, 48.0)
	assert_eq(bottom_bar.custom_minimum_size.y, 32.0)

	for child in top_bar.get_children():
		if child is Button:
			assert_gte(child.custom_minimum_size.x, 84.0)
			assert_gte(child.custom_minimum_size.y, 34.0)


func test_auto_interface_scale_detects_high_density_displays() -> void:
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(2560, 1440)), 1.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(3840, 2160)), 1.5)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(5120, 3140)), 2.0)
	assert_eq(MainScript.compute_auto_interface_scale(2.0, Vector2i(2560, 1600)), 2.0)
```

### `README.md`

```markdown
# PixelForge

CI：`.github/workflows/ci.yml` 已配置 Godot 4.6.3、gdtoolkit lint、GUT 测试和导出模板检查。本地副本没有 Git remote，无法生成有效 GitHub badge URL；接入仓库后请使用实际 `owner/repo` 补全 Actions badge。

PixelForge 是一个 Godot 4.6 工具型应用工程。本阶段实现 M0：工程骨架、无限画布底座、基础服务、项目保存/打开、撤销与任务队列。

## 目录摘要

- `core/`：纯逻辑领域层，只放不依赖场景树的像素算法、数据模型和工具。
- `services/`：应用服务层，管理项目、素材、撤销、任务队列、设置和事件总线。
- `infra/`：基础设施层，封装日志、文件 IO、HTTP/WebSocket 等外部能力。
- `ui/`：界面层，包含主窗口、无限画布和后续面板。
- `tests/`：GUT 自动化测试，按 unit / integration / smoke 分层。
- `docs/`：手动测试脚本、交付说明和维护文档。
- `addons/gut/`：GUT 测试框架。

## 常用命令

```bash
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```

如果系统 PATH 没有 `godot`，脚本会自动尝试 `/Applications/Godot.app/Contents/MacOS/Godot`。

`./scripts/lint.sh` 需要 `gdformat` 和 `gdlint`。本地缺少 gdtoolkit 时会失败退出，安装命令：

```bash
python -m pip install gdtoolkit
```

如果项目内存在 `.godot/gdtoolkit-venv/bin`，`lint.sh` 会自动优先使用该本地环境。

导出预设使用 `export_presets.cfg.example` 作为模板。需要本地导出时复制为 `export_presets.cfg`，该本地文件已加入 `.gitignore`。
```

### `CHANGELOG.md`

```markdown
# Changelog

## Unreleased

- M0: 建立 Godot 4.6 工程骨架、基础设施服务、无限画布、项目保存/打开、撤销/任务队列和测试流水线。
- M0 修订: 禁用 viewport stretch 压缩，增加自动 UI scale，修复 Retina/高分屏下窗口与字体显示过小的问题。
- M0 复审加固: 严格执行 gdtoolkit lint、模板化 export presets、补充任务取消/AssetLibrary 缓存计费测试，并拆出画布选择状态模块。
- M0 二审加固: 补齐 TaskQueue running cancel 生命周期、未来项目格式拒开、Logger 日志清理、真实 LRU 验证、视口外 process 剔除、HTTP/WebSocket stub 签名和 M1 交接说明。
```

### `docs/manual-test-m0.md`

```markdown
# M0 手动测试脚本

适用版本：Godot 4.6.3，PixelForge `0.1.0-m0`。

## 1. 启动

1. 在项目根目录运行 `./scripts/check_export_templates.sh`。
2. 确认 Godot headless 能启动并退出，日志中出现 `Logger ready`。
3. 使用 Godot 编辑器或可执行程序打开项目，确认窗口标题为 `Untitled - PixelForge`。
4. 在 macOS Retina / 5K 物理分辨率屏幕上确认窗口按自动 UI scale 放大：视觉上约为 1440x900 逻辑尺寸，字体边缘清晰，不再被 1440px viewport 压缩成小窗口。
5. 确认顶部工具栏、按钮和状态栏文字可正常阅读；在 5K/Retina 环境下工具栏应使用 2x scale，在 4K 环境下应使用 1.5x scale。
6. 如需手动覆盖界面缩放，可在 `user://settings.cfg` 中将 `ui/interface_scale` 设置为 `1.0`、`1.5` 或 `2.0`；`0.0` 表示自动检测。

## 2. 新建、拖入、画布交互

1. 点击 `New`。
2. 将 10 张 PNG 拖入窗口。
3. 用鼠标滚轮缩放，确认缩放锚点跟随鼠标位置。
4. 在缩放达到 400% 及以上时确认像素网格出现。
5. 按住中键拖拽，确认画布平移。
6. 按住空格并左键拖拽，确认画布平移。
7. 单击选择元素，Shift 单击多选，空白区域拖出框选。
8. 拖拽选中元素，确认位置吸附到整数坐标。
9. 按 Delete 删除元素，按 Ctrl+Z 撤销，按 Ctrl+Shift+Z 重做。

## 3. 保存与打开

1. 按 Ctrl+S 或点击 `Save`，保存为 `.pxproj`。
2. 用系统 `unzip` 或压缩工具打开 `.pxproj`。
3. 确认至少包含：
   - `manifest.json`
   - `canvas/canvas.json`
   - `assets/{asset_id}.png`
   - `assets/{asset_id}.meta.json`
4. 关闭项目后重新打开 `.pxproj`。
5. 确认画布元素位置、数量、素材和相机缩放与保存前一致。

## 4. 自动保存与恢复提示

1. 修改画布后等待自动保存周期，或在调试控制台调用 `ProjectService.autosave_now()`。
2. 强制结束进程。
3. 再次启动应用。
4. 确认出现自动保存恢复提示，并能打开最近的 autosave 项目。

## 5. Session Lock 异常退出验证

1. 打开应用并保持项目处于运行状态。
2. 在系统终端中使用 `kill -9 <pid>` 强制结束 Godot/PixelForge 进程。
3. 再次启动应用。
4. 确认应用能识别上一次 session lock 未正常释放，并触发恢复提示或安全清理路径。
5. 若恢复提示未出现，记录平台、Godot 版本、日志文件路径和 `user://pixelforge_session.lock` 状态，作为 M1 前置缺陷处理。

## 6. Windows 平台记录

当前本机环境为 macOS，无法直接完成 Windows 实测。M0 合并前需要在 Windows 11 + Godot 4.6.3 环境执行本文件第 1-5 节，并记录：

- 窗口默认尺寸和 UI scale 是否清晰可读。
- `.pxproj` 保存/打开是否能被系统压缩工具检查。
- `kill -9` 等价操作（任务管理器结束进程）后恢复提示是否正常。
- `./scripts/lint.sh`、`./scripts/run_tests.sh`、`./scripts/check_export_templates.sh` 是否通过。

## 7. 自动化验收命令

```bash
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```

当前本机已验证：

- GUT：29 tests / 224 asserts 全部通过。
- headless 启动：通过；本机缺少 Godot 4.6.3 export templates，CI 会安装模板后执行检查。
- lint：严格模式通过；使用项目内临时 venv 安装 gdtoolkit 后，`gdformat --check` 与 `gdlint` 均已实际执行。
```

### `docs/m1-handoff-notes.md`

```markdown
# M1 Handoff Notes

本文给下一个 agent 解释 M0 地基的设计目的、可依赖契约和仍需登记的风险。M1 开始前建议先读本文件，再读 `pixelforge-plan/03-milestones/M1-cleanup-pipeline.md`。

## 架构边界

- `core/`：纯逻辑和无场景树依赖的工具。M1 的像素算法、裁切、量化和调色板逻辑优先放这里。
- `services/`：应用状态和业务流程。M1 如果需要排队执行批处理，应该通过 `TaskQueue`，不要在 UI 脚本里直接开线程。
- `infra/`：外部能力封装。HTTP/WebSocket 目前是 stub，M4/M7 才实现网络；M1 不应在这里扩展业务逻辑。
- `ui/`：Godot 控件和交互。画布状态已经开始拆分，M1 新增面板时保持 UI 只调用服务，不直接读写压缩包格式。

## TaskQueue

`TaskQueue` 有三个关键目的：

- Worker 内不触碰场景树，进度和完成信号统一回主线程发出。
- 并行任务按提交顺序 flush 完成信号，避免 M1 批量清洗时 UI 乱序刷新。
- running task 的取消是协作式取消，不是线程抢占。`cancel(task_id)` 只设置 `cancel_requested`；`task_canceled` 和 `_running` 清理要等 worker 自然返回。

M1 使用建议：

- 长任务的 work callable 需要定期检查 `task_ref.cancel_requested`，尽快返回。
- 调用方必须等 `task_canceled/task_finished/task_failed` 信号，不要把 `cancel()` 当成同步完成。
- 如果 M1 要显示批处理队列，请以 task id 和提交顺序为 UI 主键。

## UndoService

Undo 动作包含图像快照时，必须显式传入内存成本：

```gdscript
var cost := UndoService.estimate_snapshot_cost(before_image)
UndoService.perform_action("Cleanup", do_cleanup, undo_cleanup, cost)
```

如果一个 action 持有多张图像副本，逐张相加。这个约定是 M1 最容易漏的点：不传 `memory_cost_bytes` 不会立刻报错，但会让 512MB 上限失效。

## ProjectService

`open_project()` 会拒绝高于当前 `AppInfo.PROJECT_FORMAT_VERSION` 的项目，返回 `ERR_FILE_UNRECOGNIZED`。这是为了避免旧 app 静默解析新格式。

M1 如果修改 `.pxproj` 格式：

- 在 `core/util/app_info.gd` 提升 `PROJECT_FORMAT_VERSION`。
- 在 `ProjectService.MIGRATIONS` 增加从旧版本到新版本的迁移 callable。
- 补一个旧格式打开迁移测试，以及一个未来版本拒开测试。

## AssetLibrary

素材缓存统一保存 RGBA8，内存计费为 `width * height * 4`，等价 `Image.get_data().size()`。`get_image()` 返回副本，调用方可以安全修改返回图像，不会污染缓存。

LRU 由 `_lru_order` 维护：每次存入或命中缓存都会把 asset id 移到末尾，超限时从头淘汰。M1 如果增加批量清洗预览，优先复用 asset id，不要绕过 `AssetLibrary` 直接缓存裸 Image。

## Canvas

`infinite_canvas.gd` 保留坐标转换、绘制、Undo 接入和元素管理；选择、拖拽、框选状态已拆到 `canvas_selection.gd`。M3 节点图或 M1 清洗预览需要更多状态时，继续按职责拆文件，不要把所有交互状态塞回主画布。

视口剔除现在同时设置：

- `item.visible`
- `item.set_process(visible)`
- `item.set_physics_process(visible)`

这是为 M1/M2 后续元素动画或进度标记预留的 CPU 保护。

## Logger 和脚本环境

Logger 写 `user://logs/app_YYYY-MM-DD.log`，启动时按文件名日期清理 7 天前日志。测试脚本会把 `HOME` 指向项目内 `.godot/home`，这是为了避免 macOS/沙箱环境下 Godot 初始化日志时写系统目录失败。

`.godot/` 是本地临时目录，不应提交。

## HTTP/WebSocket Stub

`PFHttpClient` 固定了 `request_raw()`、`request_json()`、`cancel_all()` 和结果字典字段。M4 实现时保持 `ok/status_code/headers/body/error/url/method/timeout_seconds` 这些字段。

`PFWsClient` 固定了连接、发送、轮询和关闭签名。不要命名为 `is_connected()`，这个名字会和 Godot `Object.is_connected(signal, callable)` 冲突；当前接口是 `is_socket_connected()`。

## 登记债务

- 像素网格仍是 GDScript `draw_line` 循环。M0 性能测试通过，但 M1 末尾或 M3 前建议改成 shader/ColorRect 方案。
- Windows 11 + Godot 4.6.3 实测仍未在当前机器完成。`docs/manual-test-m0.md` 已列出手动验证项。
- 当前测试为 29 tests / 224 asserts。M1 开始前建议按 M0/M1 任务卡逐条做验收覆盖盘点，尤其是批量图像处理和错误恢复。

## 常用验证命令

```bash
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```
```
