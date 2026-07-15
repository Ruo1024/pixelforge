# PixelForge Beta 0.7 Fix 工程报告

> 日期：2026-07-15
>
> 任务：PF · E · Beta 0.7 Fix 执行
>
> 分支：本地 `codex/beta0-7-fix-execution`
>
> 起点：`1b3f93481be5e8fc517344d2460abc6df2c6ad1c`
>
> 批准计划 SHA-256：`8113a8ed40737bcc5d14cc663fd4222a9e27b45c7f96cea75e39143a054b789c`
>
> 当前状态：**工程通过、人工未验、候选未构建、发布未通过**

## 1. 工程结论

批准的 B7F-0 至 B7F-8 已连续实现。应用内入口、操作反馈、结果和下一步已接通：

- 卡片内部滚动在边界继续拥有滚轮，点击卡片的视觉层和命中层同步置顶；
- 生成卡固定为 GPT Image 2、四档分辨率、三种方向和 1–16 个结果，不再显示比例锁、
  Quality、Advanced、Seed 或费用；5–16 个结果在创建槽位或任务前确认；
- API 设置与开发者模式进入顶栏；Key 仍走安全凭据存储，地址、保存、取消和本地 mock
  Ping 状态已接通；
- 长提示词在中英日及无空格文本下换行；风格预设支持选择、复制、编辑、保存、删除，
  最终提示词只注入一次并只在开发者模式显示；
- Reference 与 Output 共用虚拟化大图网格，支持动态列、最多三行滚动、真实指针排序和
  Undo；Reference 可按原顺序原子直通空白 Output，Provider、HTTP、生成任务均为零；
- 像素清晰卡只保留摘要与唯一运行入口，完整参数回到右侧检查器，运行中不可编辑；
- 预算、估价、月累计、费用文案和 `CostService` 产品路径已删除；Provider 回传的
  `actual_cost_usd`、`charge_id`、`provider_meta` 仅作为隐藏审计字段保留。

最终 `verify_beta_0_7.sh` 已通过。首次完整尝试发现一条旧 smoke 调用退役 cleanup
preview 后没有断言，GUT 将其标为 Risky；该夹具迁移到当前 Footer/协调器边界后定向
6/6 通过，同时最终脚本增加 Risky/Pending 非零即失败的门。随后重新完整运行并全绿。

## 2. 根因与修复边界

| 故障域 | 根因 | Fix 处理 |
|---|---|---|
| 滚动与置顶 | 内层边界把滚轮泄漏给画布；视觉提升未与命中顺序统一 | 滚动容器全程消费事件；选中项进入临时 SelectedItemLayer，项目 z-order 与 Undo 不变 |
| 生成卡 | Provider 动态能力直接塑造产品 UI，交付尺寸与远端请求尺寸混为一层 | 产品层冻结 4×3 delivery policy；1080p 仅传输为 1088 并居中裁切；OpenAI descriptor 分离 delivery/request 尺寸 |
| API 与提示词 | 设置入口埋在卡片，提示词和预设编辑路径不完整 | 顶栏统一 API 设置和开发者模式；集中预设库、草稿/保存/删除与单次前缀注入 |
| 图片可读性 | Reference 与 Output 使用不同的小图布局并重复创建控件 | 共用 176–320 logical px 的虚拟化媒体网格，只实例化可见项与缓冲项 |
| 本地直通 | Reference 仍需绕生成路径才能进入结果 | 协调器新增显式本地原子事务，失败不留下半个 Output，成功不创建网络或生成任务 |
| 像素清晰 | 卡片和检查器同时承载完整参数，职责和运行入口重复 | 卡片压缩为摘要/Footer；检查器成为参数编辑面；Footer 保持唯一执行入口 |
| 费用产品 | 旧 Beta 0.7 把 Provider 审计值扩展成预算、估价和月累计产品 | 删除产品服务、设置、UI 与调用；不删除跨模块已冻结的隐藏原始审计字段 |

PF-SEC-01、生成 POST 禁止自动重试、Output 既有动作以及 Fix 未覆盖的 1A / 2B 含义均未改变。

## 3. 提交

| 提交 | 内容 |
|---|---|
| `d47e1ce` | 固定批准计划与 B7F-0 红灯保护 |
| `ac2613f` | 卡片滚动所有权与点击置顶 |
| `95a7866` | 固定生成交付契约 |
| `45176af` | LOD 往返保留卡片输入状态 |
| `da5876f` | Reference 本地直通 Output |
| `af4417f` | 顶栏 API 设置与开发者模式 |
| `4501d16` | 可编辑风格预设库与提示词链 |
| `b9f020b` | Reference / Output 共用虚拟化媒体网格 |
| `d40c33d` | 像素清晰参数移入右侧检查器 |
| `e28711e` | 删除费用产品路径并对齐契约、i18n、回归与证据脚本 |
| `bfb7a95` | 迁移退役 cleanup preview smoke，并让最终门拒绝 Risky/Pending |

## 4. 自动化证据

开发过程只使用本地 mock HTTP 和程序生成图片；未读取真实 Key、未访问真实 API，未发送
真实 Ping、生成或编辑请求。

- Provider descriptor、OpenAI 合同、model catalog：30/30；
- 固定生成卡、18 组 i18n/几何、workspace shell：13/13；
- 运行时 en→zh→en、cleanup pipeline、workspace shell：18/18；
- Fix 保护、项目 roundtrip、契约文档、workflow、Graph、i18n、卡片编辑、媒体网格、
  cleanup inspector：63/63；
- i18n catalog、UI scaling、touched-files gdformat/gdlint、全仓 lint、`git diff --check`：通过；
- 固定截图：9/9，包含 `2560×1440 @ 100%` 的 12 张 Reference 大图；精确文件集、尺寸、
  唯一哈希、结构字段和凭据 sentinel 检查通过。

最终命令：

```bash
./pixel/scripts/verify_beta_0_7.sh
```

最终结果：

- lint / format：345 个 GDScript 文件，无问题；
- 全量 GUT + 本地 mock HTTP：134 scripts、637/637 tests、14,221 assertions、
  Risky/Pending=0、1 个既有 `error_tracker.gd` orphan；
- i18n catalog：通过；i18n source guard：6/6 tests、498 assertions；
- UI scaling：通过；English/简中 × 3 窗口 × 3 UI scale：1/1 test、2,755 assertions；
- 9/9 固定截图与 manifest：通过；
- Godot 4.6.3 官方 macOS export template 存在；本轮没有调用导出、没有构建候选；
- `git diff --check` 与基线/暂存/工作树/untracked 合并 raster guard：通过。

全量中的 `syntax_error` 是插件隔离负向夹具的预期解析错误；Godot 退出时仍打印既有
ObjectDB/resource-in-use 提示，测试与总门进程均退出 0。

受保护真实图片 smoke 默认由 `PF_ALLOW_PROTECTED_FIXTURES=1` 明确 opt-in；本任务未设置该
变量、未读取这些图片，最终门禁也不复制、不散列、不移动它们。

## 5. 人工、候选与发布状态

- **工程状态**：B7F-0 至 B7F-8 工程通过；
- **人工状态**：项目所有者尚未执行或签收人工清单；
- **候选状态**：未构建；
- **Git 状态**：未 merge 到 `main`，未 push；
- **发布状态**：未签名、未公证、未发布。

自动化和脚本截图不能替代项目所有者对滚动手感、真实窗口布局、拖放、Undo 和设置流程的
人工判断。最短复验步骤见 `BETA-0.7-FIX-MANUAL-CHECKLIST.md`。
