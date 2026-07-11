# M4 — 云端 AI Provider 接入（功能3b；完整规格暂冻结）

> 目标：先用 M4-V1 验证“集成生成是否显著优于外部生成后导入”；只有 go 决策后，才执行后续完整 Provider 规格。
> 依赖：M3.1 受邀 alpha 出口通过（ai_generate 节点已就位，本里程碑替换 mock）。
> 现状依据：RESEARCH-NOTES §2（两家 API 能力/定价 2026-06 核实）。

---

## M4-V1 单 Provider 价值验证（当前唯一激活卡）

**目标**：用一个真 Provider 走通固定提示词 → 真实 batch → 清洗/对比 → 导出，只验证集成生成的用户价值，不提前建设完整 M4。

**范围**：
- 执行前只选一家最适合暴露“生成后清洗”价值、且当前可获得测试凭据的 Provider；不同时接第二家。
- 提供最小的会话内 password 输入，由实验主持人在测试前配置且不持久化；不建设通用凭据中心。若此路径需要改变 `PROVIDER-API`，必须先走契约修订批准；key 不进入项目、日志和 fixture。
- 只实现该纵切必需的请求、失败反馈、provenance 和一次可重试网络失败；不做通用设置 schema、月度费用仪表、预算拦截或营销对比图。
- 优先复用 M3.1 AR-3 的 3 名测试者，不另招一批；与“同一 Provider 在外部生成后手动导入”做 A/B。
- 两条路径均从“测试者拿到同一提示词任务且工具就绪”开始计时，到“测试者接受一张素材并从 PixelForge 成功导出到目标目录”结束，比较三人的中位数与继续使用意愿。

**go / no-go**：
1. 集成路径的首个可用素材时间相对外部导入降低约 30%，且至少 2/3 测试者愿意继续承担 API key/费用 → `go`，解冻 M4-1～M4-5。
2. 本地清洗有价值但集成生成无明显增益 → `no-go`，保持 v0.1 产品，完整 M4 暂停。
3. 结果受明显交互阻断污染 → 只修对应阻断后复测一次，不横向扩功能。

**验收产物**：一页实验报告，包含 Provider 选择依据、三人任务记录、时间对比、失败样本和明确 go/no-go；不得以“API 调通”替代产品结论。

**工程底线**：对应 Provider 契约 fixture、网络失败映射、provenance 与 key 泄漏 grep 必须自动化通过；产品实验不能替代工程门禁。

---

> 以下 M4-1～M4-5 是 go 后的完整规格。M4-V1 作出 go 决策前全部暂停，不得拆卡施工。

## M4-1 HTTP 基础设施补全（infra/http_client.gd）

**目标**：生产级 HTTP 封装。

**技术实现指导**：
- 包装 HTTPRequest（每请求新建节点挂 infra 管理的容器，完成即释放——规避单节点并发限制）：`request_json(method, url, headers, body, opts) -> PFTask`；opts：timeout（默认 60s，生成类 180s）、retries（默认 0）、backoff。
- 错误归一化：HTTP 状态/超时/解析失败 → PFError code 映射表（PROVIDER-API §6）。
- 大响应（base64 图）解码放 WorkerThreadPool（防主线程卡顿）。
- 凭据注入由 provider 层做，本层不知道 key 概念（分层）。
- 全局请求日志（脱敏：Authorization 头打码）开关于设置。

**验收标准**：
1. 单测（本地 mock HTTP 服务器，Python 脚本起在 CI）：成功/401/429/超时/畸形 JSON 五场景 PFError 映射正确。
2. 429 + retries=3 时指数退避重试节奏正确（时间戳断言）。

---

## M4-2 凭据管理与 Provider 设置 UI

**目标**：PROVIDER-API §3 的 provider_service 完整实现 + 设置页。

**技术实现指导**：
- `provider_service.gd`：注册表、当前默认 provider、凭据 CRUD（Crypto AES-256-CBC，key=机器 id 派生 PBKDF2；**安全注释明示**：本地加密防的是"裸文本泄漏"，不防本机恶意程序——诚实的威胁模型）。
- 设置页 UI：provider 列表 → 每项按 `get_config_schema()` 自动渲染表单（含 password 型输入框遮蔽）+ "验证"按钮（validate_credentials 任务，结果图标）+ capabilities 只读展示（用户能看懂该选谁）。
- ai_generate 节点的 provider 下拉仅列"已配置且验证通过"项 + mock。

**验收标准**：
1. key 保存后 credentials.cfg 无明文（grep 断言）；重启可解密使用。
2. 错误 key 验证失败提示清晰；节点下拉过滤逻辑正确。

---

## M4-3 RetroDiffusion Provider（plugins/provider_retrodiffusion/）

**目标**：首个真 provider，主打像素原生生成。

**技术实现指导**：
- 按其公开 REST API（api-examples repo 为准；端点/参数实现时再核对——**调研快照仅作起点，落地前必须重新打一次真实 API 确认字段**，记录差异到本卡交付说明）。
- capabilities：native_pixel=true, transparent_bg=true（remove_bg 参数）, sizes 16–512, animation=false（v1 不接动画端点）。
- style 映射：StylePreset.provider_hints.retrodiffusion.style 直传；无 hint 时回退 prompt_template 拼接。
- 结果 raw_pixel=true → ai_generate 下游 pixel_cleanup 自动跳过 detect（直接量化到项目色板——仍需跑，保证色板一致性）。
- 费用：响应含 credit 消耗 → PFGenResult.cost；estimate_cost 按官方价目硬编码表（注释标注价目日期，UI 显示"估算"）。
- 限流与配额错误映射演练（PROVIDER-API §6）。

**验收标准**：
1. 契约测试（录制 fixture）全绿：成功批量 4 图解码、401/配额/限流映射。
2. --manual 真 API 冒烟：16×16 与 128×128 各 1 张成功入画布，provenance 完整（prompt/seed/model/cost）。
3. 节点链端到端（真 API，手动）：旅程 7 节点链产出真实素材且全自动对齐色板。

---

## M4-4 OpenAI Image Provider（plugins/provider_openai/）

**目标**：通用兜底 provider（当前推荐 `gpt-image-2`；伪像素输出 → 清洗管线主战场）。

**技术实现指导**：
- 端点 images/generations；按 2026-07-11 官方能力，`gpt-image-2` 不支持透明背景，尺寸映射使用 1024/1536 固定档并通过纯色对比背景辅助后续抠图。**结果必然伪像素**：raw_pixel=false，依赖下游清洗（这正是产品价值闭环的展示场景）。
- prompt 组装强化：追加"pixel art, {base_size}x{base_size} sprite, flat colors, no anti-aliasing"等模板尾缀（在 provider 内追加而非污染通用模板——平台适配职责，PROVIDER-API §4）。
- moderation/content_policy 错误映射；组织级 key 校验。
- 费用估算：按 quality 档价目表。

**验收标准**：
1. 契约测试全绿（fixture）。
2. --manual：同提示词经 OpenAI（伪像素→清洗）与 RetroDiffusion（原生）双路产出对比图存档 docs/，色板一致性肉眼过关——这张对比图同时是营销素材。

---

## M4-5 费用与配额仪表

**目标**：体验原则"本地数据主权+透明"：用户随时知道花了多少钱。

**技术实现指导**：
- task 完成时 cost 累计入 settings（按 provider/月分桶）；状态栏小组件显示本月累计；超用户设定预算（默认无）时新任务前确认弹窗。
- Run 前估算：图执行计划遍历 ai_generate 节点 estimate_cost 求和 → 工具栏显示"≈$0.12"。

**验收标准**：
1. mock provider 设定虚拟价格跑批量 → 累计与估算误差 = 0；预算拦截弹窗触发正确。

---

## M4 整体验收

- v0.3：无 ComfyUI、无本地模型，纯云端的端到端素材生产可用。两 provider 在真实网络波动下（断网重连、限流）不崩、错误提示人话。
- 安全自查：日志/项目文件/崩溃转储均无 key 泄漏（自动化 grep 测试）。
