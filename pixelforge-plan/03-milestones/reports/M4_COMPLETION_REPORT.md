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
