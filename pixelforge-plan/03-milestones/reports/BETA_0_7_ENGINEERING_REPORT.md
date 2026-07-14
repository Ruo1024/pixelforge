# PixelForge Beta 0.7 工程报告

> 日期：2026-07-14
>
> 分支：本地 `main`，未 push、未发布
>
> B7-9 基线：`fa4818d188fe2f0432f3f23f7d97ce420c3f4ccb`
>
> 批准计划 SHA-256：`655597660e21acdf7a4d5e2bab388bdf54586875ee59921211cdc1dad2f073f4`
>
> 当前状态：**工程通过、人工待验、发布未通过**

## 1. 工程结论

Beta 0.7 B7-0 至 B7-9 的本地工程门已通过。唯一候选是
`PixelForge-0.7.0-beta.1-macOS.zip`；自动化、脚本截图和干净用户目录启动只能证明
候选具备工程测试条件，不能替代项目所有者对真实云端、输入手感、视觉和保存重开的
人工签收。

本卡只把 `pixel/core/util/app_info.gd` 的单点应用版本改为 `0.7.0-beta.1`；没有在
组件或其他源码增加版本常量。没有调用 Computer Use、真实 Provider 或付费 API。

## 2. 唯一总验证

命令：

```bash
./pixel/scripts/verify_beta_0_7.sh
```

结果：

- lint / format：336 个 GDScript 文件，无问题；
- 全量 GUT + 本地 mock HTTP：130 scripts、621/621 tests、14,818 assertions；
- i18n catalog：通过；
- i18n 源码守护：6/6 tests、484 assertions；
- UI scaling 静态守护：通过；
- English/简中 × 3 个窗口 × 3 个 UI scale 的 18 组几何：1/1 test、3,691 assertions；
- 8/8 固定截图、精确文件集、尺寸、结构字段、唯一 SHA 与 manifest：通过；
- 官方 Godot 4.6.3 macOS export template：存在并用于构建；
- `git diff --check`：通过；
- staged / `26a6070...HEAD` / working tree / untracked 合并 raster 守护：通过；
- 凭据 sentinel 未进入日志可见持久化面、截图或 manifest。

三张受保护 real fixture 只在全量测试期间从控制工作区临时复制并逐张核验固定 SHA；
测试后 PNG、sidecar 和 `.godot/imported` 派生物均立即清零。它们没有进入截图、Git、
候选或桌面副本。

## 3. 固定结构证据

证据目录（ignored）：
`/Users/ruo/Desktop/pixelforge/scratch/worktrees/main-integration/scratch/beta0-7-evidence/`

| 文件 | 场景 | SHA-256 |
|---|---|---|
| `1280x720-en-100-example-reflow.png` | 重排后的内置实例 | `14b3b64525ecd4d0943321aff1b8a3864addffbe7809743024c42246612c26fa` |
| `1440x900-zh-100-generation-ready.png` | 生成卡 Ready、尺寸和费用 | `246b0675761a3e0a8ae9ac8e5cdfb8e455d5cbae1d879065412ed54359dd82ad` |
| `1440x900-en-100-running-output-edge.png` | Running、pending Output、固定 active 相位 | `72acbee3aa45e788355886567e4ea412956cab69dcaca13dc808a399cd57a536` |
| `1440x900-zh-100-output-12.png` | 12 张三行 Output | `7c54bfccdaa756fb943dceec363daba959e452444d07671576404578cffbc2ce` |
| `1440x900-en-100-output-13-50-scroll.png` | 13/50 张内部滚动 | `e9100d17becee95fc07874a3f62ffa1040cf577766256c2051e91caae1a8c659` |
| `1440x900-zh-100-detached-sprite.png` | 单图拆出后的独立图片卡 | `1c3d50d4d08f8f1de7f8dad0f6046594233e939b93de86e4de0fd1d16e27b73e` |
| `1440x900-en-100-cleanup-running.png` | pixel_cleanup 全参数与 Running | `3ef0f49e94f3249952a3b789b7c5c49cdd55793f0130c7bd0d6e938ab45339c2` |
| `1080x560-zh-150-partial-dialog.png` | Partial 错误框与仅重试失败项 | `29a5869852c470fa06131a6cc66bb6c4f4e477532e0c13e53736e8efe9ee8f98` |

所有画面使用程序生成的许可安全结构素材。manifest 的 sentinel 扫描结果为
`found=false`。这些截图只证明固定结构，不证明真实窗口手感或视觉已人工通过。

## 4. 唯一 macOS 候选

- scratch：`/Users/ruo/Desktop/pixelforge/scratch/candidates/beta0-7/PixelForge-0.7.0-beta.1-macOS.zip`
- 桌面：`/Users/ruo/Desktop/PixelForge-0.7.0-beta.1-macOS.zip`
- SHA-256：`fd984990ecd44f7dd0c445d7b4b71f36b635a2eca70a81414e95c80fa5d71ba9`
- 大小：77,513,760 bytes
- 两处文件逐字节 SHA 一致。

ZIP 与 PCK 共审计 10 个归档路径和 445 个 PCK 路径；未发现 `scratch/`、受保护图片
目录、用户项目、credentials、日志、环境密钥或 sentinel。解包后的应用在全新 HOME、
清空环境变量的 headless 模式启动通过，没有调用真实 Provider。

PixelForge 没有执行项目签名或公证。官方 Godot macOS export template 自带并保留
发行方 `Prehensile Tales B.V.` / Team ID `6K46PWY5DM` 的供应商签名；构建门只接受这个
固定官方身份并拒绝其他签名。这不等于 PixelForge 已签名、公证或可发布。

## 5. 已知非阻断噪声

- 全量测试仍有 1 个既有 `error_tracker.gd` orphan；数量未增长。
- 插件隔离负向测试会故意加载损坏的 `syntax_error` fixture，产生预期解析错误。
- Godot 退出时仍报告既有 ObjectDB / resource-in-use 提示；测试进程退出 0，数量口径未
  用来替代 621/621 结果。
- 导出器在隔离 HOME 下打印一次 ObjectDB Snapshots 目录创建失败提示；导出退出 0，
  ZIP/PCK 审计与候选自身的干净 HOME 启动均通过。

## 6. 后续状态

项目所有者只对上述 SHA 对应的桌面候选执行 `manual-test-beta0.7.md`。在项目所有者明确
签收前，状态保持“人工待验、发布未通过”。本卡没有 push、发布、PixelForge 项目签名、
公证或真实付费请求。
