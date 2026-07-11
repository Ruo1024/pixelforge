# PixelForge 1.0.0-rc.1 最终统一验收包

> 这是 M3.1–M7 唯一一次集中人工验收入口。工程门控已经统一通过，但下列结果必须由验收人记录后才可作产品/发布 go/no-go。

## 候选入口

- macOS：`pixel/build/PixelForge-1.0.0-rc.1-macOS.zip`
- Windows：`pixel/build/PixelForge-1.0.0-rc.1-windows.exe` + 同目录 PCK
- Linux：`pixel/build/PixelForge-1.0.0-rc.1-linux.x86_64` + 同目录 PCK
- 单页旅程：`pixel/docs/manual-test-v1.md`
- 用户资料：`pixel/docs/user-manual.md`、`faq.md`、`plugin-dev.md`、`licenses-and-models.md`

## 一次性执行顺序

1. 三平台干净配置启动；完成风格预设、示例项目和可选 Provider 设置，记录安装/缩放/可达性问题。
2. 用同一真实素材完成导入 → 清洗/抠图/切分/描边 → 3×4 批量审阅 → Pixel Repair Editor → Board/动画 → 保存重开 → 全类导出。
3. 分别执行 mock、OpenAI、RetroDiffusion、ComfyUI；检查进度、取消、失败人话提示、费用确认、provenance 和结果清洗衔接。
4. 执行目录插件与 PCK 安装、停用幽灵化、重装恢复、损坏插件隔离；确认权限警告文案。
5. 对同一工程强杀 10 次，每次从 autosave 恢复为副本，核对画布、节点、资产、Board、动画和导出引用均无丢失。
6. 至少 3 名未参与开发的目标用户只看文档完成旅程；记录用时、口头帮助次数、P0/P1 和主观质量结论。

## 结果记录

| 出口 | 结果 | 证据/阻断 |
|---|---|---|
| macOS 完整旅程 | 待验 |  |
| Windows 完整旅程 | 待验 |  |
| Linux 完整旅程 | 待验 |  |
| OpenAI 真实 API | 待验 |  |
| RetroDiffusion 真实 API | 待验 |  |
| ComfyUI 真实工作流 | 待验 |  |
| 强杀恢复 10/10 | 待验 |  |
| 插件权限文案法务 | 待验 |  |
| 3 名陌生用户 | 待验 |  |
| 最终产品 go/no-go | 待决策 |  |

判定规则：任一数据丢失、密钥泄漏、P0 崩溃或核心旅程不可达都直接 `no-go`；其他问题进入设计债后由项目所有者决定是否阻断 RC 晋级。禁止把工程通过自动转换成人工通过或发布通过。
