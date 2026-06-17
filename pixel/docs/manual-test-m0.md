# M0 手动测试脚本

适用版本：Godot 4.6.3，PixelForge `0.1.0-m0`。

## 1. 启动

1. 在项目根目录运行 `./scripts/check_export_templates.sh`。
2. 确认 Godot headless 能启动并退出，日志中出现 `Logger ready`。
3. 使用 Godot 编辑器或可执行程序打开项目，确认窗口标题为 `Untitled - PixelForge`。
4. 在 macOS Retina / 5K 物理分辨率屏幕上确认窗口按自动 UI scale 放大：视觉上约为 1440x900 逻辑尺寸，字体边缘清晰，不再被 1440px viewport 压缩成小窗口。
5. 确认顶部工具栏、按钮和状态栏文字可正常阅读；在 5K/Retina 环境下工具栏应使用 2x scale，在 4K 环境下应使用 1.5x scale。
6. 如需手动覆盖界面缩放，可在 `user://settings.cfg` 中将 `ui/interface_scale` 设置为 `1.0`、`1.5` 或 `2.0`；`0.0` 表示自动检测。**测试结束后必须把该值还原为 `0.0`**——残留的显式覆盖会永久旁路自动检测，曾导致 macOS Retina 下界面缩小一半复发（M1.1 改进期已加入针对 mac 残留 `1.0` 的一次性自动迁移，但其他值仍会被尊重）。

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

- GUT：30 tests / 225 asserts 全部通过。
- headless 启动：通过；本机缺少 Godot 4.6.3 export templates，M0 本地 agent 门控只验证 headless 启动。
- lint：严格模式通过；使用项目内临时 venv 安装 gdtoolkit 后，`gdformat --check` 与 `gdlint` 均已实际执行。
