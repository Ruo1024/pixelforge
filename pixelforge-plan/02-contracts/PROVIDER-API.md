# PROVIDER-API.md — AI Provider 抽象接口契约

> api_version = 1。所有 AI 能力（云 API、ComfyUI、未来本地模型）都实现本接口。
> 主程序自带的 provider 也按插件形态实现（自食狗粮，保证接口真实可用）。
> 当前产品范围只发展云端图片模型；ComfyUI 与本地模型是历史扩展能力，不进入 Beta 0.3–0.5，也不作为当前后备路线。

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
func get_model_descriptors() -> Array[Dictionary]
#   [{
#     "provider_id": "openai_image", "model_id": "gpt-image-2",
#     "display_name": "GPT Image 2", "is_default": true,
#     "capabilities": {
#       "txt2img": true, "max_reference_images": 4,
#       "output_sizes": ["1024x1024", "1536x1024", "1024x1536"],
#       "max_batch": 4, "seed": false, "transparent_bg": false,
#       "cost_estimate": false
#     }
#   }]
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
  "model_id": "",                 # 顶层具体模型；空值由所属 Provider 解析默认模型
  "prompt": "a wooden barrel",    # 已由调用方拼好（见 §4 提示词组装责任）
  "negative_prompt": "",
  "style": { ... },               # StylePreset 序列化对象；provider 自行决定如何映射
  "width": 64, "height": 64,      # 目标素材的真像素尺寸
  "batch": 4,
  "seed": -1,                     # -1 随机
  "ref_images": [],               # 有序 Array[Image]（参考图/编辑用）
  "ref_image": null,              # 旧单图兼容输入；仅在 ref_images 为空时作为第一项读取
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

### 2.1 模型目录与前置校验

- `get_model_descriptors()` 是 UI、运行协调器和测试读取模型能力的唯一真相；不得在组件中维护第二份模型表。
- 每个描述符必须包含 `provider_id / model_id / display_name / is_default / capabilities`，同一 Provider 恰有一个默认模型。
- `capabilities` 至少包含 `txt2img / max_reference_images / output_sizes`（或明确的尺寸约束）`/ max_batch / seed / transparent_bg / cost_estimate`。
- Provider 收到空 `model_id` 时解析本 Provider 的默认模型；未知模型、超批量、非法尺寸、参考图超限或不支持透明背景必须在提交网络请求前返回 `invalid_request`，不得截断或静默替换。
- `ref_images` 的顺序有语义。兼容读取旧 `ref_image` 时只包装为第一项；新请求统一写 `ref_images`。

### 2.2 安全生成快照与目标

每个实际结果写入清理后的 `generation_snapshot`：`provider_id / model_id / prompt / negative_prompt / style / width / height / seed / reference_asset_ids / reference_content_sha256s / source_generate_node_id`，以及可选 `source_row_id / run_id / cost`。不得包含凭据、绝对路径、请求头或完整外部响应。

运行协调器调用边界固定为 `graph_id + generate_node_id`，可带 `batch_node_id`。run 状态与结果必须按 `run_id` 和目标节点记录，不得扫描当前选择或第一个同类型节点决定落点。

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
| `openai_image` | 内置插件 | 通用兜底；`gpt-image-2` 支持文字生成和有序多参考编辑输入；用户基数大、key 易获取 |
| `comfyui` | 历史桥接插件 | 底层代码保留；Beta 0.3–0.5 及当前产品路线无限期延后，不显示、不扩展 |

当前原型只发展云端图片模型。`mock` 永久用于自动化；`retrodiffusion` / `openai_image` 优先承接 Beta 0.4。新增云端适配器只在现有两条路径无法完成核心参考图旅程时允许选择一个最小实现。PixelLab 与其他动画能力超出当前范围。

OpenAI 能力核对日期为 2026-07-13，来源为官方 [GPT Image 2 模型页](https://developers.openai.com/api/docs/models/gpt-image-2) 与 [Image generation 指南](https://developers.openai.com/api/docs/guides/image-generation)：Image API 的 generations/edits 分离；edits 接受一张或多张有序 `image[]`；`gpt-image-2` 的参考输入固定高保真；当前不支持透明背景。PixelForge 暴露的批量、参考图数量与常用尺寸可以比平台极限更保守，但必须是适配器真实支持并经过录制请求测试的上限。

## 6. 错误码约定

`PFError.code` 枚举：`auth_failed | rate_limited | quota_exceeded | invalid_request | network | timeout | content_policy | provider_internal | cancelled`。
UI 按 code 给出本地化提示与建议动作（如 quota_exceeded → 引导换 provider 或充值）。rate_limited 由 task_queue 自动指数退避重试（最多 3 次），其余不自动重试。

## 7. 测试要求

每个 provider 插件必须附带：
- 契约测试：`tests/integration/provider_contract_test.gd` 以 provider id 参数化跑通（capabilities 声明与实际行为一致、错误映射正确）——用录制的 HTTP fixture（mock 服务器），CI 不打真实 API。
- 一个 `--manual` 标记的真实冒烟测试（开发者本地手动跑，需 key）。
