# PixelForge 当前真实状态

> 本页只记录当前可由 Git、批准执行书和自动化重现的事实。工程通过、人工通过和
> 发布通过必须分开；历史细节留在旧计划、reports 与 Git。

## 当前基线与授权

- 日期：2026-07-14。
- 唯一写入分支/worktree：本地 `main`，
  `/Users/ruo/Desktop/pixelforge/scratch/worktrees/main-integration`。
- Beta 0.6 beta.2 工程基线：`26a60708233f75cad7673cb9f80d9532f00c9d25`。
- 阶段 A 的 ancestry、工程报告、clean committed state 与测试证据确认：
  `codex/beta0-6-adaptive-shell-repair` 是唯一最小必要 tip；`0a746ce`、旧 Beta 0.2、
  B3/B4 等已被它完整包含，实验/否决分支未合并。main 从 `bdfeafc` 正常 fast-forward
  到 `26a6070`；未 reset/rebase/force，未删除分支/worktree，未 push。
- 基线全量：396/396 tests、7718 assertions、1 个已知 orphan，exit 0。三张受保护
  real fixture 只按既有批准流程临时恢复并核 hash，测试后立即删除；不在 Git、候选、
  截图或外发物中常驻。

## 当前执行任务

- 角色：唯一执行任务 E。
- Goal：审计并集成有效本地分支后，在 main 连续完成批准的 Beta 0.7 B7-0 至 B7-8，
  保持相关和全量自动化绿色并按卡提交。
- 批准执行书：`BETA-0.7-PLAN.md`，固定 SHA-256
  `655597660e21acdf7a4d5e2bab388bdf54586875ee59921211cdc1dad2f073f4`。
- B7-0 已完成并提交：`c476c2a` 固定八份契约、228 条 requirement manifest、旧测试
  替换台账与本地 main 文档基线；批准计划字节与固定 SHA 保持不变。
- B7-1 已完成并提交：`9fcac09`。敏感 Header/URL/错误表面脱敏；生成 POST
  强制单次尝试；OpenAI 安全 GET 最多三次且使用可注入 RetryScheduler；删除 Retro
  哑元生成验证，configured 状态只在用户明确首次真实生成后转 verified/invalid；Provider
  meta 改为显式白名单；en/zh_CN 同步。凭据 sentinel 确认原始 mock transport 收到，
  log/task/PFError/当前持久化表面均未收到。
- B7-1 全量：406/406 tests、7805 assertions、1 个既有 orphan，exit 0；三张受保护
  fixture 再次按固定 hash 临时恢复并在测试后删除。i18n 与 v1 security 静态守护绿色。
- B7-2 已完成并分片提交，最终代码收口为 `aaf3ae2`。按 `B7-DEC-OWNER-01`
  完成 v2 hard cut：Project/Graph/Provider/Plugin/Template/Clipboard 不接受 v1，不保留
  alias；PromptPreset 与 CleanupPreset 拆分；旧 batch UI 仅从 `result_slots` 的
  `succeeded && !detached` 唯一投影读取。生产 Provider 目录仅暴露 OpenAI Image 与
  RetroDiffusion，mock 仅供内部自动化。
- B7-2 全量：98 scripts、493/493 tests、9391 assertions、1 个既有 orphan，exit 0；
  全量 lint 274 文件无问题。三张受保护 fixture 复核固定 hash 后临时恢复，
  测试后立即删除，无 `.import`、无 raster 暂存。日志仅含预期故障注入
  `syntax_error` 和既有 7-resource 退出提示。
- B7-4 的最终 GenerationRunCoordinator/history 和 B7-5 的最终 Output UI 仍待各自
  red→green，B7-2 没有提前完成或弱化它们。
- B7-3 已完成：真实红灯提交 `d8be104`，实现提交 `ca2e740`。请求规划在任何凭据、
  预算、Output 或网络副作用前完成本地验证；OpenAI Image 与 RetroDiffusion 的 mock
  transport 覆盖成功、Partial、超时、鉴权失败、取消和显式重试；费用统一使用整数
  micro USD 并按 charge/request 去重；失败槽重试与完整重新生成共用 plan→预算预检→
  明确授权门，未确认或被阻止时不产生请求。独立只读复核未发现剩余 B7-3 blocker。
- B7-3 全量：542/542 tests、9995 assertions、1 个既有 orphan，exit 0；lint 292 文件
  无问题。三张受保护 fixture 按固定 hash 临时恢复，测试后立即删除，未暂存 raster。
- 当前下一卡：B7-4 GenerationRunCoordinator、新 Output/history、生成卡、运行边和错误
  对话框收口；继续按
  “真实红灯→最小实现→定向/相关/静态/
  全量绿色→范围检查→分卡提交”执行，红灯不得弱化测试或带入下一卡。

## Beta 0.7 固定产品边界

1. Project/Graph/Provider/Plugin/Template/Clipboard 一次性硬切 v2；不迁移 v1、不留
   adapter/alias。PromptPreset 与 CleanupPreset 各为 v1 新对象。
2. 生成与清洗主路径只有 text_prompt、object_list、prompt_preset、image_input、
   reference_set、ai_generate、pixel_cleanup、batch（用户名“结果”/“Output”）。
3. StylePreset 和 size_spec 从主路径退役；编辑器、地图、palette、抠图、切片、描边等
   独立能力不能因此删除或重设计。
4. 每次完整生成/清洗创建新 Output；最多显示 3 行结果并在卡内滚动；历史保留；清洗
   是显式手动、逐张单并发且不覆盖源素材。
5. Provider v2 生产范围只有 OpenAI Image 与 RetroDiffusion；ComfyUI 和其他实验后端
   保持禁用/不注册。

## 工程、人工与发布状态

- Beta 0.6 beta.1 已被项目所有者否决，只保留历史证据。
- beta.2 自动化工程基线已集成本地 main；这不把 Beta 0.6 改写为人工通过或发布通过。
- Beta 0.7 当前开发中，尚未工程通过、人工通过或发布通过。
- 本 Goal 禁止真实付费 API、Computer Use、未许可图片、B7-9、候选构建、push、发布、
  强制改写历史和删除分支/worktree。

## 下一步

1. 从 B7-4 开始依序完成至 B7-8，每卡先保存真实红灯，再全量转绿并独立提交；
2. B7-4 删除临时 legacy adapter，以唯一协调器建立新 Output/history 与运行状态；
3. B7-8 后只报告工程状态并停止，不执行 B7-9 或候选构建。

## 禁止宣称

- 不得称任何 Beta、alpha、RC 或 v1.0 已人工通过或已发布；
- 不得把自动化、agent 审查或脚本截图冒充项目所有者人工签收；
- 不得把 beta.1 的 SHA、截图或旧测试数字冒充当前证据；
- 不得把账号/协作/版本历史、ComfyUI、M8 或延期 Graph 节点改写为本轮欠债或能力。
