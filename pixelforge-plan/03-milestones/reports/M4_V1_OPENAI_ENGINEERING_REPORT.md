# M4-V1 OpenAI 工程准备报告（diff 模式）

> 日期：2026-07-11；原工程分支：`codex/m4-v1-openai`；已由长期本地分支 `codex/pixelforge-full-plan-goal` 继承。
> 结论：**工程准备完成；M4-V1 产品实验未完成，不作 go/no-go。**

## 1. 路线与边界

- 原规划要求先通过 M3.1。项目所有者明确“暂时不测试，继续沿最初设定开发”，因此本次仅将 M4-V1 推到可测试状态；M3.1 人工状态仍为待验收。
- 只选 OpenAI 一家 Provider。`gpt-image-2` 的高分辨率、非透明输出更容易暴露 PixelForge 清洗/抠图的增益，符合价值验证目的。
- 没有施工冻结的通用凭据中心、费用仪表、第二 Provider、完整 HTTP 基础设施或 M4-1～M4-5。
- 当前环境没有可用 OpenAI API key，未发起付费真实请求；不得把 fixture 通过写成 API 已调通。

## 2. 实现差异

- 新增契约既定的最小 `PFProvider` / `PFPlugin` / `PFPluginAPI` 接口与 `ProviderService` 注册表，内置 OpenAI Provider 仍按插件入口注册；会话清除/存在性检查保持 Provider 可选扩展，没有升格为跨模块契约。
- OpenAI key 只保存在 Provider 实例内存；password 输入提交或关闭后清空，不进入 task payload、settings、project、fixture 或日志。
- 请求使用 `gpt-image-2`、low quality、固定尺寸映射；支持 base64 PNG → RGBA8、一次网络/5xx 重试、取消，以及 auth/rate/content/timeout/network/internal 错误归一化。
- `PFTask` / `TaskQueue` 增加主线程外部异步任务终态，保持提交顺序和取消语义。
- 生成结果写入正式 graph + batch，保存 provider/model/prompt/seed/cost/provider_meta provenance；选中 OpenAI graph 可再次运行并替换批次。
- 新增录制 JSON fixture（内嵌合成 1×1 PNG，不含外部画师素材）和 M4-V1 专用门禁。

## 3. 自动化证据

- `./pixel/scripts/lint.sh`：127 files，无问题。
- `./pixel/scripts/run_tests.sh`：197/197 tests，1515 assertions 通过。
- 新增覆盖：Provider capabilities/schema、请求净化、PNG 解码、错误映射、单次重试、provenance、异步 resolve/cancel、password 遮蔽与提交后清空。
- `verify_m4_v1.sh` 还会复用 M3.1 门禁并扫描疑似真实 OpenAI key；图片红线沿用 `verify_m3_1.sh`。

## 4. 尚未完成（产品出口）

1. 使用真实 key 完成一次固定提示词生成，确认网络、账户权限、当前响应字段和实际延迟。
2. 在真实图上走通生成 → 清洗/抠图 → 对比/筛选 → 导出，并记录失败样本。
3. 三名目标用户分别执行集成生成与外部生成后导入 A/B，记录首次可用素材时间与继续使用意愿。
4. 按 `M4-ai-providers.md` 给出明确 go/no-go。项目所有者已授权 Goal 期间暂定工程继续 M4-1～M4-5，但不得把该授权倒填为产品 `go`；最终 no-go 时可整体不合并本地 Goal 分支。

## 5. 后续人工入口（用户准备测试时）

1. 启动 PixelForge，File → Configure OpenAI Session Key，输入测试 key。
2. File → Generate OpenAI Value Batch，等待状态栏完成或可操作错误。
3. 对生成批次执行现有 Clean/Matte/Compare/Export；选中该 graph 任一节点后可用 Run Selected Graph 重跑。
4. 关闭并重新启动应用，确认必须重新输入 key；保存的 `.pxproj` 与日志中不得出现 key。

## 6. 长期 Goal 继承审计

- origin/main 基线：`a9003ab`；本地 main 基线：`bdfeafc`；Goal 起点：`44a5081`。
- 继承提交：M3/M3.1 `bdfeafc..531aa86`，M4-V1 `44a5081`；没有合并 main，没有 push。
- `./pixel/scripts/verify_m4_v1.sh`：197/197 tests、1515 assertions 通过；复用 `verify_m3_1.sh` 通过。
- 既有 1 个 GUT orphan 与退出时资源警告仍存在；本轮没有新增用户影响证据，后续若数量或归属变化必须重新定位。
- 人工状态：**待最终统一验收**。当前结论固定为：**暂定工程继续，产品 go/no-go 待最终统一验收**。
