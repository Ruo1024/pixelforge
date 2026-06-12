# PROVIDER-API.md — AI Provider 抽象接口契约

> api_version = 1。所有 AI 能力（云 API、ComfyUI、未来本地模型）都实现本接口。
> 主程序自带的 provider 也按插件形态实现（自食狗粮，保证接口真实可用）。

## 1. 接口定义

```gdscript
# core 侧仅定义接口与数据类型；具体 provider 在 plugins/ 实现
class_name PFProvider extends RefCounted

# —— 元数据 ——
func get_id() -> String                    # "retrodiffusion" | "openai_image" | "comfyui" ...
func get_display_name() -> String
func get_api_version() -> int              # 实现的契约版本，当前 1
func get_capabilities() -> Dictionary
#   {
#     "txt2img": true, "img2img": true, "inpaint": false,
#     "transparent_bg": true,          # 原生透明背景输出
#     "native_pixel": true,            # 原生输出真像素（如 RetroDiffusion）
#     "max_batch": 4,
#     "sizes": [[16,16],[512,512]],    # [min, max]
#     "animation": false,
#     "cost_estimate": true            # 是否能预估费用
#   }
func get_config_schema() -> Array[Dictionary]   # 设置页自动渲染（api_key、endpoint 等）

# —— 生命周期 ——
func configure(config: Dictionary) -> PFError   # null = 成功
func validate_credentials() -> PFTask           # 异步验证 key（轻量请求）

# —— 核心：生成 ——
func generate(req: PFGenRequest) -> PFTask      # task.finished 载荷为 PFGenResult
func estimate_cost(req: PFGenRequest) -> float  # 美元估算，-1 = 不支持
func cancel(task_id: String) -> void
```

## 2. 请求/结果数据结构

```gdscript
# PFGenRequest（Dictionary 包装，键如下）
{
  "mode": "txt2img",              # txt2img | img2img | inpaint
  "prompt": "a wooden barrel",    # 已由调用方拼好（见 §4 提示词组装责任）
  "negative_prompt": "",
  "style": { ... },               # StylePreset 序列化对象；provider 自行决定如何映射
  "width": 64, "height": 64,      # 目标素材的真像素尺寸
  "batch": 4,
  "seed": -1,                     # -1 随机
  "ref_image": null,              # Image（img2img/inpaint 用）
  "mask": null,                   # Image（inpaint 用）
  "extra": {}                     # provider 专有参数（UI 从 config_schema 渲染）
}

# PFGenResult
{
  "images": [Image, ...],         # 统一 RGBA8；provider 负责解码
  "raw_pixel": true,              # true = provider 已保证真像素（跳过清洗的 detect 步骤）
  "seeds": [123, 124],
  "cost": 0.008,                  # 实际/估算费用，未知 -1
  "provider_meta": {}             # 原始响应摘要（写入素材 provenance）
}
```

## 3. 注册与凭据

- `provider_service.gd` 持有注册表：`register(provider: PFProvider)`；UI 生成下拉列表。
- API key 存储：`user://credentials.cfg`，用 Godot `Crypto` AES-256 加密，密钥派生自机器标识；**绝不**写入项目文件或日志。
- 每个 provider 的配置（endpoint、默认模型等）存 settings_service，与 key 分离。

## 4. 提示词组装责任划分（重要）

- **节点层**（ai_generate 节点）负责把 style 预设的 `prompt_template`、用户的物体描述、尺寸规格组装成最终 `prompt` 字符串。模板语法：`{subject}`、`{style_tags}`、`{size_hint}` 三个占位符，String.format 实现。
- **Provider 层**只做平台适配（如 RetroDiffusion 把 style 映射到其官方 style 参数而非提示词；OpenAI 把透明背景需求映射到 `background: transparent` 参数）。
- 这样保证换 provider 不换提示词逻辑，新 provider 接入成本最小。

## 5. v1 计划接入的 Provider（M4 任务卡）

| id | 形态 | 选型理由（2026-06 调研）|
|---|---|---|
| `mock` | 内置 | 程序生成占位图；开发/测试/无网演示用，永久保留 |
| `retrodiffusion` | 内置插件 | 像素专用模型；REST API；原生真像素+透明背景+tileset/动画风格；按张计费便宜（<$0.01/张）|
| `openai_image` | 内置插件 | 通用兜底；gpt-image-1 支持透明背景 PNG；用户基数大、key 易获取 |
| `comfyui` | 桥接插件（M7）| 本地免费、可白嫖全部 SD/FLUX 生态；REST /prompt + WebSocket 进度 |

注：PixelLab（角色8方向/骨架动画）列为 M7 后候选，其能力（动画）超出 v1 范围。

## 6. 错误码约定

`PFError.code` 枚举：`auth_failed | rate_limited | quota_exceeded | invalid_request | network | timeout | content_policy | provider_internal | cancelled`。
UI 按 code 给出本地化提示与建议动作（如 quota_exceeded → 引导换 provider 或充值）。rate_limited 由 task_queue 自动指数退避重试（最多 3 次），其余不自动重试。

## 7. 测试要求

每个 provider 插件必须附带：
- 契约测试：`tests/integration/provider_contract_test.gd` 以 provider id 参数化跑通（capabilities 声明与实际行为一致、错误映射正确）——用录制的 HTTP fixture（mock 服务器），CI 不打真实 API。
- 一个 `--manual` 标记的真实冒烟测试（开发者本地手动跑，需 key）。
