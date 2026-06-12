# M1.1 人工走查清单

适用版本：Godot 4.6.3，PixelForge M1.1。
来源：M1.1-2 验收第 4 条（非技术用户视角）与 M1.1 改进期复盘新增项。
**走查完成后在文末签字区记录人、日期、结论——矩阵中"待人工走查"项以此为闭环证据。**

## 1. 自定义调色板全流程（非技术用户视角，禁止查文档）

1. 从 Lospec 下载任一调色板 JSON（或使用 `assets/palettes/` 下样例复制改名）。
2. 检查器调色板下拉 → 选择 `Import custom palette...` → 文件选择器出现且只显示 `*.json`。
3. 选择合法 JSON → 下拉中出现该调色板且自动选中 → 色条预览正确显示其颜色。
4. **视觉区分检查（M1.1-2 计划要求项）**：确认自定义调色板在下拉中带 `Custom: ` 前缀，与内置板可一眼区分。
5. 选中自定义调色板 → `Delete Custom Palette` 按钮可用；选中内置调色板 → 按钮置灰。
6. 用该调色板对一张图执行 fixed_palette 清洗 → 输出色彩符合调色板。
7. 导入一个非法 JSON（如删掉 `colors` 字段）→ 错误弹窗给出具体字段原因，下拉状态不变。
8. 保存项目 → 关闭 → 重新打开 → 自定义调色板仍在下拉中且可用于清洗。
9. 删除自定义调色板 → 下拉回退到 db32 → 保存重开后确认已删除。

## 2. macOS 显示走查（M1.1 改进期新增）

1. Retina 屏启动：窗口约为 1440×900 逻辑尺寸（非 720×450 小窗）。
2. **检查器面板**：右侧 Pixel Cleanup 面板宽度、字号与主界面比例一致（不再是一半大小）。
3. 查看日志（`user://logs/`）中 `Interface scale resolved` 行：`source`、`resolved`、`reported_screen_scale` 与实际环境一致。
4. 若此前手动把 `interface_scale` 设过 `1.0`：启动后确认日志出现迁移警告且界面恢复正常；`settings.cfg` 中该值已回 `0.0`。
5. Cmd+S / Cmd+O / Cmd+N 可用（Windows 上 Ctrl 不回归）。

## 3. Auto K Strategy

1. Quantize 选 `Auto K` → `Auto K Strategy` 下拉出现，默认 `Median Cut`，tooltip 可读。
2. 切到 `Fixed Palette` / `None` → 该下拉隐藏。
3. k=32 下用 K-means 清洗一张渐变感强的图 → 不报错、颜色分布主观上不差于 Median Cut。

## 签字区

| 走查人 | 日期 | 范围 | 结论 | 备注 |
|---|---|---|---|---|
| _待填_ | | | | |
