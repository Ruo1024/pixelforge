# PixelForge 当前真实状态

> 本页只记录可由 Git、批准计划和自动化重现的当前事实。工程通过、人工通过、候选通过和
> 发布通过必须分开；历史细节留在旧计划与 reports。

## 当前基线与执行任务

- 日期：2026-07-15。
- 唯一代码执行任务：`PF · E · Beta 0.7 Fix 执行`。
- 独立本地分支：`codex/beta0-7-fix-execution`；起点精确为
  `1b3f93481be5e8fc517344d2460abc6df2c6ad1c`。
- 批准计划：`BETA-0.7-FIX-PLAN.md`；SHA-256 为
  `8113a8ed40737bcc5d14cc663fd4222a9e27b45c7f96cea75e39143a054b789c`。
- B7F-0 至 B7F-8 的产品代码、测试、相关契约、i18n 和固定截图脚本已实现并提交；
  工程报告与人工清单已建立，最终 `verify_beta_0_7.sh` 已通过。
- 本任务未 merge 到 `main`、未 push、未构建候选、未签名/公证、未发布。

## Beta 0.7 Fix 已实现结果

1. 卡片内层滚动在上下边界仍拥有滚轮；点击卡片临时进入选中层，视觉与命中同步置顶，
   不修改项目 z-order 或 Undo。
2. 生成卡固定显示 GPT Image 2、API 主机、720p/1080p/2K/4K、横/竖/方和 1–16 数量；
   5–16 在任何 Output 槽、Provider 或 task 创建前确认。1080p 只在请求层使用 1088，
   交付层仍为标准 1080 并居中裁切。
3. API 设置和开发者模式位于顶栏；Key 使用安全凭据存储。所有自动化网络验证只连本地
   mock，没有真实 Ping、生成或编辑请求。
4. 长提示词换行；风格预设具备选择、复制、编辑、保存和删除；最终前缀只注入一次，
   开发者预览只在开发者模式出现。
5. Reference 与 Output 共用大图虚拟化网格、动态列和最多三行滚动；Reference 支持真实
   指针排序与 Undo，并可按顺序原子直通空白 Output，网络和生成任务计数为零。
6. 像素清晰卡压缩为摘要与唯一 Footer 运行入口；完整参数由右侧检查器读写并进入 Undo，
   运行中禁用编辑。
7. 预算、估价、费用 UI、月累计和 `CostService` 已删除；`actual_cost_usd`、`charge_id`、
   `provider_meta` 仅作为隐藏审计字段保留。

## 固定边界

- Fix 未覆盖的 1A / 2B 含义保持冻结；PF-SEC-01 不变。
- 生成 POST 自动重试仍为 0；timeout、429、5xx 或不确定提交不得静默重发。
- Output 的预览、编辑、下载、拆出、Undo、历史与重试动作继续保留。
- Provider v2 生产范围仍只有 OpenAI Image 与 RetroDiffusion；ComfyUI 和其他实验后端
  保持禁用/不注册。
- 受保护真实图片只允许项目所有者显式 opt-in；本任务不读取、不复制、不散列、不提交。

## 工程、人工、候选与发布状态

- **工程状态**：B7F-0 至 B7F-8 工程通过；最终门禁为 134 scripts、637/637 tests、
  14,221 assertions、Risky/Pending=0、1 个既有 orphan；lint、i18n、UI scaling、18 组
  几何、9 张固定截图、export-template 存在性、diff 与 raster 守护通过。
- **人工状态**：未验收；自动化和脚本截图不构成人工签收。
- **候选状态**：未构建。
- **发布状态**：未 merge、未 push、未签名/公证、未发布。

## 下一步

1. 将工程报告与 `BETA-0.7-FIX-MANUAL-CHECKLIST.md` 交回 P / 项目所有者；
2. 等待项目所有者统一人工验收。未获新授权不得构建候选、merge、push 或发布。

## 禁止宣称

- 不得称 Beta 0.7 Fix 已人工通过、候选通过或发布；
- 不得把自动化、agent 审查或脚本截图冒充项目所有者签收；
- 不得把旧 Beta 0.7 候选、SHA、费用 UI 或旧截图冒充当前 Fix 证据。
