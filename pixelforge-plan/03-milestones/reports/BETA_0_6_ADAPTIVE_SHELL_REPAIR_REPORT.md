# PixelForge Beta 0.6 自适应工作区壳修复报告

> 日期：2026-07-14
>
> 分支：`codex/beta0-6-adaptive-shell-repair`（本地，未合并 `main`、未 push）
>
> 修复基线：`0a746ce9`
>
> 代码提交：`25aa18c fix: rebuild adaptive desktop shell`
>
> 当前状态：**工程通过、人工待验、发布未通过**

## 1. 修复原因

`PixelForge-0.6.0-beta.1-macOS.zip` 已被项目所有者否决。实际 macOS 运行截图确认：

1. 内建 Retina 屏拖到外接屏后出现异常放大、裁切与工作区错位；
2. 直接在外接屏打开时，顶栏、画布卡片和右侧区域比例失衡、内容不可达；
3. 恢复自动保存弹窗无法点击；
4. 项目所有者运行到的界面与 Beta 0.6 交付说明不一致，暴露分支/工作区交接错误；
5. 旧几何矩阵和脚本截图没有证明真实独立窗口的显示器、DPI 切换和原生输入。

因此 beta.1 的“工程通过”结论已经撤销，旧候选、SHA、测试数字和截图没有沿用到 beta.2。冻结的 `1A / 2B / 3C` 卡片设计保持不变。

## 2. 实现差异

- 根窗口改为会话固定 UI 倍率：应用启动时确定倍率；运行中跨屏不热换主题，也不让组件累积第二套倍率。
- macOS 屏幕、可用区和窗口几何按 Godot 已统一的坐标语义使用，不再按当前缩放做二次乘除。
- Godot 开发运行改为独立项目窗口模式 `game_embed_mode=-1`；嵌入式 Game 视图只作普通预览，不再作为显示器/DPI/输入通过证据。
- 工作区按逻辑可用宽度响应：1080 使用紧凑顶栏，Undo/Redo/Inspector 保持图标入口；更宽窗口使用标准顶栏，项目标题、主要动作和检查器仍可达。
- 修复模态弹窗、卡片标题按钮、双击和清理网格拖动的输入链；RecoveryDialog 使用真实 `InputEvent` 验证按钮命中。
- 固定截图脚本按场景使用真实 1.0/1.25/1.5/2.0 倍率和物理窗口尺寸，再输出规定的逻辑截图；候选脚本只生成新的 beta.2。

这些变更只重建工作区壳、窗口缩放、响应式入口和输入可靠性，没有扩展模型、Provider、工作流、账号、协作、本地模型或 ComfyUI。

## 3. Godot 官方依据

本次实现参考 Godot 4.6.3 的编辑器与 macOS 行为，但没有复制 Godot 编辑器控件或资产：

- 编辑器自动显示倍率取值与会话设置：[Godot `editor_settings.cpp`](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/editor/settings/editor_settings.cpp#L1853-L1904)
- UI scale 设置与重启语义：[Godot `editor_settings.cpp`](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/editor/settings/editor_settings.cpp#L451-L454)、[theme manager 注释](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/editor/themes/editor_theme_manager.cpp#L710-L713)
- macOS 最大倍率和屏幕几何：[Godot `display_server_macos.mm` 最大倍率](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/platform/macos/display_server_macos.mm#L1549-L1553)、[macOS 几何实现](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/platform/macos/display_server_macos.mm#L1490-L1573)
- Game 视图嵌入模式含义：[Godot 官方文档](https://docs.godotengine.org/en/4.6/tutorials/editor/game_embedding.html)、[实际模式映射](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/editor/run/game_view_plugin.cpp#L948-L970)
- DisplayServer 屏幕倍率契约：[Godot `DisplayServer.xml`](https://github.com/godotengine/godot/blob/35e80b3a8822a9df9be390814b62f44c0a9c69e8/doc/classes/DisplayServer.xml#L1808-L1817)

## 4. 自动化与静态门

唯一总入口：

```bash
./pixel/scripts/verify_beta_0_6.sh
```

| 门禁 | 最终结果 |
|---|---|
| 总验证 | 全绿 |
| lint | 241 个 GDScript 文件通过 |
| 全量 GUT | 396/396 tests、7718 assertions 通过 |
| i18n | 通过 |
| UI scaling guard | 通过 |
| 自适应定向测试 | 4/4 tests、508 assertions 通过 |
| 真实根 Window | 1.0/1.25/1.5/2.0 通过 |
| 响应式往返 | 1080→1280→1440→1080 通过 |
| 模态输入 | RecoveryDialog 真实 Input 命中通过 |
| Beta 0.6 固定截图 | 7/7 与 manifest 自验通过 |
| export / 候选启动 | Godot 4.6.3 官方 macOS 模板导出、干净用户目录启动通过 |
| 安全与 Git 守护 | 受保护路径审计、`git diff --check`、staged raster guard 通过 |

全量测试需要的本地受保护 fixture 只在忽略目录中临时恢复，测试完成后已经删除，未进入提交、候选或截图。唯一已知自动化噪声仍是 GUT 既有 `error_tracker.gd` orphan 和退出资源告警；本轮没有新增失败或噪声类型。

## 5. 固定截图证据

证据目录为 `scratch/beta-evidence/beta-0.6/`，不纳入 git。manifest SHA-256 为 `c54d12db826c84e1e122012f70475efac1f9bae1fa0ba33450b416e2779ccc21`。

| 文件 | UI scale / 模式 | PNG SHA-256 |
|---|---|---|
| `1080x560-en-100-closed.png` | 2.0 / compact | `4cfe889d490d98e09063b91b8d755de992cefbac26f7f44cfdd4e90cfd736152` |
| `1080x560-zh-50-overlay.png` | 2.0 / compact | `db250897d73a5dcec609c567b03c94a85a6b2eef12fc02df55e77fc3e08810d0` |
| `1280x720-en-50-batch-12-13.png` | 1.25 / standard | `947c162e2b68a7b3372c405ec41711f65e91f4b0a2b99de1619fe45896b42578` |
| `1280x720-zh-100-inspector.png` | 1.5 / standard | `9815d73e4872b6c98f789462b846d98ec4e02171d5f6d06e88d5aca306fc3a3a` |
| `1440x900-en-50-batch-50-all.png` | 1.0 / standard | `38ef911a00a011408ebee3eebd8f2ae9c4043000269dff0d21d4e72020e80ac7` |
| `1440x900-zh-100-card-families.png` | 1.25 / standard | `effb8a4afc20fc269086ad995f9c9bd1275f2d65200e044ba0742902d8dd24da` |
| `1440x900-en-400-inspect.png` | 1.0 / standard | `a043466522b3ae51bc83a1106c02df459a1bb0c4861714bc2d815159b36b197c` |

manifest 记录 `git_head=25aa18c4913393da97892f8652c78878751ae9c3`。`git_dirty=true` 来自尚未提交的报告文档，不代表截图对应代码未提交。脚本截图只证明工程渲染、几何和场景元数据，不代表项目所有者已经完成真实内外屏人工验收。

## 6. 唯一新候选

- 产物：`pixel/build/PixelForge-0.6.0-beta.2-macOS.zip`，78,172,023 bytes。
- SHA-256：`9aa88053fe0dac4e800d4cc8cc8db59e46c981f5132aadf45675bad3ac232d0c`。
- Godot 与 macOS 官方导出模板：4.6.3。
- ZIP/PCK 受保护路径审计：通过。
- 解包后干净用户目录启动：通过。
- 签名、公证、发布：未执行。

## 7. 状态与下一步

| 层级 | 当前状态 |
|---|---|
| 工程 | 通过；代码、自动化、截图与唯一候选已收口 |
| 人工 | 待验；只允许项目所有者测试 beta.2 |
| 发布 | 未通过；未合并 `main`、未 push、未签名公证、未发布 |

项目所有者现在可以按 `manual-test-beta0.6.md` 一次性执行真实云端、中文、视觉、点击手感以及内建 Retina → 外接屏 → 内建屏往返。自动化不能替代该跨屏签收。项目所有者给出 `go / 修复后复验 / 整体不合并` 后再更新人工状态；合并与 push 仍需另行明确授权。
