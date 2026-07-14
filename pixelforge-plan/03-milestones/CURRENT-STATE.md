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
- 当前卡：B7-0 契约、测试 manifest 与文档基线；尚未开始产品实现。
- B7-1 至 B7-8：待按每卡“真实红灯→最小实现→定向/相关/静态/全量绿色→范围检查→
  分卡提交”执行。红灯不得弱化测试或带入下一卡。

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

1. 完成 B7-0 八份相互一致的契约、逐条测试 manifest 和文档状态，保持 396/7718；
2. 依序完成 B7-1 至 B7-8，每卡独立提交且全量绿色；
3. B7-8 后只报告工程状态并停止，不执行 B7-9 或候选构建。

## 禁止宣称

- 不得称任何 Beta、alpha、RC 或 v1.0 已人工通过或已发布；
- 不得把自动化、agent 审查或脚本截图冒充项目所有者人工签收；
- 不得把 beta.1 的 SHA、截图或旧测试数字冒充当前证据；
- 不得把账号/协作/版本历史、ComfyUI、M8 或延期 Graph 节点改写为本轮欠债或能力。
