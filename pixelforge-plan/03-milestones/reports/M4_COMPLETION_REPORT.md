# M4 工程完成报告（diff 模式）

> 长期本地分支：`codex/pixelforge-full-plan-goal`。M4-V1 产品实验仍无 go/no-go；以下施工均为“暂定工程继续，产品 go/no-go 待最终统一验收”。

## 2026-07-11 M4-1 HTTP 基础设施补全

### 服务对象与用户动作

- 服务对象：通过云 Provider 批量生成素材、需要在限流或短暂断网后继续工作的用户。
- 入口：Provider 创建 JSON/raw HTTP 任务并交给统一 TaskQueue；反馈：原位任务进度与归一化失败；出口：解析后的响应或可操作 PFError；交接：M4-2～M4-4 Provider/UI 消费同一封装。
- 原痛点：`infra/http_client.gd` 只是同步占位，真实 Provider 各自持有 HTTPRequest，无法统一超时、退避、取消与日志脱敏。

### 本轮实现

- 每个请求尝试创建独立 HTTPRequest，完成即释放；封装返回外部异步 PFTask，可经 TaskQueue 取消并保持统一终态。
- JSON/raw 请求支持默认 60 秒超时（生成类可传 180 秒）、可配置重试次数与指数退避；401/403、402、429、4xx、5xx、超时与网络失败映射到 PROVIDER-API §6 错误码。
- 请求日志只记录 URL、方法、尝试次数和脱敏头；Authorization、Proxy-Authorization、X-Api-Key 与 Api-Key 永远替换为 `[REDACTED]`。
- 测试门禁启动独立本地 Python HTTP server，覆盖成功、401、429、超时、畸形 JSON，以及 429 三次重试的 40/80/160ms 指数节奏。

### 修改文件

- `pixel/infra/http_client.gd`
- `pixel/tests/fixtures/http/mock_http_server.py`
- `pixel/tests/integration/test_http_client.gd`
- `pixel/tests/unit/test_infra_clients.gd`
- `pixel/scripts/run_tests.sh`
- `pixel/scripts/verify_m4_1.sh`
- `pixel/CHANGELOG.md`
- `pixelforge-plan/03-milestones/CURRENT-STATE.md`
- 本报告

### 自动验证命令与结果

- `./pixel/scripts/lint.sh`：128 files，无问题。
- `./pixel/scripts/run_tests.sh`：204/204 tests、1550 assertions 通过；首次运行发现并修正新增 Node orphan 与预期畸形 JSON 的错误控制台噪声，最终不得新增这两项。
- `./pixel/scripts/verify_m4_1.sh`：复用 M4-V1、M3.1、UI 缩放、模板与 headless 门禁，并检查 fixture server 接线与脱敏守护。
- `git diff --check`：提交前执行。

### Agent 实机冒烟

- Godot 4.6.3 headless 真实连接本机 TCP HTTP server；成功、失败、超时与四次实际请求均走场景树 HTTPRequest，而非直接调用映射函数。
- 429 重试实际时间戳满足至少 30/65/130ms 间隔，验证指数退避没有阻塞主线程。
- 本卡不新增用户可见 UI；该冒烟只算 agent 工程证据，不算用户人工签收。

### 最终统一人工验收追加项

1. 在 M4 Provider UI 中触发一次有效请求，预期生成任务异步完成且画布持续可操作。
2. 断网后触发请求，预期显示网络失败与重试建议，不崩溃、不泄漏 key。
3. 触发或模拟限流，预期按策略退避后成功或显示 `rate_limited` 人话提示。

人工状态：**待最终统一验收**。

### 已知失败、限制和延期

- M4-1 只完成通用传输层；M4-V1 OpenAI 专用请求迁移与大图解码线程化随 M4-4 集成卡完成，避免在基础设施卡跨界改 Provider 行为。
- 既有 GUT `error_tracker.gd` orphan 与退出资源警告仍待归因；本卡修复了自己一度新增的 client orphan，不扩大已知警告数量。
- 真实公网波动与真实 Provider 限流仍待凭据可用后的最终统一验收；fixture 不能替代真实 API 证据。

### 对应本地提交与关键 diff

- 对应提交：`M4-1 complete production HTTP client`（哈希以 Goal 分支日志为准）。
- diff 模式：占位 client 替换为 PFTask 异步实现；新增本地 server、7 个集成断言组与里程碑门禁；不内联全量源码。

## 2026-07-11 M4-2 凭据管理与 Provider 设置 UI

### 服务对象与用户动作

- 服务对象：需要自行提供云 Provider key、又不希望 key 进入项目或日志的本地创作者。
- 入口：`File > Provider Settings...`；反馈：能力摘要、保存/验证状态；出口：验证通过的 Provider；交接：AI Generate 节点只列 mock 与已验证项。
- 原痛点：M4-V1 只有 OpenAI 会话输入，关闭即丢失；没有通用 schema UI、默认 Provider、重启解密或节点过滤闭环。

### 本轮实现

- `PFCredentialStore` 用设备标识 + 随机盐执行 PBKDF2-HMAC-SHA256，拆分 AES-256-CBC 与 HMAC-SHA256 密钥；PKCS#7 填充、随机 IV、encrypt-then-MAC，配置文件只留 base64 密文元数据。
- 威胁模型诚实限定：防止 credentials.cfg 裸文本泄漏，不防同用户权限恶意程序；Godot 官方亦提示设备标识可能变化或被伪造，因此最终验收需覆盖设备变化后的可恢复错误。
- ProviderService 补齐配置 CRUD、重启解密、默认 Provider、异步验证状态与最近验证持久化；更换或删除 key 会清除验证状态。
- 设置对话框从每个 Provider 的 `get_config_schema()` 和 capabilities 自动生成；password 使用遮蔽输入，已保存值只显示占位，不回填明文。
- Graph 参数对话框的 Provider 下拉只列 `mock` 与保存且验证通过的 Provider；未验证项不能误入运行链。
- PBKDF2 实现依据 RFC 8018，并在 `06-algorithm-refs/pbkdf2/INTEGRATION.md` 记录来源、许可与本项目 profile。

### 修改文件

- `pixel/services/credential_store.gd`
- `pixel/services/provider_service.gd`
- `pixel/services/settings_service.gd`
- `pixel/ui/dialogs/provider_settings_dialog.gd`
- `pixel/ui/dialogs/graph_node_params_dialog.gd`
- `pixel/ui/shell/m2_1_ui_controller.gd`
- `pixel/ui/shell/strings.gd`
- `pixel/plugins/provider_openai/openai_image_provider.gd`
- `pixel/tests/unit/test_credential_store.gd`
- `pixel/tests/integration/test_provider_service.gd`
- `pixel/tests/fixtures/providers/fake_provider.gd`
- 相关 UI/OpenAI 契约测试、门禁、CHANGELOG、CURRENT-STATE 与 PBKDF2 引用说明

### 自动验证命令与结果

- `./pixel/scripts/lint.sh`：133 files，无问题。
- `./pixel/scripts/run_tests.sh`：211/211 tests、1584 assertions 通过；覆盖 PBKDF2-SHA256 已知向量、无明文、错误设备拒绝、服务重启解密、成功/失败验证与节点过滤。
- 首轮完整门禁中既有 Magic Wand 性能哨兵出现一次 73.18ms 瞬时超限；未改代码，定向复测 27.35ms，随后两轮完整门禁分别 26.59ms、26.66ms 并全绿，记录为机器负载型波动而非 M4-2 回归。
- `./pixel/scripts/check_ui_scaling.sh`：随 `verify_m4_2.sh` 复用门禁；新 UI 没有手动 scale、硬编码字号或组件级注入。
- `./pixel/scripts/verify_m4_2.sh`：复用 M4-1/M4-V1/M3.1 全门禁，并静态检查 AES-CBC、PBKDF2 向量与节点过滤守护。
- `git diff --check`：提交前执行。

### Agent 实机冒烟

- 环境：macOS Retina、Godot 4.6.3 独立窗口、全新 `/tmp` HOME，界面倍率 2.0。
- `File > Provider Settings...` 可找到；对话框显示 OpenAI GPT Image 2 能力摘要，API key 输入以圆点遮蔽。
- 使用明确虚构的 `fixture-not-a-real-key` 点击 Save Credentials；UI 清空输入并显示“Saved credential”占位和“validate before use”，未点击 Validate、未发起外部请求。
- `credentials.cfg` 只出现 salt/iv/ciphertext/mac，grep 不含虚构明文；关闭并用同一干净 HOME 重启后仍显示已保存占位，证明生产迭代数下可解密恢复。
- 本节是 agent 冒烟，不是用户人工通过，也不证明真实 key 有效。

### 最终统一人工验收追加项

1. 打开 Provider Settings，确认能力信息可理解、key 输入遮蔽；保存真实测试 key 后重启，预期仍显示已保存但不回填明文。
2. 点击 Validate：正确 key 显示验证通过，错误 key 显示清晰原因；期间 UI 继续可操作。
3. 新建/编辑 AI Generate 节点：未验证 Provider 不出现，验证后出现；更换或删除 key 后再次隐藏。
4. 检查 `credentials.cfg`、settings、项目、日志与崩溃输出不含 key；模拟设备标识变化时给出可恢复失败，不静默破坏项目。

人工状态：**待最终统一验收**。

### 已知失败、限制和延期

- 没有真实 key，因此 Validate 的真实 OpenAI 成功路径仍待最终统一验收；fixture Provider 仅证明服务状态机。
- 设备标识变化会使旧密文无法解密；当前返回未配置状态，不提供跨设备密钥迁移，这符合本地威胁模型但必须写入最终 FAQ。
- M4-V1 的会话输入入口暂留作实验兼容路径；M4-4 完整 OpenAI 集成时统一到 Provider Settings，避免两个长期入口并存。

### 对应本地提交与关键 diff

- 对应提交：`M4-2 add encrypted provider settings`（哈希以 Goal 分支日志为准）。
- diff 模式：新增 credential store/schema UI/验证状态；ProviderService 从会话注册表扩为完整配置中心；测试不存任何真实 key。

## 2026-07-11 M4-3 RetroDiffusion Provider

### 服务对象与用户动作

- 服务对象：希望直接获得像素原生候选、减少伪像素清洗负担的本地创作者。
- 入口：Provider Settings 保存并验证 RetroDiffusion，再在 AI Generate 节点选择它；反馈：统一队列进度与人话错误；出口：真实 batch 卡及逐图 provenance；交接：批次审阅、清洗与导出沿用既有工作台。
- 原痛点：节点图只能跑 mock 或 M4-V1 OpenAI 特例，RetroDiffusion 没有插件、请求适配、worker 解码与费用元数据。

### 本轮实现

- 新增内置 `provider_retrodiffusion` 插件，按 2026-07-11 官方 `api-examples` 重新核对 `POST /v1/inferences`、`X-RD-Token`、`prompt_style`、`num_images`、`remove_bg`、`check_cost` 与响应字段。
- 按当前官方模型限制把总能力边界诚实收窄为 16～384，而不是计划调研快照的 16～512；默认 style 按尺寸映射为 `rd_plus__low_res`、`rd_pro__default`、`rd_fast__default`，显式 provider hint 优先直传。
- 生成经通用 PFHttpClient，base64 PNG 解码放入 WorkerThreadPool；返回 `raw_pixel=true`、逐图 seed、实际 credit 消耗与 model/balance/style 元数据。
- 401/403、余额不足、429、网络、超时与服务端失败映射到统一 Provider 错误；请求任务、日志、fixture、项目与 provenance 均不含 key。
- “Run Selected Graph” 从 OpenAI 特例扩为所有已验证非 mock Provider；本地真实 HTTP fixture 已走 UI 选中 graph → TaskQueue → worker 解码 → batch 替换 → provenance 的完整闭环。
- 官方 README 只给出 RD_PRO 单图示例消耗 0.25，未提供可核验的完整静态 style 价目表；因此只对 `rd_pro__default` 给出带日期的确定性估算，其余返回未知，避免伪造精度。

### 修改文件

- `pixel/plugins/provider_retrodiffusion/` 插件清单、入口与 Provider
- `pixel/infra/http_client.gd` worker transform 与单任务取消
- `pixel/services/provider_service.gd`
- `pixel/ui/shell/openai_generation_controller.gd` 与 `m2_1_ui_controller.gd` 的通用云 Provider 路由
- `pixel/tests/fixtures/providers/retrodiffusion_success.json`、本地 HTTP server 与 RetroDiffusion 契约/UI 集成测试
- `pixel/scripts/lint.sh`、`verify_m4_3.sh`、CHANGELOG、CURRENT-STATE 与本报告

### 自动验证命令与结果

- `./pixel/scripts/lint.sh`：138 files，无问题；同时把 `plugins/` 纳入全仓 gdformat/gdlint 门禁。
- `./pixel/scripts/run_tests.sh`：218/218 tests、1639 assertions 通过；覆盖 4 图 fixture、实际本地 TCP、worker 解码、错误映射、费用与 provenance，以及 UI graph 闭环。
- 首轮新增 UI 测试因 mock server 固定只回 1 图而失败；根因确认后让 server 按官方 `num_images` 回 1～4 图，未修改生产逻辑，复跑全绿。
- `./pixel/scripts/verify_m4_3.sh`：复用 M4-2 及其上游完整门禁，并守护官方鉴权头、worker 解码、UI 闭环和 key 泄漏。
- `git diff --check`：提交前执行。

### 最终统一人工验收追加项

1. 使用真实测试 key 分别生成 16×16、128×128 各一张，预期成功进入画布 batch，prompt/seed/model/cost provenance 完整。
2. 在真实节点链选择 RetroDiffusion，运行后执行项目调色板清洗并导出；确认原生像素没有不必要的 detect 重采样，最终颜色属于目标调色板。
3. 触发错误 key、余额不足、限流和断网，预期提示可理解、UI 不冻结、key 不出现在项目或日志。

人工状态：**待最终统一验收（当前无真实 RetroDiffusion key，不能宣称真 API 通过）**。

### 已知失败、限制和延期

- 没有真实 key，故计划要求的公网 16×16/128×128 与真实 credit 扣费证据尚未执行；录制 fixture 和本地 TCP 只构成工程证据。
- 当前最小 graph 仍由项目 style preset 直接进入生成请求，生成后的调色板对齐仍由批次菜单清洗完成；独立 style/cleanup 图节点不是本卡新增范围，最终旅程需在后续图执行扩展后统一验收。
- RetroDiffusion 官方示例当前没有完整静态价目表，非 RD_PRO 估算显示未知；M4-5 的预算逻辑必须允许 unknown，不能假装为 0。
- 既有 GUT `error_tracker.gd` orphan 与退出资源警告不变。

### 对应本地提交与关键 diff

- 对应提交：`M4-3 add RetroDiffusion provider`（哈希以 Goal 分支日志为准）。
- diff 模式：新增 RetroDiffusion 插件、worker 解码与通用云 graph 路由；fixture/本地 HTTP 覆盖真实异步路径；不内联全量源码。

## 2026-07-11 M4-4 OpenAI GPT Image 2 Provider

### 服务对象与用户动作

- 服务对象：需要通用生成兜底、并依赖 PixelForge 把高分辨率伪像素清洗为项目素材的创作者。
- 入口沿用 Provider Settings 与 AI Generate 节点；出口仍是统一 batch/provenance，不再保留 Provider 内自建 HTTPRequest 的第二套生命周期。

### 本轮实现

- 使用 openai-docs 技能核对官方开发者文档；Docs MCP 已安装但需重启 Codex 才能在当前任务暴露，故按技能规则回退到 OpenAI 官方域名。
- 当前官方模型页确认 `gpt-image-2` 与 `/v1/images/generations`；API reference 明确 GPT Image 模型支持 `background=transparent`、`output_format=png`、low/medium/high 与三档尺寸。该证据覆盖并修正计划快照中“GPT Image 2 不支持透明背景”的过期假设。
- OpenAI Provider 迁移到 PFHttpClient，验证与生成共用脱敏、取消、超时和退避；base64 PNG 解码放 WorkerThreadPool。
- 生成请求固定透明 PNG、low quality，并按目标横纵比映射 1024×1024 / 1536×1024 / 1024×1536；目标真像素尺寸和风格约束仍写入 provider 适配 prompt。
- 返回保留 `raw_pixel=false`，并记录 usage、目标尺寸、输出尺寸、quality、background、format；错误映射覆盖 content policy、auth、rate limit、timeout、network 与 5xx。
- 官方 GPT Image 2 模型页当前只引导动态 pricing calculator，没有稳定可核验的逐图静态表，因此 estimate 继续返回 unknown，避免硬编码推测价格。

### 自动验证命令与结果

- `./pixel/scripts/lint.sh`：138 files，无问题。
- `./pixel/scripts/run_tests.sh`：219/219 tests、1648 assertions 通过；新增真实本地 TCP、共享 HTTP 与 worker 解码测试。
- `./pixel/scripts/verify_m4_4.sh`：复用全部上游门禁，并守护模型、透明 PNG、worker 测试和 key 泄漏。
- 按用户最新指令，不执行逐模块实机冒烟；统一留到 M7 后总验收。

### 最终统一验收与限制

- 待真实 OpenAI key 验证组织权限、透明 PNG 输出、网络错误和同提示词双 Provider 对比；当前 fixture 不能替代公网证据。
- 对比图不写入仓库：真实/生成测试图片受工作区红线约束；最终可由用户在本地临时目录审阅。
- 对应本地提交：`M4-4 complete OpenAI image provider`（哈希以 Goal 分支日志为准）。

## 2026-07-11 M4-5 费用与预算仪表

### 本轮实现

- 新增 CostService，按自然月与 Provider 分桶持久化实际费用；未知费用使用 -1 且绝不按 0 计入，避免误导。
- 云生成完成即按 Provider 响应的总 cost 入账；画布底栏持续显示本月累计，已知 run estimate 时显示“Next ≈”。
- Provider Settings 增加全局月度 USD 预算（0 表示无限制）；已知估算导致本月超预算时，在任务创建前弹确认框，取消不会发送请求，确认才继续。
- estimate 统一调用 Provider 合同；RetroDiffusion 当前可核验 RD_PRO 价目参与预算，OpenAI 与 Retro 其他 style 的未知价不做虚假拦截。

### 自动验证与统一验收口径

- `./pixel/scripts/lint.sh`：140 files，无问题。
- `./pixel/scripts/run_tests.sh`：222/222 tests、1661 assertions 通过。
- 覆盖虚拟 Provider 估算与实际误差 0、按月/provider 累加、unknown 忽略、无预算放行、已知超额拦截，以及真实 Retro UI graph 确认后继续执行。
- `./pixel/scripts/verify_m4_5.sh` 复用 M4 全部上游门禁；按用户指令不做模块级实机冒烟，M4 的真实 key、网络波动、费用显示与双路对比统一留到最终一次验收。

### M4 工程结论

- M4-1～M4-5 工程闭环完成于 Goal 隔离分支；两 Provider、凭据、异步传输、费用与节点运行均有自动化证据。
- 产品 go/no-go、真实 API、三人 A/B 和真人体验均仍是**待最终统一验收**；不得把本节解释为 M4 产品 go。
- 对应本地提交：`M4-5 add provider cost and budget controls`（哈希以 Goal 分支日志为准）。
