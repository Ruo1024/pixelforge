# M2 人工走查清单

适用版本：Godot 4.6.3，PixelForge M2。
目标：验证 v0.1 alpha 故事 `AI 图拖入 -> 清洗 -> 抠图 -> 切分 -> 描边 -> spritesheet 导出` 在真实窗口中可走通。

## 1. 基础导入与清洗

1. 启动 PixelForge，拖入一张本地 PNG 到画布。
2. 选中该素材，使用右侧 Pixel Cleanup 面板执行一次 `Apply Cleanup`。
3. 确认清洗结果作为新素材出现在原素材右侧，原素材未被覆盖。
4. 保存项目并重新打开，确认原素材和清洗素材都存在。

## 2. 抠图与切分

1. 选中一张白底或纯色底多物体图。
2. 点击顶栏 `Matte`，确认背景被透明化，结果作为新素材出现。
3. 选中原图或抠图结果，点击顶栏 `Slice`。
4. 确认多个独立物体被拆成独立素材，并按从上到下、从左到右的顺序排列在原图右侧。
5. 保存项目并重新打开，抽查拆分素材的 provenance 中 `parent_asset` 指向原素材。

## 3. 描边与导出

1. 选中一个透明背景素材，点击顶栏 `Outline`。
2. 确认生成的新素材带 1px 黑色外描边，原素材不变。
3. 多选 2 个以上素材，点击 `Export PNG`，选择 `spritesheet.png`。
4. 确认同目录下生成 `spritesheet.png` 和 `spritesheet.json`。
5. 打开 JSON，确认每个素材有 `frame.x/y/w/h` 坐标；PNG 放大查看仍为清晰最近邻像素。

## 4. 跨平台/显示检查

0. Godot 编辑器调试前先关闭编辑器并运行 `./scripts/configure_editor_game_view.sh`，再重新打开项目；该脚本默认禁用 Game embedding，Play 时应出现无 Game bar 的独立窗口。若手动重新启用 Game bar（顶部有 `输入 / 2D / 3D` 等按钮），右侧下拉菜单的 Embedded Window Sizing 必须设为 `Stretch to Fit`；`Fixed Size` 会按项目基准分辨率居中显示，属于编辑器调试设置，不是 PixelForge 工作区布局。
1. macOS Retina：顶栏 `Matte/Slice/Outline/Export PNG` 按钮高度、字号与现有按钮一致。
2. Windows 100%/150% 缩放：按钮可读，不重叠，文件对话框可正常保存 PNG/JSON。
3. 运行 M2 动作时，画布仍可平移缩放；任务结束后状态栏显示完成状态。

## 5. M2.1 UI 交互补完

1. 使用 `File > Import Images...` 多选 2 张以上 PNG/JPG，确认画布出现批次卡缩略网格；拖放单张图片仍生成独立 sprite。
2. 选中单张 sprite，点击 `Matte`，确认弹出参数对话框；调整 tolerance/feather 后预览更新，按 Esc 取消不生成新素材。
3. 选中单张 sprite，点击 `Slice` / `Outline`，确认参数对话框可预览 bbox / 描边结果，Apply 后生成新素材且原素材不被覆盖。
4. 按 `W` 后在选中 sprite 内点击背景，确认状态栏显示选区面积；按 `M` 拖拽确认矩形选区与尺寸提示；按 `L` 左键打点、右键闭合确认套索选区。
5. 拖动左下角缩放滑条，确认画布按离散 zoom level 缩放且百分比标签同步；再用鼠标滚轮缩放，确认滑条位置同步变化。
6. 选中 2 张以上 sprite，点击 `Batch` 生成批次卡；在批次卡缩略图上点选子集，右键卡片执行 `Split Selected`，确认子批次独立出现且原批次不变。
7. 右键批次卡执行 `Clean Batch` / `Matte Batch` / `Outline Batch`，确认批次缩略图替换为新素材版本，Ctrl+Z 可回退整批卡 asset 队列。
8. 对渐变或非纯色背景图执行 `Matte`，确认出现可操作建议而不是只有状态栏 warning。

## 签字区

| 走查人 | 日期 | 平台 | 结论 | 备注 |
|---|---|---|---|---|
| _待填_ | | | | |
