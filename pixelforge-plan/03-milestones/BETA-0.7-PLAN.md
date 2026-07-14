# Beta 0.7 — 生成、Output 与像素清洗工作流重构执行书

> 状态：项目所有者的产品决定已写入；本执行书待项目所有者审阅；Beta 0.7 产品代码执行尚未授权
>
> 规划日期：2026-07-14
>
> 产品代码基线：`codex/beta0-6-adaptive-shell-repair@26a6070`，worktree 为 `scratch/worktrees/beta0-6-adaptive-shell-repair`，核对时 clean
>
> 规划控制基线：`codex/pixelforge-full-plan-goal@6338a09`；既有 dirty `AGENTS.md` 与 `pixel/project.godot` 不属于 Beta 0.7，任何 E 都不得覆盖、暂存、撤销或提交
>
> 外部行为参考：`hero8152/Infinite-Canvas main@bc7efbde9ddab02f11abf738d7309b5689dbfa22`，固定于 2026-07-14
>
> 执行身份：当前没有 Beta 0.7 的 E 任务、分支或 worktree；本次 P 只创建规划，不修改 `pixel/`、不构建、不 stage/commit、不 merge/push

## 1. 本轮最终要交付的用户旅程

Beta 0.7 不再继续修补“节点都有了，但流程仍像原型”的表面问题。本轮要把生成、等待、结果拆出和像素清洗连成一条能被普通用户理解的主流程：

```text
自由提示词 + 可选对象清单 + 可选风格提示词 + 可选参考图
  → 在生成卡内选择 Provider、模型、宽、高和数量
  → 用户明确点击“生成”
  → 新 Output 立即出现稳定 pending 槽位
  → 当前执行连线像管道液体一样发光推进
  → 结果逐槽回填；终态失败才弹本地化错误框
  → Output 最多三行，更多结果在卡内滚动
  → 单图可预览、编辑、下载或直接拖出为独立图片卡
  → Output 可连接独立像素清洗节点
  → 用户选择清洗预设、调整现有完整参数并点击“开始清洗”
  → 按输入顺序单并发处理，每次运行产生新的 Output
```

完成后，用户不需要先理解检查器、临时批次动作、尺寸节点和多领域 StylePreset，才能完成一次生成与清洗。

这条旅程直接收口 [LibTV 无限画布产品证据](../04-research/LIBTV-INFINITE-CANVAS-EVIDENCE.md) 中仍存在的应用层差距：输入可在卡内理解、生成有过程反馈、真实结果留在同一画布、加工也是可见节点。Beta 0.7 不重写无限画布底层，也不引入 LibTV 的视频、Agent、协作或市场能力。

## 2. 项目所有者决定登记

以下决定已经由项目所有者给出。执行 E 不得在开发中改成其他方案，也不得用“兼容旧实现”恢复被删除的路径。

| 决定 ID | 最终结论 | 执行含义 |
|---|---|---|
| `PF-SEC-01` | 纳入 Beta 0.7 | 必须是首个实现阻断卡；修复前禁止真实 API、Provider UI 扩建和生成链实现 |
| `B7-PREP-01` | `object_list` 暂不删除 | 保留为可选结构化批量输入；本轮只收紧字段和数量语义，不扩展成新的对象系统 |
| `B7-PREP-02` | 不考虑任何旧版本兼容 | 删除独立 `size_spec`；宽高进入 `ai_generate`；项目、Graph、Provider、Plugin manifest/API、模板和剪贴板一次性硬切 v2，不写 v1 迁移；第三方 v1 插件会被明确拒绝 |
| `B7-BUG-01` | 修复并重做内置实例 | 示例按新卡有效边界重新布局；只改内置示例，不自动移动用户项目 |
| `B7-DEC-01` | 拒绝“紧凑 Output + 完整 Review” | Output 采用参考项目的应用行为：最多三行、内部滚动、pending 原位回填、便捷拆图；删除旧审阅模式 |
| `B7-PREP-03` | 接受生成反馈设计并增加连线流光 | Running 时只有本次执行闭包的连线发光前进；失败停止动画后再弹对应错误框 |
| `B7-DEC-02` | 接受生成卡重构 | Provider、模型、输入摘要、宽高、动态参数、费用和唯一主按钮集中在生成卡 |
| `B7-DEC-03` | Style 只做提示词注入 | 旧 `style_preset` 退役；新 `prompt_preset` 只在最终正向提示词前追加一段前缀；清洗相关设置进入 CleanupPreset |
| `B7-PREP-04` | 接受独立像素清洗节点 | 现有右侧清洗参数原封不动搬到节点；只有点击“开始清洗”才执行；严格顺序、单并发、新建 Output、源结果不变 |
| `B7-API` | 同意 API 全面收口 | 状态、进度、错误、取消、部分成功、分片重试、幂等、安全和费用一起完成，不能只改 Provider 表单 |
| `B7-BUG-02` | 同意修复粘滞平移 | 覆盖 Space/左键释放顺序、`button_mask=0`、失焦和模态弹窗 |
| `B7-I18N-01` | 同意 i18n 架构收口 | 生产 UI 不再直接读取 English 常量；Provider schema、错误和动态状态全部走集中目录 |

## 3. 1A / 2B / 3C 在 Beta 0.7 的确切状态

Beta 0.6 的代号含义是：

- `1A`：输入/生成使用结构化卡，图片/Output 使用内容优先卡；PixelForge 使用自己的主题和实现。
- `2B`：正式卡片标题可改，卡片可在该类型规定的最小/最大范围内调整宽高；尺寸保存、复制和 Undo 后保持。
- `3C`：旧 Output 把全部结果在画布上展开，禁止卡内滚动。

Beta 0.7 的状态固定为：

1. `1A` 保持。生成卡仍是结构卡，Output 仍是图片优先的内容卡。
2. `2B` 的标题编辑、尺寸持久化、复制后保持和 Undo/Redo 保持继续有效；其他卡仍使用 Beta 0.6 的类型尺寸范围。只有 Output 的旧最大尺寸 `1600×1200` 被本计划的新 Output 边界 `360..960` 宽、最多三行自然高明确替代。Output 仍可调整宽高，但用户把卡缩小时只滚动网格，放大到新上限也不能显示第四行。
3. `3C` 由项目所有者明确撤销，替换为“Output 最多三行，超出后只在图片网格内部纵向滚动”。

因此，Beta 0.6 规格中所有“50 张全部展开、禁止 ScrollContainer、结果卡按内容无限增高、Contact/Focus/Compare 审阅”的条款，在 Beta 0.7 不再有效。执行 E 只能改写或删除与 3C、Output 新尺寸上限或 §10.7 明确退役行为直接冲突且已进入 B7-0 失效台账的旧测试；每项必须在同卡增加新契约替代测试。`1A`、`2B` 的其余行为及其非冲突测试继续保留。

## 4. 固定范围和明确不做

### 4.1 本轮必须完成

- 项目/Graph/Provider/模板/剪贴板契约硬切 v2；
- `X-RD-Token` 及通用敏感 Header 脱敏，禁止生成 POST 的不安全自动重试；
- 保留并收紧 `object_list`；
- 删除 `size_spec`，把宽高和数量语义收进 `ai_generate`；
- 把 Style 节点改成只注入提示词的 `prompt_preset`；
- 完整重构生成卡、运行协调器、费用语义和错误呈现；
- 用最多三行、内部滚动的新 Output 完全替换旧结果批次 UI；
- 支持单图拖出、显式拆出、拆出全部、预览、编辑和下载；
- 建立独立 `pixel_cleanup` 手动节点和 CleanupPreset；
- 重排内置示例；
- 修复粘滞平移；
- 清零生产 UI 对旧 English 常量和动态裸文案的绕过；
- 通过本计划规定的自动化与固定截图；只有项目所有者另外明确授权“构建 Beta 0.7 候选”后，才执行唯一候选和最终人工清单。

### 4.2 本轮不做

- 不新增 Provider 或本地模型；API v2 只覆盖当前默认在线生成链路中的 OpenAI Image 与 RetroDiffusion；非默认、实验性后端不迁移、不重构、不新增契约或验收项；
- 不新增视频、音频、时间线、Agent 自动建图、模型市场；
- 不实现账号、权限、协作、共享、项目版本历史；
- 不保留 v1 项目、Graph、模板、剪贴板或旧节点别名；
- 不建设“紧凑 Output / Review”双模式；
- 不恢复 Keep / Reject / Flag、Focus / Compare、Current / Previous / Split；
- 不在 Output 或检查器里保留本轮被迁移的直接整批像素清洗、重采样和量化入口；
- 既有全局抠图、切片、描边以及其他不属于本轮清洗节点重构的独立能力、入口和测试原样保留；本轮既不删除也不扩建；
- 不把对象输入扩展为场景实体、角色系统或资产数据库；
- 不做通用自动排布；只为内置示例和运行新建的 Output 计算无重叠位置；
- 不升级 OpenAI 模型名或更改模型选择策略；模型仍来自 Provider descriptor；
- 不复制 Infinite-Canvas 的代码、CSS、图标、文案、截图、资产或文件结构；
- 不在自动化中调用真实付费 API；
- 不用 Computer Use 代替自动化，也不让脚本截图冒充人工体验通过。

## 5. 契约一次性硬切

### 5.1 版本表

| 契约 | Beta 0.7 固定版本 |
|---|---:|
| `.pxproj` | `format_version = 2` |
| Graph | `graph_version = 2` |
| Provider | `api_version = 2` |
| Plugin manifest/API | `api_version = 2` |
| Workflow Template | `version = 2` |
| Clipboard payload | `PAYLOAD_VERSION = 2` |
| PromptPreset | `prompt_preset_version = 1` |
| CleanupPreset | `cleanup_preset_version = 1` |

硬切规则：

- v1 项目返回 `unsupported_project_version`，不部分打开。
- v1 Graph 返回 `unsupported_graph_version`。
- Provider 插件 `api_version != 2` 在注册阶段返回 `unsupported_provider_api_version`，不得进入 Provider 列表、设置页或运行服务；禁止 v1 adapter、别名或按方法存在性猜版本。
- 插件 manifest `api_version != 2` 返回 `unsupported_plugin_api_version` 并隔离；禁止 v1 adapter。只迁移本轮默认用户旅程实际加载的内置插件；非默认实验性后端保持禁用/不注册，不为通过 v2 门禁而扩建或重构。
- v1 模板返回 `unsupported_template_version`，不猜字段。
- v1 剪贴板返回 `unsupported_clipboard_version`。
- 不保留旧字段别名、旧节点别名或静默默认迁移。
- 所有内置示例、内置模板、测试 fixture 和录制契约直接重建为 v2。
- 错误必须本地化说明“这是预发布格式，当前版本不再支持；请新建项目”，不得崩溃或显示裸错误码。

Plugin API v2 在本轮的版本含义固定为“注册面和 Provider/Graph schema 的 breaking revision”，不是插件签名版本：删除 `register_style_preset`，新增 `register_prompt_preset/register_cleanup_preset`，其余 v1 注册能力原样保留。`PLUGIN-API.md §4` 旧“签名校验留作 v2”路线在 B7-0 必须明确改为“签名/市场/真沙箱仍是未排期未来能力”；Beta 0.7 不实现签名、不声称 v2 插件可信，继续在安装第三方插件时显示“可执行任意代码，只安装可信来源”。不得为了对上旧路线偷偷做伪签名，也不得因未做签名把 API 版本退回 1。

### 5.2 B7-0 必须修改的契约文档

实现前先修改并互相对齐：

1. `pixelforge-plan/02-contracts/GRAPH-SCHEMA.md`；
2. `pixelforge-plan/02-contracts/PROVIDER-API.md`；
3. `pixelforge-plan/02-contracts/PROJECT-FORMAT.md`；
4. `pixelforge-plan/02-contracts/WORKFLOW-TEMPLATE.md`；
5. 将 `STYLE-PRESETS.md` 改成退役说明；
6. 新建 `PROMPT-PRESETS.md`；
7. 新建 `CLEANUP-PRESETS.md`；
8. 修改 `pixelforge-plan/02-contracts/PLUGIN-API.md`：删除 Graph StylePreset 注册点，新增 PromptPreset/CleanupPreset 注册点，同时原样保留所有无关插件能力。

这些文件完成并通过一致性检查前，不得开始产品实现。

## 6. Graph v2 的唯一节点和数据语义

### 6.1 Beta 0.7 主路径节点

生成与清洗主路径只使用以下节点；内置主流程模板的节点白名单也只包含这些类型：

```text
text_prompt
object_list
prompt_preset
image_input
reference_set
ai_generate
pixel_cleanup
batch
```

`batch` 是内部类型名，用户可见名称固定为中文“结果”、English “Output”。不要为了显示名称再新增 `output` 同义节点。

这不是删除其他既有产品能力的授权。已经实现的非主路径节点和全局工具继续按自身模块契约注册；尚未实现的 `matting / slice / outline / palette_map / select / output_to_canvas / output_to_library` 必须在 `GRAPH-SCHEMA.md` 标记为“既有实现”或“延期/未实现”，不能借 Beta 0.7 静默删除既有实现，也不能借本轮补做延期能力。

Graph v2 生成与清洗主路径端口类型只有：

| 类型 | 载荷 | 用途 |
|---|---|---|
| `text` | `String` | 自由提示词 |
| `prompt_prefix` | `{prefix, preset_id}` | 正向提示词前缀注入 |
| `subject_list` | `Array[{id, text, count}]` | 带稳定身份和数量的对象行 |
| `asset_list` | `Array[String]` | 已注册到项目素材库的稳定 asset id |

端口名固定为：

```text
text_prompt.prompt              → ai_generate.prompt
object_list.subjects            → ai_generate.subjects
prompt_preset.prefix            → ai_generate.prefix
image_input.assets              → ai_generate.references
reference_set.assets            → ai_generate.references
ai_generate.assets              → batch.in
batch.assets                    → pixel_cleanup.assets
pixel_cleanup.assets            → batch.in
```

`image_input.assets` 必须恰好有一个 asset id；`reference_set.assets` 按用户排序输出 `0..descriptor.max_reference_images` 个 asset id。运行协调器在创建 `PFGenRequest` 前按同一顺序解析 asset id，读取 RGBA8 `Image` 和内容 SHA-256：运行时图片只进入 `ref_images`，同序 asset id/SHA 只进入 provenance。Provider 不能接触 Graph asset id。其他主路径类型不得隐式转换。`ai_generate` 必须先把 Provider 返回图片注册为素材，再输出 `asset_list`。

### 6.2 `object_list` 保留但收紧

它的唯一产品含义是“批量提示词表”：每一行写一个要生成的对象和数量，例如“木桶 ×4、宝箱 ×2”。它不是必经模块，不代表画布对象、场景实体或素材引用；普通单提示词流程不需要它。

唯一参数：

```json
{
  "rows": [
    {
      "id": "stable-row-uuid",
      "text": "wooden barrel",
      "count": 4,
      "enabled": true
    }
  ]
}
```

固定规则：

- 删除旧 `items` 字段及其兼容转换。
- `id` 非空且在本节点唯一。
- `text` 去首尾空白后非空。
- `count` 为整数 `1..999`。
- 只输出 `enabled=true` 的行。
- 输出端口固定为 `subjects:subject_list`；每项严格为 `{id, text, count}`，不能降成失去身份的字符串数组。
- 有有效 rows 时，行内 `count` 是结构化批量生成的唯一数量真相。
- 本轮不新增对象图片、对象标签、对象关系或嵌套组。
- `object_list` 不是默认演示入口；它只保留在“添加节点”菜单和单独的“批量对象生成”模板。默认示例与基础模板使用 `text_prompt`。

### 6.3 删除 `size_spec`

尺寸是一次生成请求的必要参数，不是能被独立理解或复用的内容模块。把它单独放在生成前只会增加一条必连边和两份数量/尺寸优先级，因此 Beta 0.7 把它并入生成卡，不再保留独立节点。

彻底删除：

- 节点类型 `size_spec`；
- 端口类型 `spec`；
- `ai_generate.spec` 输入；
- `size_spec_node.gd`、注册表、添加菜单、图标、卡片和检查器；
- 示例、模板、剪贴板和测试中的 `size_spec`；
- `per_subject` 及所有旧尺寸节点数量优先级。

不得隐藏节点后继续让运行器读取它。目标尺寸必须只有 `ai_generate.params.target_width / target_height` 一份真相。

### 6.4 `prompt_preset` 只做提示词注入

节点接口：

```text
type: prompt_preset
category: input
inputs: none
outputs: prefix:prompt_prefix
params: preset
```

数据：

```json
{
  "prompt_preset_version": 1,
  "id": "prompt-hibit",
  "name_key": "PROMPT_PRESET_HIBIT",
  "prefix": "high detail pixel art, controlled palette, modern hi-bit game asset"
}
```

固定规则：

- 用户可见名称为中文“风格提示词”、English “Style Prompt”。
- 它只提供一段正向 `prefix`；Beta 0.7 不定义、保存或向 Provider 发送 negative prompt。
- 前缀按普通文本处理，不解释 `{subject}`、`{style_tags}`、`{size_hint}` 等模板占位符。
- 不允许携带调色板、基础尺寸、描边、抖动、透视、Provider 映射、编辑器或地图设置。
- 删除 Graph 中的 `style_preset` 节点、`style` 端口，以及生成/清洗链对旧运行时 StylePreset、`prompt_template`、`provider_hints` 的消费。共享 StylePreset 不再是跨模块真相；若编辑器或地图当前读取它，B7-2 只把已有效的模块默认值固化到该模块自己的配置，功能和入口不删除、不重设计。
- 名称字段二选一：内置预设必须只有 `name_key`；用户预设必须只有 `name`。两者同时存在或同时缺失都校验失败。
- 内置预设用 `name_key` 本地化；用户创建的名称按用户文本原样保存。

六个内置 PromptPreset 的 id 与 `prefix` 逐字固定如下；资源文件不得使用继承或运行时拼接：

| id | name_key | prefix |
|---|---|---|
| `prompt-hibit` | `PROMPT_PRESET_HIBIT` | `high detail pixel art, controlled palette, modern hi-bit game asset` |
| `prompt-gb` | `PROMPT_PRESET_GB` | `Game Boy pixel art, four color palette, monochrome handheld sprite` |
| `prompt-hd2d-prop` | `PROMPT_PRESET_HD2D_PROP` | `HD-2D pixel prop, crisp sprite, high resolution pixel prop` |
| `prompt-1bit` | `PROMPT_PRESET_1BIT` | `1-bit pixel art, black and white, binary monochrome sprite` |
| `prompt-nes` | `PROMPT_PRESET_NES` | `NES pixel art sprite, limited hardware palette, 8-bit console sprite` |
| `prompt-16bit-db32` | `PROMPT_PRESET_16BIT_DB32` | `pixel art, 16-bit style, limited palette, clean pixel grid, retro game asset, DawnBringer palette` |

旧 StylePreset 消费者必须按下表逐一替换，不能笼统删除：

| 现有消费者 | Beta 0.7 唯一替代 |
|---|---|
| `pf_project.manifest.style_preset` | 删除字段；项目不再有全局 Style 真相 |
| Graph node/registry/card/drop/result branch builder | 改为 `prompt_preset`；资源拖入创建 Style Prompt 卡 |
| generation controller 的 project style/prompt/provider hints | 全部删除；只消费连接的 PromptPreset prefix 与生成卡 descriptor |
| cleanup inspector、batch cleanup、`Pipeline.default_params(style)` | 检查器入口删除；pipeline 不接 StylePreset，清洗卡默认选择 `cleanup-16bit-db32` 并保存完整 settings |
| project resource catalog/browser | 旧 `style_preset` kind 改成独立 `prompt_preset` 与 `cleanup_preset` kind；原调色板资源仍独立保留 |
| v1 onboarding 的“Project style preset” | 删除该全局选择步骤，不在 manifest 写 style；不新增替代弹窗。新 prompt/cleanup 节点各使用上述默认 preset |
| pixel editor | 保留入口和能力；模块默认固定为 `base_size=32`、palette `db32`，不读取项目 Style |
| board/map editor | 保留入口和能力；模块默认固定为 `tile_size=16`、palette `db32`，不读取项目 Style |

B7-0 test manifest 必须列出现有每个读取点及替代测试；不得以“Style 退役”为理由删除 editor、board、resource browser、palette、onboarding 主流程或它们的无关断言。

`prompt_preset` 卡继承旧 `style_preset` 的 2B 尺寸，不另开例外：默认 `320×280`、最小 `280×220`、最大 `1600×1200`；标题、尺寸持久化、复制和 Undo/Redo 继续使用通用 2B 行为。

新建 `prompt_preset` 默认嵌入 `prompt-16bit-db32`；新建 `pixel_cleanup` 默认嵌入 `cleanup-16bit-db32`。这两个默认只为新节点填初值，不恢复项目全局 Style。

### 6.5 `ai_generate` 的固定接口

输入：

```text
prefix: prompt_prefix，可选，最多一条
prompt: text，可选，最多一条
subjects: subject_list，可选，最多一条
references: asset_list，可选，最多一条
output: assets:asset_list
```

参数：

```json
{
  "provider_id": "openai_image",
  "model_id": "gpt-image-2",
  "target_width": 32,
  "target_height": 32,
  "batch_size": 4,
  "seed": -1,
  "extra": {"quality": "low"}
}
```

固定规则：

- 每个 Provider 的 model descriptors 必须恰好一个 `is_default=true`。新建生成节点时把当前默认 provider id、它的默认 model id、`seed=-1` 以及该 descriptor 每个 `dynamic_params.key → default` 的完整 `extra` 直接写入 params。切换 provider 时在同一条 Undo 中改 provider id、写该 Provider 默认 model id，并把 extra 整体重建为新 descriptor 的 defaults；切换同 Provider model 时也在同一条 Undo 中改 model id并整体重建 extra。两种切换都保留 target width/height、batch size 和顶层 seed，不保留旧 extra 的同名或未知值。运行前 `provider_id/model_id` 为空或找不到都返回字段级 validation issue，不做隐藏回退。
- `target_width / target_height` 是用户希望清洗后得到的真像素目标，不得冒充云 Provider 的原生返回尺寸；先验证为正整数，再按 descriptor 的 `target_size_constraints` 验证。
- 没有有效对象 rows 时，`batch_size` 为 `1..999` 并决定结果数。
- 有有效 rows 时，不显示可编辑 batch size，只显示“数量由对象清单每行决定”。
- `MAX_RESULTS_PER_RUN = 999`。无对象行时检查 `batch_size <= 999`；有对象行时先求所有有效 row 的 `count` 总和并检查 `<=999`。超过时在生成卡本地拒绝，且预算、Output、队列和网络请求数都必须为 0。
- 至少有非空自由提示词或一个有效对象 row，否则返回 `missing_prompt_input`。
- 语义提示词严格按 `prefix → text_prompt → row.text` 排序，跳过空值，用 `", "` 连接；没有 row 时为 `prefix → text_prompt`。
- `native_pixel=true` 时最终 prompt 就是语义提示词。`native_pixel=false` 时，协调器用一个 `", "` 在语义提示词末尾追加精确技术后缀：`pixel art designed for a {w}x{h} true-pixel target, flat colors, crisp edges`，其中 `{w}/{h}` 是验证后的目标尺寸。
- 生成卡的“最终提示词预览”必须显示实际将发送的完整字符串，包括上述技术后缀；Provider 不得追加隐藏业务提示词。没有有效对象 row 时显示唯一完整 prompt；有对象 rows 时，主预览只显示第一条有效 row 的完整 prompt，并在同组显示“共 N 行 / M 张”和一个可展开的只读列表。展开列表严格按 row 顺序逐行显示 `{row label、count、该 row 的完整 prompt}`，不得为 count 复制 999 条相同文本。
- `image_input/reference_set` 的有序 asset ids 必须在发请求前解析成 RGBA8 `ref_images`；不存在、损坏或超过 descriptor 上限时本地拒绝，网络请求数为 0。
- Provider 只收到已拼好的最终 prompt，不读取 PromptPreset，也不自行追加业务提示词。
- descriptor `native_pixel=true` 时，Provider 请求尺寸等于目标尺寸。`native_pixel=false` 时，协调器从 descriptor 的 `provider_output_sizes` 选择与目标宽高比误差最小的一项；误差相同时取 descriptor 数组中靠前项。返回素材保留 Provider 原生分辨率，生成阶段不得自动缩到目标尺寸；用户需要时显式经过 `pixel_cleanup`。
- `seed` 永远是顶层参数，禁止放进 `extra`。节点只允许 `-1` 或 `0..2147483647`；`-1` 表示每个逻辑 slot 都请求随机 seed。descriptor `capabilities.seed=false` 时 UI 不显示 seed、请求字段省略 seed、每个 slot 的快照写 `requested_seed=-1`；为 true 时才显示并发送。
- descriptor 支持 seed 且节点 seed 非负时，第 `logical_index` 个预建 slot 的 `requested_seed = (node_seed + logical_index) % 2147483648`，`logical_index` 按有效 object row、row 内 count 的全局顺序从 0 开始。分片不得重置 seed：例如 seed=42、总数 5、普通分片 `[4,1]` 时两个 PFGenRequest 的首 seed必须分别为 42 和 46，Provider 把 request 内第 i 项解释为 `request.seed+i`。单个 request 禁止跨越 2147483647→0；planner 必须在 wrap 前强制截断，例如 seed=2147483647、count=2 必须拆为 `{batch:1,seed:2147483647}` 和 `{batch:1,seed:0}`。人工重试某个失败 slot 必须发送该 slot 原 input snapshot 的 `requested_seed`；若 Provider 没返回实际 seed，成功素材的 `actual_seed` 保存 null，不得拿 requested seed 冒充实际值。
- `extra` 必须恰好包含当前 model descriptor 声明的全部 dynamic param keys，每个值满足 kind/range/enum；缺 key、未知 key 或类型错误都在预检返回字段级 `invalid_dynamic_param`，不得透传。带 `visible_when` 的参数仍保留其规范值，但只有条件命中当前 request mode 时 Provider 才发送；条件不命中时不发送且不删除节点值。PFGenRequest、slot input snapshot 和 provenance 保存这份完整规范 extra。
- 参数修改即时进入 Graph params 和 Undo；不提供 Apply。

### 6.6 `pixel_cleanup` 是显式手动节点

端口：

```text
input:  assets:asset_list，required=true
output: assets:asset_list
```

`pixel_cleanup.assets` 只允许一个直接上游，合法来源固定为：

- `batch.assets`：主旅程，只读取 `status=succeeded && detached=false` 的有序可见 slots，并保存 batch/slot 来源；
- `image_input.assets`：允许清洗单张导入图或从独立 sprite 创建的 Image Input；
- `reference_set.assets`：允许按用户顺序清洗多张导入/既有素材。

生成结果必须先物化为可见 Output，因此 `ai_generate.assets → pixel_cleanup.assets` 直接连接返回 `cleanup_requires_output_source`，并提示连接本次 Output。对 image/reference 来源，source batch/slot 字段使用空字符串但 source asset、输入节点 id 和类型仍必须保存；不得为了满足 schema 伪造 batch/slot。这样既保持“结果批次 → 清洗”的默认旅程，也不删除现有导入图片和独立图片的清洗入口。

节点基类新增：

```gdscript
func get_execution_policy() -> String:
    # 只允许 "automatic" 或 "manual"
```

`pixel_cleanup` 固定返回 `manual`。

节点参数：

```json
{
  "preset_id": "cleanup-16bit-db32",
  "settings": {
    "detect_grid": {
      "enabled": true,
      "mode": "auto",
      "scale": 4.0,
      "offset": [0.0, 0.0],
      "base_size": 32
    },
    "resample": {
      "enabled": true,
      "mode": "mode",
      "scale": 4.0,
      "offset": [0.0, 0.0]
    },
    "quantize": {
      "enabled": true,
      "mode": "fixed_palette",
      "palette_id": "db32",
      "auto_k_strategy": "median_cut",
      "k": 16,
      "dither": "none",
      "dither_strength": 0.0,
      "dither_contrast": 0.0,
      "dither_chroma": 0.0,
      "dither_density": 1.0
    }
  }
}
```

必须保留当前右侧清洗检查器已经暴露的全部设置和值域：

| 设置 | 值域 |
|---|---|
| 自动/手动网格检测 | `auto / manual` |
| scale | `1.0..64.0` |
| offset x/y | `0.0..64.0` |
| base size 先验 | `0 / 8 / 16 / 24 / 32 / 48 / 64 / 96 / 128`；由 CleanupPreset 提供，只读，`0` 表示无先验 |
| resample enabled | boolean |
| resample mode | `mode / center / median / edge_aware` |
| quantize enabled | boolean |
| quantize mode | `auto_k / fixed_palette / none` |
| palette | 内置或用户调色板 ID |
| auto-k strategy | `median_cut / kmeans` |
| max colors k | `2..256` |
| dither | `none / bayer2 / bayer4 / bayer8 / chromatic / error_diffusion` |
| dither strength | `0..1`；同时写入 `dither_strength` 与 `dither_contrast` |
| dither density | `0..1` |
| dither chroma | `0..0.25` |

当前检查器只有一个 Strength 滑杆；Beta 0.7 不新增 Contrast 滑杆。执行快照仍保留 `dither_strength / dither_contrast` 两个字段，并始终把它们写成同一个值。调色板选择、颜色条预览、导入用户调色板和删除用户调色板继续复用现有 PaletteRegistry；这些是资源操作，不得变成第二套节点参数。

当前检查器也只有一组共享 `scale/offset`。清洗卡必须继续只显示这一组控件，并同时写入 `detect_grid.scale/offset` 与 `resample.scale/offset`；validator 要求两组值完全相同，不得拆成两个可独立编辑的参数。`detect_grid.base_size` 只由 CleanupPreset 快照提供并显示为只读先验，用户在卡上不能编辑。

`detect_grid.enabled` 在 Beta 0.7 固定为 true，不新增开关；Auto/Manual 只切换检测方式。validator 收到 false 必须返回 `invalid_cleanup_settings`，不能让 resample 悄悄失去共享 grid 语义。

目标尺寸不是第二份节点参数。点击开始时对每个 source slot 分别计算 `effective_target_size`：generated asset 读取自己的 `generation_snapshot.target_width/target_height`；cleaned asset 读取上一轮 cleanup provenance 的 `effective_target_size`；其他来源写 `[0,0]`。执行单项时才把该值注入现有 pipeline 的内部 `resample.target_size`。`resample.enabled=true` 且值为正时输出必须精确到该尺寸；`[0,0]` 时按检测出的共享 scale/offset 决定尺寸。节点 settings、CleanupPreset、模板和剪贴板都不得保存 `target_size`。UI 输入摘要按实际输入显示“目标 32×32（来自来源）”“混合目标（逐图使用）”或“按网格自动决定”。

`palette_snapshot` 只属于一次运行的不可变输入快照，不是第二份节点 settings。点击“开始清洗”并完成其他本地校验后，协调器按以下规则从 `PaletteRegistry` 解析一次，解析失败必须在创建 Output 前返回字段级 `missing_cleanup_palette`：

```json
{
  "palette_id": "db32",
  "content_sha256": "64-char-lowercase-hex",
  "colors_rgba8": ["#000000FF", "#222034FF"]
}
```

- 只有 `quantize.enabled=true && quantize.mode="fixed_palette"` 时 snapshot 为上述对象；其他模式严格为 null。
- `colors_rgba8` 是 PaletteRegistry 当时解析出的有序、非空 RGBA8 列表，每项必须是大写 `#RRGGBBAA`；顺序不得排序或去重。`content_sha256` 是该数组使用无空白 UTF-8 JSON 编码后的 SHA-256 小写 hex。
- 每个 cleanup input snapshot 和成功素材 provenance 都复制这一个不可变对象；运行中或运行后删除/改名用户 palette 不影响本次执行、原位重试或审计。
- 执行每个 item 时，只在传给 pipeline 的内部参数副本中把 `palette_snapshot.colors_rgba8` 注入现有 palette-colors 输入支路；不得写回节点 settings，也不得让 pipeline 按 `palette_id` 再读 PaletteRegistry。fixed_palette 缺 snapshot 必须失败，禁止 fallback 到 db32 或任何默认 palette。
- “仅重试 interrupted 项”读取原 snapshot，不再访问 PaletteRegistry；点击新的“开始清洗”属于完整新运行，必须重新解析当前 palette，并创建新 snapshots。
- 节点、CleanupPreset 和普通剪贴板配置仍只保存 `palette_id`；项目保存通过现有资源清单携带用户 palette。Workflow Template 不嵌入 palette colors，也不负责跨项目复制资源，只按 §7.5 保存 requirements hash 并要求目标项目已经有同 ID/同 hash palette。

修改参数不得自动运行清洗或产生素材；只有“开始清洗”可以执行完整管线。Beta 0.7 不保留旧检查器的自动预览副作用。

执行规则：

1. 普通 Graph Run 到达该节点时停止向下执行并把它标为 Ready。
2. 只有点击卡片固定 Footer 的“开始清洗”才执行。
3. 点击前要求可见成功输入数为 `1..MAX_RESULTS_PER_RUN(999)`；超过时本地拒绝，不创建 Output、不排队、不执行 pipeline。
4. 点击时从合法直接上游一次性快照有序 `{input_source_kind, input_source_node_id, source_batch_node_id, source_slot_id, asset_id, effective_target_size}`、完整节点 settings 和上述 palette snapshot；batch 来源填写 batch/slot，image/reference 来源把两项写空字符串。运行中不得重新读取边、上游 slots、provenance 或 PaletteRegistry。
5. 严格单并发，按输入顺序逐张调用现有 `core/pixel/pipeline.gd`。
6. 单张失败后记录失败槽并继续下一张。
7. 每张成功立即注册为新素材，绝不覆盖源素材。
8. 每次点击都创建新的 Output；源 Output 和之前的清洗 Output 不变。
9. 全成功为 Complete；有成功有失败为 Partial；全失败为 Failed。
10. 取消后不启动下一张；已有成功保留，剩余槽位为 Canceled。
11. 项目异常关闭后，残留 Queued/Running 槽位在重开时变为 Failed/`interrupted`，可重试。

必须删除：

- 批次菜单的直接整批清洗；
- 右侧检查器直接对选择应用清洗；
- Output 卡上的清洗、重采样和量化参数；
- 未点击“开始清洗”就被上游自动触发的路径；
- `pixel_cleanup` 的 style 输入。

既有全局抠图、切片、描边命令、对应对话框、算法与测试不属于上述删除项，必须原样保留；本轮也不把它们塞进 `pixel_cleanup`。

### 6.7 CleanupPreset

```json
{
  "cleanup_preset_version": 1,
  "id": "cleanup-16bit-db32",
  "name_key": "CLEANUP_PRESET_16BIT_DB32",
  "settings": {
    "detect_grid": {
      "enabled": true,
      "mode": "auto",
      "scale": 4.0,
      "offset": [0.0, 0.0],
      "base_size": 32
    },
    "resample": {
      "enabled": true,
      "mode": "mode",
      "scale": 4.0,
      "offset": [0.0, 0.0]
    },
    "quantize": {
      "enabled": true,
      "mode": "fixed_palette",
      "palette_id": "db32",
      "auto_k_strategy": "median_cut",
      "k": 16,
      "dither": "none",
      "dither_strength": 0.0,
      "dither_contrast": 0.0,
      "dither_chroma": 0.0,
      "dither_density": 1.0
    }
  }
}
```

规则：

- `settings` 与 `pixel_cleanup.params.settings` 结构完全相同。
- 名称字段与 PromptPreset 相同：内置只用 `name_key`，用户预设只用 `name`，不得同时存在。
- 选择预设时把完整 settings 复制进节点；节点 settings 始终是用户设置真相。CleanupPreset 不得包含 `target_size`。
- 用户修改任一可编辑设置后清空 `preset_id`，但保留 settings。
- 项目、模板、剪贴板和 provenance 保存完整 settings；预设以后不存在也能复现。
- 旧 StylePreset 中与清洗无关的 `perspective / tile_size / provider_hints / prompt_template` 不进入 CleanupPreset。
- 预设只负责快速填值，不允许在执行时再覆盖用户已编辑的节点设置。

旧 Pixel Style Profile 到 CleanupPreset 的含义固定为“重新制作内置预设”，不是迁移旧 JSON：

| 旧字段 | CleanupPreset v1 |
|---|---|
| `palette.ref` | `settings.quantize.palette_id` |
| `max_colors_per_sprite` | `settings.quantize.k` |
| `auto_k_strategy` | 同名字段 |
| `dither / dither_strength` | 同名清洗字段；contrast 与 strength 同值 |
| `base_size` | `settings.detect_grid.base_size`；运行时网格检测先验，`0` 表示无先验 |
| `outline / anti_alias` | 不迁入清洗管线；现有 pipeline 没有对应步骤，既有独立描边工具仍保留 |
| `perspective / tile_size / provider_hints / prompt_template` | 不进入 CleanupPreset；旧共享 StylePreset 资源退役，独立模块能力按 §6.4 保留 |

六个内置 CleanupPreset 的有效值固定如下。表中未单列的字段全部使用上方完整样例的值；实现时每个 JSON 仍必须重复写出全部 settings，不允许 `based_on`、继承或运行时补字段。

| id | name_key | base_size | quantize enabled/mode | palette_id | k | dither | strength/contrast |
|---|---|---:|---|---|---:|---|---:|
| `cleanup-hibit` | `CLEANUP_PRESET_HIBIT` | 48 | `true/fixed_palette` | `endesga64` | 32 | `none` | `0.0` |
| `cleanup-gb` | `CLEANUP_PRESET_GB` | 16 | `true/fixed_palette` | `gb_4` | 4 | `bayer4` | `0.35` |
| `cleanup-hd2d-prop` | `CLEANUP_PRESET_HD2D_PROP` | 64 | `false/none` | `custom` | 64 | `none` | `0.0` |
| `cleanup-1bit` | `CLEANUP_PRESET_1BIT` | 32 | `true/fixed_palette` | `bw_2` | 2 | `bayer4` | `0.5` |
| `cleanup-nes` | `CLEANUP_PRESET_NES` | 16 | `true/fixed_palette` | `nes_full` | 4 | `none` | `0.0` |
| `cleanup-16bit-db32` | `CLEANUP_PRESET_16BIT_DB32` | 32 | `true/fixed_palette` | `db32` | 16 | `none` | `0.0` |

所有六个预设的 `auto_k_strategy=median_cut`、`dither_chroma=0.0`、`dither_density=1.0`。HD-2D 的旧 `custom` palette 没有颜色，故本版明确禁用量化；不得把空 palette 当作有效固定调色板。NES 旧预设的 `black_1px` 和 Hi-bit 的 `selective` 描边不进入清洗预设，用户仍可在既有独立描边工具中执行。

不得为了“保留旧 StylePreset”在 CleanupPreset 里偷偷恢复多领域字段；描边若以后要成为清洗步骤，需要独立产品决定。不得据此删除现有描边、抠图、切片、编辑器或地图能力。

## 7. Output 数据、运行和历史语义

### 7.1 当前结果的唯一真相

`batch.params.result_slots` 是当前一次运行结果的唯一持久化真相：

```json
{
  "label": "",
  "source_node_id": "generate-or-cleanup-node-id",
  "source_run_id": "run-uuid",
  "role": "current",
  "input_snapshots": {
    "snapshot-uuid": {
      "kind": "generation",
      "graph_id": "graph-id",
      "source_node_id": "generate-node-id",
      "provider_id": "provider-id",
      "model_id": "model-id",
      "mode": "txt2img",
      "prompt": "final prompt for this logical slot",
      "source_row_id": "optional-row-id",
      "prompt_preset_id": "preset-id-or-empty",
      "prompt_prefix": "actual prefix",
      "reference_asset_ids": [],
      "reference_content_sha256s": [],
      "target_width": 32,
      "target_height": 32,
      "provider_output_size": [1024, 1024],
      "requested_seed": -1,
      "extra": {}
    }
  },
  "request_records": [
    {
      "kind": "provider",
      "provider_id": "openai_image",
      "run_id": "run-uuid",
      "request_id": "request-uuid",
      "source_row_id": "optional",
      "slot_ids": ["slot-uuid"],
      "requested_count": 1,
      "received_count": 1,
      "attempts": 1,
      "state": "succeeded",
      "actual_cost_usd": null,
      "charge_id": "",
      "provider_meta": {
        "remote_task_id": "optional-safe-id"
      },
      "remote_cancel_confirmed": null,
      "error": null
    }
  ],
  "result_slots": [
    {
      "slot_id": "slot-uuid",
      "run_id": "run-uuid",
      "request_id": "request-uuid",
      "source_row_id": "optional",
      "source_asset_id": "optional-for-cleanup",
      "input_snapshot_id": "snapshot-uuid",
      "planned_size": [1024, 1024],
      "status": "succeeded",
      "asset_id": "result-asset-uuid",
      "detached": false,
      "unexpected": false,
      "error": null
    }
  ]
}
```

状态只允许：

```text
queued | running | succeeded | failed | canceled
```

固定规则：

- 删除持久化 `asset_ids`；成功素材列表从 slot 派生。
- 删除持久化 `expected_count`；总槽位数等于 `result_slots.size()`。
- `label=""` 表示使用本地化默认标题；只在用户自定义 Output 逻辑标签时保存用户文本，禁止持久化默认裸 English `"Results"`。
- 数组顺序就是 UI 顺序，不保存第二个 `order`。
- `asset_id` 只允许出现在 `status=succeeded`。
- 每个非剪贴板纯素材 slot 必须有 `input_snapshot_id` 并指向本 Output 的唯一安全快照；剪贴板纯素材 standalone slot 固定为空且无 Retry。
- `planned_size` 必须是两个正整数，创建 slot 后不可修改：generation 使用实际发送的 `provider_output_size`；cleanup 只有在 `settings.resample.enabled=true` 且 `effective_target_size` 为正时使用 target，否则使用 source asset 当时的真实尺寸；剪贴板纯素材使用图片真实尺寸。它供 queued/running/failed/canceled 的稳定布局，成功后图片以解码后的真实尺寸渲染，禁止拿 planned size 冒充 actual size。
- `detached` 是独立 boolean，只允许成功槽为 true；它不改变执行终态。成功数、Complete/Partial 和费用推导仍把 detached 成功槽计为 succeeded，但 Output 网格和下游 `asset_list` 不再包含它。
- `unexpected=true` 只用于 Provider 多返回而追加的成功槽；正常预建槽固定 false。
- `status=failed` 必须有 `error`；其他状态的 slot error 必须为 null。重试时把旧错误留在 request record，当前 slot error 清空，终态后再写本次结果。
- Provider 返回顺序不能改变 slot 顺序；用 request/slot 映射原位回填。
- 少返回时缺失槽变为 `failed/result_count_mismatch`。
- 多返回时在末尾追加 `unexpected=true` 成功槽，并在对应 request record 写 `received_count > requested_count`，不得静默丢图。
- Provider 多返回的 unexpected slot 必须创建新的 snapshot id：复制该 request 的安全 prompt/mode/reference/尺寸/extra/source row 快照，并按返回 `index` 推导 requested seed；不支持 seed 或原请求为随机时写 `-1`，确定 seed 时使用 `(request.seed + index) % 2147483648`。该 snapshot 只说明实际发送的请求输入，不伪造原先存在的逻辑 slot；成功素材另保存 Provider 返回的 actual seed。
- `role` 只允许 `current / history / standalone`。
- `current / history` 必须有非空 `source_node_id`；`standalone` 必须清空 `source_node_id`。
- 同一 `source_node_id` 最多有一个 `role=current` 的 Output；此前的 Output 必须是 `role=history`。
- current/history 的 `source_run_id`、slot `run_id/request_id` 必须非空并与 request records 交叉引用。standalone 有两种合法来源：剪贴板粘贴的纯素材容器必须 `source_run_id=""`、`request_records=[]`、所有 slot `run_id=request_id=""`；删除来源节点形成的审计容器保留原 source_run/request records 和 slot 身份。只要 request records 非空，每个非空 slot request id 都必须找到唯一 record；禁止半清空。
- 多返回且所有预期槽都成功时，运行终态仍为 Complete，但显示一个非阻断 `result_count_mismatch` 警告；有缺失或其他失败时才是 Partial/Failed。

`input_snapshots` 是失败/中断后可复现重试的持久化真相，不是日志：

- generation 每个逻辑 slot 建一个 snapshot，保存该 slot 最终 prompt、规范化 safe extra、mode、参考 asset id/SHA、目标/Provider 尺寸和 requested seed；不得保存凭据、Header、raw response、Image 字节、Provider 私有请求体或已渲染文案；
- cleanup 每个输入建一个下列完整 snapshot；`settings` 是点击时节点快照，`palette_snapshot` 见 §6.6：

```json
{
  "kind": "cleanup",
  "graph_id": "graph-id",
  "source_node_id": "cleanup-node-id",
  "input_source_kind": "batch",
  "input_source_node_id": "source-node-id",
  "source_batch_node_id": "source-batch-id",
  "source_slot_id": "source-slot-id",
  "source_asset_id": "source-asset-id",
  "effective_target_size": [32, 32],
  "preset_id": "cleanup-16bit-db32-or-empty",
  "settings": {"detect_grid": {}, "resample": {}, "quantize": {}},
  "palette_snapshot": null
}
```

- 上例 settings 的三个空对象只表示嵌套位置；实际 snapshot 必须逐字段满足 §6.6 的完整 settings shape，不能把空对象视为合法；
- `input_source_kind` 只允许 `batch/image_input/reference_set`。batch 时 `source_batch_node_id/source_slot_id` 必须非空并匹配；image_input/reference_set 时两项必须同时为空，不能只空一个；
- “仅重试失败项”和 interrupted 重试必须使用原 slot 指向的 snapshot，不得重新读取已编辑的来源节点、提示词、参考图顺序、清洗设置或 palette；UI 明示“使用原运行设置”；
- “再次生成/重新完整清洗”才读取当前节点并创建新 Output/新 snapshots；来源节点已删除的 standalone Output 禁用 Retry，但保留 snapshots 作审计；
- snapshot 引用的 reference/source assets 和 palette 内容 hash 纳入 §7.4 history 扫描；Project/Clipboard validator 禁止外来 snapshot id 或悬空引用。

`request_records` 是请求、取消、计费和计数的唯一审计真相，不是第二份结果列表：

- `kind` 只允许 `provider / cleanup`；
- `provider_id`：`kind=provider` 时必须非空并与本次调用一致；`kind=cleanup` 时严格为空字符串；
- state 只允许 `queued / running / succeeded / partial / failed / canceled`；
- `slot_ids` 只引用本 Output 的 slot，不保存图片。创建 request 时前 `requested_count` 项必须恰好是本次预期 slots；Provider 额外成功时把新增 unexpected slot id 追加在末尾，因此长度可大于 requested_count，尾部只能引用 `unexpected=true` 的成功槽；
- `requested_count` 为本 request 发送前固定的正整数；
- `received_count` 初始 0，终态写该 request 实际成功解码数，允许因 Provider 多返回而大于 requested_count；
- `attempts` 为 `0..3`；仍在队列、尚未发送/执行就取消或失败时为 0，真正启动一次 Provider HTTP 或本地 cleanup operation 后至少为 1；
- `actual_cost_usd` 为 null 或 §8.7 的规范 USD 字符串；禁止 binary float 累计；cleanup 固定 null；
- `charge_id` 必须匹配 `[A-Za-z0-9._:-]{0,128}`；空字符串表示没有，任何其他字符使 Provider result 校验失败，禁止先宽松清洗再用于去重；
- `provider_meta` 始终是对象。provider request 只允许对应 model descriptor 的 `provider_meta_keys`；同一 Provider 的列表一致性与 key shape 按 §8.8 注册校验。Beta 0.7 内置唯一允许键为 `remote_task_id`，值必须匹配 `[A-Za-z0-9._:-]{1,128}`；cleanup 固定 `{}`。禁止保存 raw payload、URL、prompt、Header 或任意嵌套对象；
- `remote_cancel_confirmed` 只在 canceled request 为 boolean；
- `succeeded` 表示所有预期项成功，额外成功项只产生非阻断 mismatch warning；同一 request 有至少一个成功预期项和至少一个失败/缺失预期项时为 `partial`；没有成功预期项且有失败时为 `failed`。`partial/failed` 必须保存一个安全汇总 PFError，其他状态 error 为 null；逐项原因仍以 slot error 为真相；
- slot 的 `request_id/run_id` 永远指向修改该 slot 的最新一次请求。人工重试会覆盖这两个字段，但旧 request records 继续保留原 slot_ids/state/error 作历史；validator 只要求 slot 当前 request id 找到唯一 record，不要求所有旧 record 的 slot id 反向等于 slot 当前 request id；
- request record 永久不保存 body、prompt、Header、response 或用户图片。

cleanup 每个输入 item 建立一个 `kind=cleanup` 的本地 operation record：`provider_id=""`、`provider_meta={}`、`requested_count=1`，对应一个 slot，`request_id` 是本地 operation UUID，`actual_cost_usd=null`、`charge_id=""`。单 item record 不允许 `partial`，只能 queued/running/succeeded/failed/canceled；整次 cleanup run 的 Partial 由多个 operation records 聚合。operation 本身继续使用共享 PFTask；cleanup adapter 的 `cancel(request_id)` 另返回 §8.2 的通用 `PFCancelTaskV2`，本地 worker 已停止且原 operation task 发 canceled 后才 resolved，结果 remote_cancel_confirmed 固定 true。pipeline 错误使用 `cleanup_failed`，`provider_id=""`、`stage=cleanup`。`interrupted` 可重试；普通 `cleanup_failed` 默认不可原位重试，用户修改设置后再次点击会创建新的完整 Output。

Output 顶轨的“成功数 / 总槽位数”按全部 slots 计算；detached 成功槽仍计入成功数，unexpected 成功槽计入分子和分母，并额外显示“Provider 多返回”警告。下载、拆出全部和下游输出只处理 `status=succeeded && detached=false`。

### 7.2 新运行不得覆盖旧 Output

完整生成或完整清洗每次都创建一个新 `batch`：

1. 先完成本地输入、Provider、预算和目标位置校验。
2. 在发出请求前，新建 Output、稳定 pending slots 和连接，作为一个原子事务。
3. 事务快照必须包含上一张 current Output 的 role 和输入边；若排队失败，完整恢复旧 role/edge 并删除新 Output，网络请求数必须为 0。
4. 请求一旦发出，新 Output 进入忙状态；忙状态禁止复制、删除、拆出单张/全部、打开编辑器和普通 Undo。已成功回填的图片仍可选中、预览和下载，但改变 Graph/素材关系的动作必须等整个最新 run 终态。
5. 终态后 Output 变为普通可编辑卡；旧 Output 始终保留原 slots 和已有下游连接。
6. “仅重试失败项”复用同一个 Output 和原 slot，不创建新 Output。

重试是一次新的用户运行：创建新的 `run_id`，把 `batch.source_run_id` 更新为该 ID，只把目标 failed slot 改为 queued 并写新的 `run_id/request_id`；未选中的 succeeded/canceled slot 及其 detached 标记保留原身份和内容。每次重试仍执行“每个新 run 最多一个错误框”和费用按 request 去重。

run 范围与 Output 终态必须分开计算：

- busy、进度、Canceling、错误弹框和本次费用只看 `batch.source_run_id` 指向的最新 run，以及 `request_record.run_id`/`slot.run_id` 等于它的记录；旧成功槽不能被算成本次 retry 的已完成数量。
- 最新 run 结束时，若任一最新 request record 为 `failed` 且 `error.code=cancel_failed`，本次卡片状态固定 Failed；否则只要任一最新 record 为 canceled，本次卡片状态固定 Canceled，并保留取消前/旧 run 的成功素材。
- 没有上述取消分支时，最终 Output 内容状态聚合全部当前预期 slots（排除 unexpected，但包含 detached）：全部 succeeded 为 Complete；至少一个 succeeded 且至少一个 failed/canceled 为 Partial；没有 succeeded 且至少一个 failed 为 Failed。人工 retry 成功后必须按这组“当前槽”重算，不能只看最新 run 的子集。
- 例：旧 run 的 4 个槽为“成功、成功、失败、失败”，只重试后两个；最新 run 一成一败时，最新进度分母为 2，最终 Output 仍是 3 成功/1 失败的 Partial。若用户在该 retry 中取消任一未完成 request，则本次卡片显示 Canceled，即使同 run 更早已有 failed record。

生成器的上一张 Output 不再接收新结果。创建新 Output 时：

- 移除 `ai_generate → 上一张当前 Output` 的输入执行边；
- 保留上一张 Output 的存储内容和所有下游边；
- 新增 `ai_generate → 新 Output` 的输入执行边；
- 把旧 Output 的 `role` 改为 `history`，新 Output 写 `role=current`，并在 UI 中给旧 Output 加“历史”状态标记；
- 旧 Output 仍可作为 `asset_list` 来源连接清洗节点；
- 历史关系使用灰色虚线，只是画布关系，不进入 Graph 执行闭包。

新 Output 的自动位置只允许扫描生成卡右侧空位：

- 首选与生成卡顶部对齐，水平间距 `80` world px；
- 与既有有效 bounds 相交时，按 `card_height + 56` 向下扫描；
- 不移动任何既有卡；
- 用户移动旧 Output 后，后续运行不得把它移回。

清洗节点使用相同规则：每次“开始清洗”把该清洗节点上一张 `role=current` 的 Output 改为 history，移除旧输入执行边，创建并连接新的 current Output。它不改变输入的源 Output，也不移动任何旧卡。

### 7.3 Output 端口

`batch` 的输入为可选 `in:asset_list`，输出为 `assets:asset_list`。它是持久化素材引用容器：

- 有输入且本次是新运行时，把运行结果物化为 slots。
- 没有输入但已有 slots 时，输出当前 `status=succeeded && detached=false` 的 asset ids。
- `detached=true` 的成功槽仍保留审计引用，但不再从该 Output 的网格或下游输出。
- 历史 Output 不因为失去生成输入边而失效。

### 7.4 Project Format v2

`manifest.json`：

- 新增必填 `id`，使用小写连字符 UUIDv4；New Project 每次生成新 id，普通 Save 和 Save As 都保持同一 id。Clipboard v2 的 `origin_project_id` 只能取自该字段，不得用路径、文件名或窗口实例代替项目身份；
- 删除项目全局 `style_preset`；
- 不新增项目全局 PromptPreset 或 CleanupPreset 真相；
- 节点保存实际使用的完整 preset/settings snapshot。

`canvas.json` 的 graph node 继续保存 `display_title / size / collapsed / position / z_index`。Output 的 `role / source_node_id / source_run_id / input_snapshots / request_records / result_slots` 全部属于 Graph 逻辑，必须随 Graph v2 持久化，禁止复制到 canvas 或另存第二份。

从 Output 拆出的 sprite 新增：

```json
{
  "asset_id": "asset-uuid",
  "origin_graph_id": "graph-id",
  "origin_batch_node_id": "batch-node-id",
  "origin_slot_id": "slot-id"
}
```

`origin_graph_id/origin_batch_node_id/origin_slot_id` 三项必须同时存在并指向拆出命令发生时的来源；来源 Output 后来被删除或变成 standalone 也不得改写。下例只展开 Beta 0.7 改动的 generation provenance；现有公共 `name/tags/size/palette_ref/anim` 字段和 `provenance.created_at` 继续按 Project Format 保存。`origin/provenance/generation_snapshot` 的嵌套位置严格固定，禁止把 snapshot 放到 provenance 外面：

```json
{
  "id": "asset-uuid",
  "origin": "generated",
  "provenance": {
    "graph_id": "graph-id",
    "generation_snapshot": {
      "provider_id": "provider-id",
      "model_id": "model-id",
      "mode": "txt2img",
      "target_width": 32,
      "target_height": 32,
      "provider_output_size": [1024, 1024],
      "actual_width": 1024,
      "actual_height": 1024,
      "requested_seed": -1,
      "actual_seed": null,
      "run_id": "run-id",
      "request_id": "request-id",
      "source_node_id": "generate-node-id",
      "source_row_id": "optional-row-id",
      "prompt_preset_id": "preset-id-or-empty",
      "prompt_prefix": "actual prefix",
      "prompt": "actual final prompt",
      "reference_asset_ids": [],
      "reference_content_sha256s": [],
      "extra": {}
    }
  }
}
```

`generation_snapshot` 从该 slot 的 input snapshot 复制安全输入字段，再补 actual 结果；不得在素材注册时重新读取生成节点。`provider_output_size` 是发送给 Provider 的请求尺寸；`actual_width/actual_height` 是该素材解码后的真实尺寸，两者不得用目标尺寸代替。`requested_seed` 是本 slot 实际请求值；`actual_seed` 只允许 null 或 `0..2147483647`，只能来自归一化 Provider item。`reference_asset_ids` 与 `reference_content_sha256s` 必须等长、同序，并与实际送入 `ref_images` 的顺序相同。`extra` 只保存 descriptor 允许的规范化安全键。

项目文件中的 prompt 是用户业务数据，不允许进入日志、错误框或固定截图 manifest。不得保存 negative prompt、密钥、Header 或完整 Provider response。

cleanup 也使用同一个 asset metadata wrapper；下例同样省略未改变的公共字段，但嵌套位置严格固定：

```json
{
  "id": "cleaned-asset-uuid",
  "origin": "cleaned",
  "provenance": {
    "graph_id": "graph-id",
    "parent_asset": "source-asset-id",
    "cleanup": {
      "source_asset": "source-asset-id",
      "input_source_kind": "batch",
      "input_source_node_id": "source-node-id",
      "source_batch_node_id": "source-batch-id",
      "source_slot_id": "source-slot-id",
      "cleanup_node_id": "cleanup-node-id",
      "run_id": "cleanup-run-id",
      "request_id": "local-operation-id",
      "preset_id": "cleanup-16bit-db32-or-empty",
      "effective_target_size": [32, 32],
      "settings": {},
      "palette_snapshot": null,
      "report": {}
    }
  }
}
```

上例中的 `settings: {}` 与 `report: {}` 仅表示嵌套位置，实际成功记录禁止为空：source kind/node/batch/slot 必须原样复制 input snapshot 的条件字段；`settings` 必须复制点击开始时按 §6.6 完整规范化的三组快照；`palette_snapshot` 必须原样复制该 input snapshot 的对象或 null；`effective_target_size` 必须与实际注入 pipeline 的值一致。`report` 至少固定包含 `input_size:[w,h] / output_size:[w,h] / effective_target_size:[w,h] / detected_grid:{cell_size,offset} / steps:{detect_grid,resample,quantize} / input_color_count / output_color_count / elapsed_ms`；三个 step 值是 boolean，所有尺寸为正整数 pair，只有 effective target 允许 `[0,0]`。失败项没有 asset provenance，只在 slot/PFError 和 operation record 保存失败；契约测试必须用完整成功对象往返，不能把空对象当合法记录。

引用扫描：

- `batch.params.result_slots[].asset_id` 在 `succeeded && detached=false` 时是 live 引用；`detached=true` 时是 history/audit 引用；
- `sprite.asset_id` 是 live 引用；
- `batch.params.input_snapshots` 中 generation 的 `reference_asset_ids[]` 和 cleanup 的 `source_asset_id` 都是 history 引用；
- `asset.provenance.generation_snapshot` 中的 `reference_asset_ids[]` 是 history 引用；扫描器必须与各自 SHA 一起保留参考图来源完整性；
- `asset.provenance.parent_asset` 与 `asset.provenance.cleanup.source_asset` 是 history 引用。

资源扫描器必须同时收集 live 与 history 引用，二者都进入项目资源清单并阻止素材字节被当作 orphan 删除；区别只在 UI/下游是否输出。只有既不属于 live 也不属于 history 的 asset 才可清理。palette snapshot 已内嵌规范颜色与 hash，不依赖 palette 资源继续存在。不得因为参考图、detached slot、父素材或原 palette 不在当前画布/registry 中就丢失历史内容。

项目打开时不恢复外部或本地执行。加载 validator 完成后、UI 观察 Graph 前，必须用一个不可 Undo 的恢复事务原子执行：

1. 每个残留 `queued/running` slot 改为 `failed` 并写新的安全 `interrupted/retryable=true` PFError；对应 record attempts=0 时 stage=`queue`，provider record attempts>0 时 stage=`provider`，cleanup record attempts>0 时 stage=`cleanup`，provider_id/request_id/count 从 record 的安全字段复制。已有 succeeded/failed/canceled slot、素材及 detached 标记保持。
2. 逐个处理所有残留 `queued/running` request record，而不只处理刚改 slot 的 record；保留 attempts/provider id/provider meta/cost 审计。`received_count` 从 record.slot_ids 中全部 succeeded slots 重算，包含 requested_count 之后的 unexpected 成功，所以允许大于 requested_count；state 只看 slot_ids 前 requested_count 个预期 slots，按下列顺序且必须命中一支：任一预期 slot 已有 `cancel_failed` 时写 `failed`；否则任一预期 slot 为 canceled 时写 `canceled/error=null`，原 remote_cancel_confirmed 为 boolean 就保留，为 null 就保守写 false；否则预期全 succeeded 写 `succeeded/error=null`；至少一个 succeeded 且至少一个 failed 写 `partial`；没有 succeeded 且至少一个 failed 写 `failed`。partial/failed 的汇总 error 优先使用本次恢复新建的 `interrupted`，否则复制预期 slot 顺序中第一个安全 error；不得留下持久化 queued/running record，也不得因 record 写盘晚于 slots 就漏掉已有 failed/canceled 状态。
3. 对每个 source 的最新 `source_run_id` 使用 §7.2 完全相同的优先级重新派生卡片状态：最新 run 有 `cancel_failed` 先为 Failed；否则任一最新 record canceled 就为 Canceled；否则按全部当前预期 slots 聚合 Complete/Partial/Failed。禁止仅信任保存前的卡片文字状态，也禁止把“failed 后用户又取消”在重开后改名为 Partial/Failed。
4. 所有对应连线回 idle；不重建 PFTask、不发 HTTP、不运行 cleanup worker、不弹启动时错误框。只有同时满足 §8.5 来源/snapshot 前置时，用户之后才能点击“仅重试 interrupted 项”并使用原 input snapshots 创建新 run/request；standalone 或来源缺失时只保留 interrupted 审计状态。

### 7.5 Workflow Template v2

允许节点就是 §6.1 的八种。参数白名单：

| 节点 | 可保存参数 |
|---|---|
| `text_prompt` | `text` |
| `object_list` | `rows` |
| `prompt_preset` | `preset` |
| `image_input` | `asset_id`，保存模板时清空 |
| `reference_set` | `asset_ids`，保存模板时清空 |
| `ai_generate` | `provider_id/model_id/target_width/target_height/batch_size/seed/extra` |
| `pixel_cleanup` | `preset_id/settings`；不得保存派生 target size |
| `batch` | `label` |

Workflow Template v2 顶层新增且始终保存 `palette_requirements` 数组：

```json
{
  "palette_requirements": [
    {"palette_id": "custom_farm_12", "content_sha256": "64-char-lowercase-hex"}
  ]
}
```

- 只扫描模板中 `pixel_cleanup.settings.quantize.enabled=true && mode="fixed_palette"` 的节点；每个不同 palette id 恰好一项，按 palette_id 升序，hash 算法与 §6.6 完全相同。没有需求时必须保存 `[]`。
- 保存模板前从当前 PaletteRegistry 解析并写 hash；palette 缺失返回 `missing_template_palette`，同 id 被两个节点解析成不同内容属于内部校验失败，模板不写盘。
- 插入模板时先在目标项目 PaletteRegistry 查同 id：不存在返回 `missing_template_palette`，hash 不同返回 `template_palette_mismatch`；任一失败都不得部分插入节点。匹配后节点仍只保存 palette_id，运行点击时再建立完整 palette snapshot。
- 模板 payload 不保存 colors，不自动导入/覆盖用户 palette，不 fallback 到 db32。自定义 palette 要跨项目使用时，用户必须先通过既有项目 palette 导入入口加入目标项目。

规则：

- 模板中的 batch 必须固定写 `role=standalone`、`source_node_id=""`、`source_run_id=""`、`input_snapshots={}`、`request_records=[]`、`result_slots=[]`；插入后由实际运行创建 Output，普通模板不预建历史或重试输入。
- `extra` 只保留模型 descriptor 标记 `template_safe=true` 的键。
- 内置基础模板固定为 `text_prompt → ai_generate`；运行时自动创建 Output，模板不预建 Output。
- 单独提供“批量对象生成”模板：`object_list → ai_generate`；它不是默认入口。
- 把既有 “Reference continuation” 重建为 v2 第四个模板：`text_prompt → ai_generate` 与 `image_input.assets → ai_generate.references`；text 和 asset 初始为空并有本地化填写提示，不预建 Output。不得因硬切字段而删除这条既有参考图旅程。
- 内置“生成并清洗”模板固定为 `text_prompt → ai_generate` 和一个未连接输入的 `pixel_cleanup`；模板内放置本地化说明“生成完成后连接 Output，再点击开始清洗”。模板不得预建 Output、不得自动连接运行时 Output、不得自动清洗。

### 7.6 Clipboard v2

- 协调器状态为 Queued/Running/Canceling 的节点或 Output 不允许复制，返回 `clipboard_node_busy`；Canceling 是内存瞬态，不写入 request record state。
- Clipboard v2 顶层必须保存 `origin_project_id`。Beta 0.7 只允许在同一项目粘贴；目标项目 id 不同就返回 `clipboard_project_mismatch`。本版不内嵌素材字节，也不做跨项目素材导入。
- `prompt_preset` 复制完整 preset snapshot。
- `ai_generate` 只复制配置，不复制 run/request/progress/error 或当前 Output 关系。
- `pixel_cleanup` 复制 `preset_id/settings`，不复制上次运行状态或任何派生 target size。
- 终态 Output 可复制；只复制 `status=succeeded && detached=false` 的可见槽。failed/canceled/pending 槽、全部 input snapshots/request records、source/run/request 身份和 Retry 能力都不复制。
- 粘贴后的纯素材 Output 结构必须严格为：新的 batch node id，`role=standalone`、`source_node_id=""`、`source_run_id=""`、`input_snapshots={}`、`request_records=[]`；每个复制槽只允许 `{slot_id:new, run_id:"", request_id:"", source_row_id:"", source_asset_id:"", input_snapshot_id:"", planned_size:[实际图片宽,实际图片高], status:"succeeded", asset_id:原同项目素材 id, detached:false, unexpected:false, error:null}`。禁止保留或推导其他运行字段，因此永远没有“重试此项”，也不会被误标为 Provider 多返回。
- sprite 只允许同项目复制；完整保留 `origin_graph_id/origin_batch_node_id/origin_slot_id` 三元组作为审计。来源 graph/batch 未同时复制时也不阻止粘贴，但三项不能部分清空。
- payload 禁止包含 task id、原 request id、progress、last error 的 raw detail、Header 或 response。

### 7.7 拆出 Undo 与引用规则

- 拖出和按钮“拆出图片”必须调用同一个 domain command。
- command 原子地保持 `status=succeeded`、把 `detached false → true`、创建 sprite 并记录 `origin_graph_id/origin_batch_node_id/origin_slot_id` 完整来源三元组。
- Undo 删除该 sprite 并把同一 slot 的 `detached` 恢复为 false；Redo 使用同一个 asset id 和 sprite id，不能复制位图。
- 若用户随后删除 sprite，slot 保持 `detached=true`；删除 sprite 的 Undo 只恢复 sprite，不改 slot。
- “从 Output 移除但不创建 sprite”不在 Beta 0.7 范围，避免产生无明确 live owner 的素材。

### 7.8 删除来源节点

- `ai_generate` 或 `pixel_cleanup` 的协调器状态为 Queued/Running/Canceling 时，删除来源节点必须返回 `source_node_busy`，不改 Graph；Canceling 不属于持久化 request state。
- 来源节点全部终态后允许删除。删除事务必须原子地：删除来源节点；把它关联的 current/history Output 全部改为 `role=standalone`；清空这些 Output 的 `source_node_id`；删除历史灰色虚线关系。素材、slots 和 request records 保留为审计，不删除位图。
- Undo 必须恢复来源节点、原 role、`source_node_id`、当前执行边和历史关系；Redo 再执行同一事务。
- 单独删除 Output 不得删除来源节点。删除最后一张可见图也不得隐式删除 Output。

### 7.9 删除 Output 与 Undo 冲突

- 协调器状态 Queued/Running/Canceling 的 Output 禁止删除；终态 Output 可作为一条 Undo 事务删除。
- 删除 current Output 时同时移除来源执行边；删除 history 时移除历史关系。来源节点保留，下一次完整运行仍可创建新的 current Output。
- Undo 恢复被删 Output 时必须重新检查当前 Graph：来源节点已不存在则恢复为 standalone；来源存在且没有其他 current 时恢复原 role/边；来源已有另一张 current 时，旧 Output 只能恢复为 history 并使用灰色历史关系，不能恢复第二条 current 执行边。
- Undo 快照必须保留 slots/request records 和素材引用直到该 Undo 项出栈；Redo 再按同一规则删除。任何顺序都必须满足“同一 source 最多一个 current”。

## 8. Provider API v2、安全、状态与费用

### 8.1 三层身份

- `run_id`：一次用户点击“生成”或“开始清洗”的完整运行。
- `request_id`：运行中一个可审计执行单元；generation 是一个 Provider 分片，cleanup 是一个单素材本地 operation。`request_record.kind` 区分两者。
- `attempt`：同一执行单元真正启动的次数；Provider 是 HTTP 尝试，cleanup 是本地 pipeline operation 启动。未启动为 0。

只有 Provider transport 在同一 request 内执行获准的自动网络 attempt 时，才复用同一个 `request_id`、完全相同 body 和相同幂等键；Beta 0.7 生成 POST 实际没有此自动重试权限。用户对失败 slot 的人工 Retry、interrupted cleanup Retry 和重新完整运行都必须创建新的 request id；cleanup 不存在 body/幂等键语义。

分片算法固定：先按 `object_list.rows` 数组顺序建立逻辑组；无对象行时只有一个组，count=`batch_size`。每组按当前 model descriptor 的 `max_batch` 从前向后切成连续片，最后一片取余，例如 count=5、max_batch=4 必须得到 `[4,1]`；确定 seed 时还必须按 §6.5 在 wrap 边界提前切片。每片创建一个 request id/request record，并引用预建的连续 slot ids；不得跨 row 合并分片。

人工“仅重试失败项”只收集失败/缺失 slot，成功 slot 不进入新请求。可合并到同一 retry request 的 slots 必须同时满足：同一 source row、除 requested seed 外的 input snapshot 完全相同、原 slot 顺序连续、requested seed 非负且逐项 `+1`、不跨 2147483647→0；任一条件不满足就拆成不同 request。`requested_seed=-1` 的失败槽固定逐 slot、`batch=1` 重试，避免一次新的随机批次改变其他 slot 的身份。例如原 42/43/44/45 中只有 42 和 44 失败时必须发两个 `batch=1` 请求，不能合成 seed=42/batch=2。

### 8.2 PFGenRequest

```json
{
  "run_id": "run-uuid",
  "request_id": "request-uuid",
  "idempotency_key": "stable-key",
  "provider_id": "provider-id",
  "mode": "txt2img",
  "model_id": "model-id",
  "prompt": "final assembled prompt",
  "target_width": 32,
  "target_height": 32,
  "provider_output_size": [1024, 1024],
  "batch": 4,
  "seed": -1,
  "ref_images": [],
  "extra": {}
}
```

上方 `provider-id/model-id` 是无 dynamic params 的 shape 占位模型，所以 extra 为 `{}`；真实内置 OpenAI request 必须是 `{"quality":"low"}` 或用户已验证的 quality 值，RetroDiffusion 同样遵守 §6.5“完整且恰好全部 keys”。slot input snapshot 与 provenance 的通用 `{}` 示例使用同一解释。

删除 `style`、`negative_prompt`、单数 `ref_image` 和 Provider 内 StylePreset 映射。只保留复数 `ref_images`。`target_width/target_height` 供审计和目标提示；`provider_output_size` 是 Provider 实际接收的尺寸。`ref_images` 的顺序必须与 generation provenance 的 reference id/SHA 顺序相同。

`mode` 只允许 `txt2img / img2img`：`ref_images=[]` 时固定 txt2img，非空时固定 img2img，并在网络前验证 descriptor capability 和最大参考图数。任何路径都不得静默丢掉参考图后降级 mode。

协调器总是生成稳定 `idempotency_key` 供内部审计，但只有 descriptor 声明 `native_idempotency=true` 且契约测试证明插件实际发送时，Provider 才能把它写入远端 Header/body；当前 OpenAI 与 RetroDiffusion 都不得伪造或声称远端幂等。

PFProvider API v2 的运行接口固定如下；具体 Godot 基类/协议可以按现有项目风格实现，但方法名、输入输出和所有权不得改变：

```gdscript
func get_api_version() -> int:                 # 固定返回 2
func get_config_schema() -> Array[Dictionary]
func get_model_descriptors() -> Array[Dictionary]
func estimate_cost(request: PFGenRequest) -> Variant  # null 或规范 USD String
func generate(request: PFGenRequest) -> PFProviderTaskV2
func cancel(request_id: String) -> PFCancelTaskV2
```

- `generate` 必须在任何 progress、网络副作用或终态前立即返回 provider 专用 wrapper，不阻塞 UI；实际启动必须排到下一次 deferred/queue turn，使协调器能先连接全部信号，禁止在 `generate()` 调用栈内同步发信号。`PFProviderTaskV2` 信号固定为 `progress(PFProviderProgress)`、`completed(PFGenResult)`、`failed(PFError)`、`canceled(request_id)`；零到多次 progress 后，必须恰好一次 completed/failed/canceled 终态，终态后的任何信号幂等忽略。
- `PFCancelTaskV2` 是 Provider 与本地 cleanup adapter 共用的独立取消 wrapper，只允许恰好一次 `resolved(PFCancelResult)` 或 `rejected(PFError code=cancel_failed)`，没有 progress/canceled 信号。Provider 成功取消顺序是“停止本地回调 → generation task 发 canceled → cancel wrapper resolved”；cleanup 顺序是“worker 停止 → 原 operation PFTask 发 canceled → cancel wrapper resolved”。若 5 秒内无法证明本地停止，Provider 必须让 generation task 先 `failed(同一个 cancel_failed PFError)`、再让 cancel wrapper rejected；不能留下未终态 generation wrapper。任一取消 wrapper 终态后都绝不再物化结果。

`PFCancelResult` 固定为：

```json
{
  "request_id": "request-uuid",
  "local_stopped": true,
  "remote_cancel_confirmed": false,
  "billing_update": null
}
```

`billing_update` 只允许 null，或取消 cutoff 后、本地停止完成前已经收到并通过 §8.7/§8.8 校验的对象。非 null 时必须且只能含 `actual_cost_usd/charge_id/provider_meta`：actual 必须是非 null 的规范 USD String，charge/meta 分别遵守 §7.1；没有 actual 时整个字段必须 null。它不得含图片、普通错误或 raw response。Provider 不得为了追账在本地停止后继续轮询。cleanup 与未提交 Provider request 固定为 null。协调器在 cancel wrapper resolved 时先按同一 `record_once` 规则消费非 null billing_update，再终态化 record；wrapper 重复/迟到 resolve 不得二次计费。没有已知 update 且 remote=false 时费用保持 unknown，并明确提示本地 ledger 可能低于 Provider 最终账单。
- 现有共享 `pixel/services/pf_task.gd` 及其 `progress_reported/finished/failed/canceled` 信号继续服务 HTTP、cleanup、TaskQueue 和其他模块，本轮不全局改名。B7-2 必须新增 `pixel/core/provider/pf_provider_task_v2.gd` 与 `pixel/services/pf_cancel_task_v2.gd`；前者只在 Provider 边界包装底层任务，后者统一取消完成语义。新 wrapper 不提供旧信号别名，静态测试禁止普通 UI/Graph 直接订阅 Provider task。
- 同一 request 重复 cancel 必须返回同一个 PFCancelTaskV2。`CANCEL_SETTLE_TIMEOUT_MS=5000` 只约束本地停止；本地停止后若 Provider 有远端取消，`REMOTE_CANCEL_TIMEOUT_MS=3000` 独立约束远端确认，超时即 resolved false。两者都由协调器注入的 monotonic clock/scheduler 驱动；测试不得真实等待。
- Provider progress 是单个 request 的进度，`ratio` 若存在必须表示该 request 从提交到完成解码的整体比例，而不是某个内部 phase 的局部比例。
- PFProviderTaskV2 坐在本地队列时不得发 progress。真正出队后、执行该 request 的第一个网络动作之前，Provider 必须先恰好发一次 `{phase:"submitting",determinate:false,ratio:null,completed_items:0,total_items:request.batch}`；协调器只以这次事件把 record `queued→running`、`attempts 0→1` 并把卡片进入 Running。随后重复 submitting 不再增加 attempts。本版生成 POST 无自动重试，所以 Provider request attempts 终态只能是 0（未出队）或 1（已开始）；验证 GET 的 transport attempts 不写 generation request record。
- `completed` 的 result 必须先在 Provider 边界按 §8.8 完整归一化；`failed` 只能携带 §8.4 的安全 PFError。wrapper、信号和异常都不得泄漏 raw response。
- Provider 只负责远端请求、响应解码和安全归一化；不得读取或修改 Graph、Output、AssetRegistry、卡片、连线、Undo、费用累计或弹窗。协调器是这些应用状态的唯一写入者。
- `cancel` 的终态语义按 §8.8；不存在 fire-and-forget 取消，也不得让 generate task 在 cancel task resolve 后继续物化结果。

### 8.3 运行状态机

唯一允许的卡片状态：

```text
Ready
  → Queued
Queued
  → Running | Canceling | Failed
Running
  → Canceling | Complete | Partial | Failed
Canceling
  → Canceled | Failed
Complete | Partial | Failed | Canceled
  → Queued  # 仅来自新的明确用户动作
```

规则：

- 预算确认前保持 Ready，取消预算后网络请求数为 0。
- Ready 阶段本地校验、预算或 Output 原子事务失败时保持 Ready，只显示字段/预算错误，不进入 Failed。
- 本地事务成功并进入队列后才是 Queued。
- 仍在本地队列、尚未发送时取消：`Queued → Canceling → Canceled`，`remote_cancel_confirmed=true`，网络请求数为 0。
- 队列启动前发生内部调度错误：`Queued → Failed`。
- Provider 接受执行或本地 worker 真正开始后才是 Running。
- 用户取消后先进入 Canceling；本地 task 已停止、不会再物化新结果后才是 Canceled。
- Canceling 中本地 task 无法停止时进入 Failed 并保存脱敏 `cancel_failed`；协调器自身非取消错误仍用 `provider_internal`。不得永远卡在 Canceling。
- Canceled 表示“PixelForge 已停止等待和落地”，不等于远端服务一定停止。运行记录必须保存 `remote_cancel_confirmed: true|false`；为 false 时卡片内联提示“Provider 可能仍继续处理或计费”，但用户主动取消仍不弹错误框。
- 请求结果有成功也有失败必须是 Partial，不得写成 Failed 或 Complete。
- Canceled 保留取消前已成功的素材。
- 重复点击取消只发送一次取消。
- 协调器必须串行处理状态事件。第一次取消事件建立 cutoff：cutoff 前已经完成 materialize 的 succeeded slot 保留；cutoff 后到达的图片回调不得注册素材或把 slot 改回 succeeded，只可补写安全的取消/费用审计。
- 每个 cancel task resolved 时，把该 request 仍 queued/running 的预期 slots 改 canceled，对应 record 写 `state=canceled/error=null/remote_cancel_confirmed=<result>`；generate task 必须已发 canceled 终态。
- 任一 cancel task rejected 时，把该 request 仍 queued/running 的预期 slots 改 failed 并写 `cancel_failed/retryable=false/stage=cancel`，record 写 `state=failed/error=同一安全错误/remote_cancel_confirmed=null`；其他已经 resolved 的 request 保持 canceled。等待本 run 全部 cancel tasks 终态后，存在任一 cancel_failed 则 `Canceling → Failed`，否则 `→ Canceled`。取消失败可以弹一次本地化错误框，不能把运行留在持久化 running。
- cutoff 后到本地停止完成前已经抵达 Provider adapter 的图片/普通错误一律不落图、不改 slot/record 终态；同一安全结果里的规范费用字段只能通过 `PFCancelResult.billing_update` 带回。cancel wrapper 终态后所有 task/transport 回调一律忽略，不存在第二条 post-terminal billing 信号。
- request/slot 已是终态时，重复或迟到回调只能被幂等忽略；不得二次落图、二次计费、二次弹框或倒退状态。remote=false 且 billing unknown 只显示账单风险，不能伪造 `$0` 或启动隐形轮询。
- Complete/Canceled 后点击“再次生成”，或 Failed/Partial 选择“重新完整生成”，都按 §7.2 创建新 Output 再进入 Queued。Partial/Failed 的“仅重试可重试失败项”复用原 Output 和目标 slots，再进入 Queued。打开设置、聚焦字段或关闭弹框不改变状态。

Provider task 发出的 `PFProviderProgress` 固定为：

```json
{
  "phase": "provider_processing",
  "determinate": false,
  "ratio": null,
  "completed_items": 0,
  "total_items": 4
}
```

Provider phase 只允许 `submitting / provider_processing / downloading / decoding`，`total_items` 必须等于 `PFGenRequest.batch`；Provider 不计算 elapsed，也不得发 materializing/cleaning。`completed_items` 是已完成解码或明确失败的 response items，单调 `0..batch`；Provider 多返回不扩大该进度分母。

协调器面向卡片/连线发出的 `PFRunProgress` 固定为：

```json
{
  "phase": "provider_processing",
  "determinate": false,
  "ratio": null,
  "completed_items": 2,
  "total_items": 4,
  "elapsed_ms": 1200
}
```

`phase` 只允许 `submitting / provider_processing / downloading / decoding / materializing / cleaning`。generation run 在多个 request 并发时取最下游活跃 phase，固定优先级为 `materializing > decoding > downloading > provider_processing > submitting`；cleanup 只用 `cleaning/materializing`。

- `ratio` 只允许 null 或单调 `0..1`；`determinate=true` 时 ratio 必须非 null，false 时必须为 null。
- 只有 Provider 给出真实比例时才显示百分比。
- 没有真实比例时显示不确定动画和已等待时间，绝不显示 `0%`。
- 协调器另生成 run 级 progress：total 是本 run 预建的预期 slots，completed 是其中已进入 succeeded/failed/canceled 的 slots，所以所有 request 终态时必须达到 total。它只显示“已完成 2/4”，不得伪装 Provider 内部百分比。
- generation run ratio 使用固定预期 slot 数作分母：已完全终态的 request 贡献其 requested_count；queued 贡献 0；仍在 Provider task 的 request 贡献 `provider_ratio * requested_count`。只有全部活跃 Provider tasks 都确定、且当前没有 materializing 时 run 才 determinate；任一 Provider 不确定或进入本地 materializing 时 run ratio=null。非 null 值在同一 run 内必须单调，终态为 1.0。
- cleanup 的 completed_items 只在一张完成/失败/取消后增加；现有 pipeline 没有真实的单张比例时，当前 cleaning operation 固定 determinate=false，不能按步骤数伪造百分比。
- `elapsed_ms` 只由运行协调器的可注入 monotonic clock 计算，不信任 Provider wall clock。

### 8.4 结构化 PFError

PFError 只表示已经进入 Queued/Running 后的执行失败，使用下列扁平结构；不存在第二层 `detail`：

```json
{
  "code": "rate_limited",
  "stage": "provider",
  "provider_id": "provider-id",
  "retryable": true,
  "retry_after_seconds": 30,
  "status_code": 429,
  "provider_code": "safe-code",
  "request_id": "request-uuid",
  "attempts": 1,
  "expected_count": 4,
  "received_count": 2
}
```

允许错误码固定为下列集合；新增 code 必须先修改本契约、双语映射和测试，Provider 不得临时发明字符串：

```text
auth_failed
rate_limited
quota_exceeded
invalid_request
network
timeout
content_policy
provider_internal
cancel_failed
ambiguous_result
malformed_response
result_count_mismatch
interrupted
cleanup_failed
```

校验规则：

- 除 `provider_code` 外，样例中的 `code/stage/provider_id/retryable/retry_after_seconds/status_code/request_id/attempts/expected_count/received_count` 全部必填；不适用的 `provider_id` 写空字符串，不适用的 retry/status 写 null，不得省略。`provider_code` 是唯一可省略字段；存在时必须通过下方正则；
- `code` 必须来自本节固定错误码；
- `stage` 只允许 `queue / http / provider / decode / materialize / cleanup / cancel`；运行前输入问题只能是 PFValidationIssue，不能伪造 `stage=input`；
- `retryable` 必须是 boolean；
- `retry_after_seconds` 只允许 null 或 `0..86400`；
- `status_code` 只允许 null 或 `100..599`；
- `provider_code` 只允许正则 `[A-Za-z0-9._:-]{1,64}`，不满足就省略；
- `request_id` 必须是本地生成的 request id；
- `attempts`：`stage=queue` 必须为 0；其他允许 stage 必须为 `1..3`；
- `expected_count/received_count` 为非负整数；
- 不允许额外键，不允许本地化 message；
- 禁止放入 Header、body、response、prompt、绝对路径、凭据或用户图片。

运行前字段错误不得伪造成 PFError。它们统一返回 `PFValidationIssue {code, field, args}`，例如 `missing_prompt_input/result_limit_exceeded/missing_reference/missing_cleanup_input`；保持卡片 Ready、聚焦 `field`，不创建 request。项目/Graph/模板加载错误返回 `PFLoadError {code,args}`；剪贴板和删除事务返回 `PFCommandError {code,args}`。这些结构都只存静态 code 和安全 args，不含已渲染文案；`unsupported_*_version`、`clipboard_*`、`source_node_busy` 由各自契约列举，不混进 PFError 的 attempts 规则。

### 8.5 重试和幂等

Beta 0.7 固定策略：

- 生成 POST 默认网络尝试次数为 `1`，即自动重试次数 `0`。
- OpenAI Image 和 RetroDiffusion 在本版都视为 `native_idempotency=false`。
- timeout、断网、429、5xx 都不得静默重发生成 POST。
- 无法确认服务端是否已经生成或扣费时返回 `ambiguous_result`，保留既有成功结果，由用户明确决定是否重新生成。
- 只有未来 Provider 契约附有官方服务端幂等证据、实际发送幂等键并有 mock 断言时，才允许同一 request 最多三次 attempt。
- 只有凭据验证等无副作用 GET 可自动重试，总 attempts 上限为 3。`Retry-After` 接受整数秒或 HTTP-date，换算后的单次等待必须 clamp 到 `0.25..30.0s`；没有该 Header 时两次等待固定为 `0.5s`、`1.0s`。Beta 0.7 不加 jitter，保证测试确定。不能把这条权限扩大到生成 POST。
- HTTP client 的重试等待必须注入 `RetryScheduler`（生产实现用 monotonic delay，并提供当前 UTC 供 HTTP-date 换算；测试实现只记录并手动推进），测试不得真实 sleep。
- “仅重试失败项”按失败 slot/request 分片，不按 `failed_row_ids` 重跑整行。
- 对象行被拆成 `[4,1]` 两个请求而后一片失败时，只允许重试 count=1。
- 所有用户触发的“重试此项”“仅重试可重试失败项”和“重新生成…”都必须先用本次将发送的 request 集合重新调用 `CostService.preflight`；确认取消或 blocked 时 slots 保持原终态、网络请求数为 0。任何按钮不得绕过预算入口直接调用 Provider。
- 已发出的生成 POST 若返回无法满足 §8.8 shape 的响应，默认表示“服务端可能已经执行或扣费”，必须归一化为 `ambiguous_result/retryable=false`。只有 transport/Provider 契约能以机器可验证字段证明请求未被接受、没有生成且不会计费时，才可使用 `malformed_response/retryable=true`；测试必须断言该证明条件，不能根据 HTTP 文案猜测。

失败槽动作固定为：

| code | retryable | 槽位按钮 |
|---|---:|---|
| `rate_limited` | true | `retry_after_seconds` 非 null 时到期后显示“重试此项”、此前禁用倒计时；null 时不画倒计时并立即允许人工 Retry |
| `network` | true | 只有能证明请求尚未发出时显示“重试此项”；提交结果不确定时必须改码 `ambiguous_result` |
| `result_count_mismatch / interrupted` | true | “重试此项” |
| `malformed_response` | 仅限上述“明确未接受且未计费”证明成立时 true | true 时“重试此项”，否则必须改码 `ambiguous_result` |
| `auth_failed / quota_exceeded` | false | “打开 Provider 设置” |
| `invalid_request` | false | “返回生成卡” |
| `content_policy` | false | “修改提示词” |
| `timeout / ambiguous_result` | false | “重新生成…”；二次确认可能重复计费，并创建新的完整 Output，不冒充原 request 重试 |
| `provider_internal` | false | “关闭”；保留脱敏 request id |
| `cancel_failed` | false | “关闭”；说明本地停止失败，远端可能继续处理或计费 |
| `cleanup_failed` | false | “调整设置后重新清洗”；新建完整 Output，不原位重试 |

UI 显示“重试此项/仅重试失败项”必须同时满足：`error.retryable=true`、等待期结束、Output `role=current|history`、`source_node_id` 非空且当前 Graph 中存在同 id/同类型来源节点、slot 的 input snapshot 完整有效。任一条件不满足都不显示 Retry；尤其 standalone 审计 Output 和剪贴板纯素材 Output 永远不可 Retry。重试排队时当前 slot 清除 error 并进入 queued；旧错误只保留在旧 request record。
`retry_after_seconds` 的人工倒计时从协调器收到规范错误的 monotonic 时刻开始，只存在内存；项目重开后已终态的 rate_limited 槽不恢复旧倒计时并立即允许人工 Retry，Retry 仍必须重新 preflight。不得把 wall-clock 时间写入 PFError。

OpenAI 当前官方模型页能证明图片模型使用 Image generation endpoint，并提供能力与价格入口；它不能替代 PixelForge 的请求级幂等证明。因此本版保守禁用自动重试：

- [OpenAI GPT Image 2 model](https://developers.openai.com/api/docs/models/gpt-image-2)

### 8.6 PF-SEC-01

当前已知事实：

- RetroDiffusion 发送 `X-RD-Token`。
- `pixel/infra/http_client.gd` 的通用 Header 脱敏没有覆盖该名称。
- 请求日志开启时存在把 key 写入本地日志的风险。
- 当前没有证据证明 key 已经泄漏；不得把“风险”写成“已泄漏事件”。

B7-1 必须实现：

- Header 名大小写不敏感。
- 明确脱敏 `authorization / proxy-authorization / x-api-key / api-key / x-rd-token / cookie / set-cookie`。
- Header 名包含 `token / secret / credential / api-key` 时也脱敏。
- 日志只保留允许的 URL scheme/host/path、method、attempt 和安全状态；删除完整 query。
- 不记录生成 request body、response body、完整外部响应或用户 prompt。
- Provider meta 使用显式白名单构造。
- 测试用唯一“凭据 sentinel”。raw mock transport 必须实际收到 sentinel，证明请求真的携带凭据；raw mock transport 的接收缓冲不参加泄漏扫描。

sentinel 门按产物首次出现的卡增量接入，不能要求 B7-1 扫描尚不存在的未来文件：B7-1 扫当时已有 transport/log/shared task/PFError/持久化表面；B7-2 加 v2 project/clipboard/generation+cleanup provenance；B7-4 加协调器状态和错误框技术详情；B7-9 最后加固定截图 manifest。每次扩展后，所有已接表面出现 sentinel 都失败。B7-1 的通过只关闭进入 B7-2 前的当前泄漏风险，不豁免后卡新增表面。

PF-SEC-01 未绿前，不得进入 B7-2。

### 8.7 费用

费用状态只允许：

```text
estimate | actual | unknown
```

金额格式固定：Provider/descriptor 入口只接受非负普通十进制字符串，不接受 float、指数、NaN 或货币符号；超过六位小数按十进制 half-up 舍入。归一化后统一保存为 `^(0|[1-9][0-9]{0,8})\.[0-9]{6}$` 的 USD 字符串，内部立即转换为 `micro_usd:int64`。加总、预算和月累计只用整数 micro-USD；显示时再格式化。契约测试必须断言 `0.100000 + 0.200000 = 0.300000`。

`PFProvider.estimate_cost(request)` 必须是同步、纯函数、无网络/文件/设置副作用：descriptor `cost_estimate=false` 时严格返回 null；为 true 时每个合法 request 必须返回上述规范 USD String，返回 float、负数、非法字符串或 null 都使 preflight blocked。Beta 0.7 的 `rd_pro` 固定按每个 requested item `0.250000` 估算，即 batch=2 返回 `0.500000`；其余三个云模型返回 null。

`CostService.preflight(requests:Array[PFGenRequest])` 在 Output 原子事务前调用一次，返回 shape 固定为：

```json
{
  "decision": "allowed",
  "estimate_state": "estimate",
  "estimated_total_usd": "0.500000",
  "estimated_total_micro_usd": 500000,
  "month_total_micro_usd": 250000,
  "projected_month_total_micro_usd": 750000,
  "budget_micro_usd": 1000000,
  "reason_code": "within_budget"
}
```

- `decision` 只允许 `allowed / needs_confirmation / blocked`；`estimate_state` 只允许 `estimate / unknown`。
- 全部 request 有合法 estimate 时用 int64 求和并填上方数字；任一 request estimate=null 时 state=unknown，两个 estimated 字段和 projected 字段必须 null，decision=allowed、reason_code=`unknown_estimate`，UI 明示无法用预算判断，但沿用现有策略不强制确认。
- budget=0 表示无上限；已知 estimate 且 `month_total + estimate > budget > 0` 时 decision=`needs_confirmation`、reason_code=`budget_exceeded`；未超出为 decision=allowed、reason_code=`within_budget`。
- Provider/model 缺失、descriptor 声称可估却返回 null、金额非法或 int64 溢出时 decision=`blocked`、`reason_code` 只允许 `provider_unavailable / invalid_estimate / amount_overflow`，保持 Ready 且不得创建 Output。
- 每个 request_id 在数组中必须唯一；provider_id 可以因 `[4,1]` 等分片重复，且每个 request 自己的 `(provider_id,request_id)` 组合必须有效。preflight 不生成 id、不修改 ledger。用户确认 needs_confirmation 后才能继续原已规划 requests，取消则不发请求。

费用设置和 ledger 同时硬切整数存储：`provider_budget_v2.monthly_micro_usd` 与 `provider_cost_v2_<YYYY-MM>` 只存 int64；旧 float bucket 不读取、不迁移。设置 UI 接受普通十进制文本并通过同一 parser 写整数，不用 SpinBox/binary float；`0` 写 0 表示无上限。

- estimate 只用于提交前提示，不进入月累计。
- actual 才进入月累计。
- unknown 显示“未知”，禁止显示 `$0`。
- `CostService` 是预算阈值和确认策略的唯一入口；协调器在创建 Output/排队前调用一次 preflight，UI 只呈现其 decision，不在生成卡复制预算规则。用户取消确认或 blocked 时保持 Ready，网络请求数和新 Output 数都为 0。
- Provider 有 charge id 时去重 key 为 `provider_id + ":charge:" + charge_id`；没有时为 `provider_id + ":request:" + request_id`，防止跨 Provider 碰撞。
- `CostService.record_once(key:String, micro_usd:int)` 同键调用两次只能累计一次。
- 每个终态 request record 最多调用一次 `record_once`；一个 run 有多个收费 request 时逐 request 记录，再用十进制相加得到 run actual。不得把整 run 金额重复写到每个 slot。
- Partial 只记录 Provider 明确返回的实际费用一次，不按图片数量重复乘。
- Failed 且 Provider 未返回 actual 时不记账。
- 预算确认取消后不得排队和发请求。

### 8.8 Provider 配置、能力和结果归一化

`PFProviderService` 是 Provider 配置与凭据的唯一入口：

- `ProviderSettingsDialog → PFProviderService → CredentialStore/Provider` 是唯一 UI/数据路径；
- 删除或重定向旧 OpenAI session/config 对话框和任何直接 Provider 配置入口，不能保留两套设置真相；
- 插件不得直接读写 SettingsService 或 CredentialStore；
- Graph/project/template/provenance 只保存 provider/model id 和非敏感生成参数；
- password/secret 只在 CredentialStore，Provider 仅在内存收到解密值；
- 保存配置后状态为 Configured，不得在未验证时伪装 Verified；
- 验证状态只允许 `unconfigured / configured / validating / verified / invalid`；
- descriptor 声明 `safe_validation=true` 的 OpenAI 只有 `verified` 才能生成；其他状态在生成卡内提示先验证。验证动作只能走 §8.5 的安全模型 GET。
- RetroDiffusion 当前实现用一条带 `credential validation` prompt 的生成 POST 验证 key；B7-1 必须删除这条伪验证。除非契约附有官方无副作用验证端点证据，否则 descriptor 写 `safe_validation=false`：设置页不显示“验证”按钮，只显示“保存后将在首次真实生成时验证”；`configured` 允许用户明确点击真实生成，第一次成功响应后标为 verified，鉴权失败后标为 invalid。禁止后台或保存时发送哑元生成请求；
- 验证失败必须进入 Invalid 并提供本地化下一步，不能只在日志失败；
- 删除凭据后清除 Provider 内存配置和 verified 状态。

`get_config_schema()` 的 `kind` 词表在 Beta 0.7 只允许 `string / password / bool / enum`；不得继续接受旧 `text`，也不得把生成动态参数的 `int/float` 控件混入凭据配置。`string/password/bool` 字段必须且只能有 `key/kind/label_key/help_key/required/default` 六个键；`enum` 额外且必须有 `values`。规则固定为：key 匹配 `[a-z][a-z0-9_]{0,63}` 且单 schema 唯一；label/help key 经 `SchemaTextResolver` 双语校验；required 是 boolean；string/password default 是 String，password 必须为 `""` 且不得把已存 secret 回填 UI；bool default 是 boolean；enum values 是非空唯一 String 数组且 default 属于 values。出现 raw `label/help/description`、未知 kind、未知额外键或错误类型都使 Provider 注册失败。

字段样例固定为：

```json
{
  "key": "api_key",
  "kind": "password",
  "label_key": "PROVIDER_FIELD_API_KEY",
  "help_key": "PROVIDER_FIELD_API_KEY_HELP",
  "required": true,
  "default": ""
}
```

不得使用 raw `label/help/description`。两个范围内 Provider 的完整配置 schema 不允许执行者自行补字段：

```json
{
  "openai_image": [
    {"key":"api_key","kind":"password","label_key":"OPENAI_FIELD_API_KEY","help_key":"OPENAI_FIELD_API_KEY_HELP","required":true,"default":""}
  ],
  "retrodiffusion": [
    {"key":"api_key","kind":"password","label_key":"RETRO_FIELD_API_KEY","help_key":"RETRO_FIELD_API_KEY_HELP","required":true,"default":""},
    {"key":"endpoint","kind":"string","label_key":"RETRO_FIELD_ENDPOINT","help_key":"RETRO_FIELD_ENDPOINT_HELP","required":true,"default":"https://api.retrodiffusion.ai/v1/inferences"}
  ]
}
```

OpenAI/Retro `api_key` 只进 CredentialStore；其他字段进普通 Provider config。测试注入 URL 必须走构造参数/mock transport，不能把未列出的 `generation_url/edit_url/validation_url` 暴露为生产 schema 字段。

每个 model descriptor 至少包含：

```text
provider_id
model_id
display_name
is_default
ui_scope
provider_meta_keys
capabilities.txt2img/img2img
capabilities.max_reference_images
capabilities.max_batch
capabilities.target_size_constraints
capabilities.provider_output_sizes
capabilities.native_pixel
capabilities.native_idempotency
capabilities.safe_validation
capabilities.seed
capabilities.transparent_bg
capabilities.cost_estimate
dynamic_params[]
```

`target_size_constraints` 固定描述用户真像素目标的 min/max/step/allowed combinations；`provider_output_sizes` 是 Provider 接口真实接受的有序尺寸数组；`native_pixel` 必须是 boolean。RetroDiffusion descriptor 写 `native_pixel=true`，OpenAI Image descriptor 写 `native_pixel=false`。生成卡只按 descriptor 显示和校验；不得在 UI 另写模型能力表。

`ui_scope` 在 Beta 0.7 范围内固定为 `main`。生成卡只列出 OpenAI Image 与 RetroDiffusion 的 main descriptors；每个 Provider 必须恰好一个 is_default=true。

`provider_meta_keys` 必须是排序后的唯一安全 key 字符串数组；key 匹配 `[a-z][a-z0-9_]{0,63}`。同一 Provider 的所有 descriptors 必须逐项相同，否则插件注册失败。Provider result 的 `provider_meta` 只能包含该数组中的 key，不能由插件临时扩表；OpenAI 与 RetroDiffusion 固定为 `["remote_task_id"]`，值校验仍按 §7.1。

两个结构的 JSON shape 固定为：

```json
{
  "target_size_constraints": {
    "min_width": 1,
    "max_width": 512,
    "width_step": 1,
    "min_height": 1,
    "max_height": 512,
    "height_step": 1,
    "allowed_sizes": []
  },
  "provider_output_sizes": [[1024, 1024], [1536, 1024], [1024, 1536]],
  "dynamic_params": [
    {
      "key": "quality",
      "kind": "enum",
      "default": "low",
      "required": false,
      "values": ["auto", "low", "medium", "high"],
      "min": null,
      "max": null,
      "step": null,
      "label_key": "GEN_PARAM_QUALITY",
      "help_key": "GEN_PARAM_QUALITY_HELP",
      "advanced": false,
      "template_safe": true
    }
  ]
}
```

- `allowed_sizes` 非空时只接受其中的正整数 pair；为空时按 min/max/step。`native_pixel=true` 时 `provider_output_sizes=[]` 且请求尺寸直接使用 target；false 时数组必须非空。
- 每个 dynamic param 必须完整保存样例中的 `key/kind/default/required/values/min/max/step/label_key/help_key/advanced/template_safe`；不适用的 values 写 `[]`，不适用的 min/max/step 写 null，不得省略后由 UI 猜。dynamic `kind` 只允许 `bool/int/float/enum/string`；enum 必须有非空 values，int/float 才能使用非 null min/max/step，password/secret 不允许出现在生成参数。条件显示时额外允许唯一 shape `visible_when:{"mode":"img2img"}`；无条件时省略该键。未知或 shape 不合法使插件注册失败。
- 非 native 尺寸比较不得靠浮点猜：候选 `a` 的比例误差分子为 `abs(a.w*target_h - target_w*a.h)`。比较 a/b 时比较 `a_error*b.h` 与 `b_error*a.h`；较小者胜，相等时取 descriptor 数组靠前项。所有乘法用 64-bit 并先验证尺寸上限，契约测试覆盖横、竖、方和 tie。

现有两个云端 Provider 的 v2 descriptor 不允许执行者自行猜：

| model | display_name | target constraints | provider sizes | refs/batch | flags |
|---|---|---|---|---|---|
| `openai_image/gpt-image-2` | `GPT Image 2` | min `16×16`，max `512×512`，step 1 | `1024×1024,1536×1024,1024×1536` | refs 4，batch 4 | ui_scope=main、meta keys=`[remote_task_id]`、is_default=true、txt2img=true、img2img=true、native_pixel=false、seed=false、transparent_bg=false、native_idempotency=false、safe_validation=true、cost_estimate=false |
| `retrodiffusion/rd_plus` | `Retro Diffusion Plus` | 每边 `16..128`，step 1 | `[]` | refs 1，batch 4 | ui_scope=main、meta keys=`[remote_task_id]`、is_default=true、txt2img=true、img2img=true、native_pixel=true、seed=true、transparent_bg=true、native_idempotency=false、safe_validation=false、cost_estimate=false |
| `retrodiffusion/rd_pro` | `Retro Diffusion Pro` | 每边 `16..256`，step 1 | `[]` | refs 1，batch 4 | ui_scope=main、meta keys=`[remote_task_id]`、is_default=false、txt2img=true、img2img=true、native_pixel=true、seed=true、transparent_bg=true、native_idempotency=false、safe_validation=false、cost_estimate=true |
| `retrodiffusion/rd_fast` | `Retro Diffusion Fast` | 每边 `16..384`，step 1 | `[]` | refs 1，batch 4 | ui_scope=main、meta keys=`[remote_task_id]`、is_default=false、txt2img=true、img2img=true、native_pixel=true、seed=true、transparent_bg=true、native_idempotency=false、safe_validation=false、cost_estimate=false |

OpenAI dynamic_params 恰好是上方完整 quality 对象。三个 Retro model 的 dynamic_params 必须逐字段相同，且恰好为：

```json
[
  {
    "key": "remove_bg", "kind": "bool", "default": true, "required": false,
    "values": [], "min": null, "max": null, "step": null,
    "label_key": "GEN_PARAM_REMOVE_BG", "help_key": "GEN_PARAM_REMOVE_BG_HELP",
    "advanced": false, "template_safe": true
  },
  {
    "key": "strength", "kind": "float", "default": 0.8, "required": false,
    "values": [], "min": 0.0, "max": 1.0, "step": 0.01,
    "label_key": "GEN_PARAM_STRENGTH", "help_key": "GEN_PARAM_STRENGTH_HELP",
    "advanced": false, "template_safe": true,
    "visible_when": {"mode": "img2img"}
  }
]
```

OpenAI 的 `background=opaque` 与 `output_format=png` 在本版是 Provider 内固定传输值，不进入 `extra`；Retro 的 seed 只走顶层。

Provider 成功结果必须在离开插件边界前归一化：

```json
{
  "request_id": "request-id",
  "items": [
    {"index": 0, "image": "Image runtime value", "actual_seed": 42, "error": null},
    {"index": 1, "image": null, "actual_seed": null, "error": "PFError with stage=decode"}
  ],
  "actual_cost_usd": null,
  "charge_id": "",
  "provider_meta": {
    "remote_task_id": "optional-safe-id"
  }
}
```

- `items` 保持 Provider 原始项目顺序，`index` 必须从 0 连续递增且唯一。成功项恰好有 RGBA8 `image` 且 error=null；解码失败项 image=null 且有脱敏 PFError。`actual_seed` 只允许 null 或 `0..2147483647`，失败项必须 null；Provider 未明确返回实际 seed 时成功项也写 null。禁止先过滤坏图再返回压缩 images 数组。
- 每个成功解码图片的实际宽高必须等于该 request 的 `provider_output_size`；不等时禁止隐式缩放，当前 item 改为 `image=null/error=ambiguous_result(stage=decode,retryable=false)`，因为远端已执行且可能计费。其他合法 items 仍保留，actual cost/charge 仍按响应记录一次。
- 协调器按 index 映射本 request 的 slot：`index < requested_count` 原位回填；额外 index 只有在该 item 成功时才追加 succeeded/unexpected slot，并创建 §7.1 的安全 snapshot；额外失败 item 不对应用户请求的结果，不创建 slot、不改变 expected-slot request state，只写一条不含 Provider 文案的结构化安全诊断。`received_count` 仍统计所有成功解码项，因此可能大于 requested_count。Provider 少返回的尾部 slot 写 `result_count_mismatch`。重复、负数或断裂 index 属于无法满足本 shape 的响应，按 §8.5 转成 `ambiguous_result`；只有已有明确“未接受且未计费”证明时才可用 `malformed_response`。已在更早 request 中成功的素材仍保留。
- `actual_cost_usd` 为 null 或非负 USD 十进制字符串；null 表示 unknown，不得转 0 或用 binary float 累计。
- `provider_meta` 只允许对应 descriptor 的 `provider_meta_keys`；内置 Provider 当前只允许 `remote_task_id`。协调器把规范化后的同一安全对象复制进对应 request record，禁止写进 slot、错误框或日志；未知键使结果校验失败，不做宽松丢弃。
- 原始 response 只存在于解析函数局部变量，归一化完成后不得进入 task、日志或项目。
- Provider 有远端异步 task 时，插件内部负责轮询并报告结构化 phase；UI 不直接解释远端 payload。
- `cancel(request_id) -> PFCancelTaskV2`：同一 request 重复调用必须返回同一个 wrapper。wrapper 只在本地 HTTP/worker 已停止回调、不会再物化结果时 resolved，结果严格符合 §8.2 `PFCancelResult`；只有本地停止失败或本地停止在 5 秒 settle deadline 内无法被证明时才 rejected 一个 `cancel_failed` 安全 PFError。远端取消失败/无能力/超时不能把已经本地停止的 wrapper 变成 rejected，只能 resolved 且 `remote_cancel_confirmed=false`。协调器必须等待本 run 全部 cancel wrappers 终态，再按 §8.3 进入 Canceled 或 Failed。仍在本地队列且未调用 Provider 的 request 由协调器直接生成 `remote_cancel_confirmed=true/billing_update=null`，不调用 Provider。

## 9. 生成与清洗结构卡最终 UI

### 9.1 `ai_generate` 生成卡

固定尺寸：

```text
default = 400 × 520
min     = 360 × 400
max     = 1600 × 1200
header  = 40
footer  = 56
```

这些数值保持 Beta 0.6 的 `ai_generate` 2B 边界；本轮只重排卡内内容，不改变生成卡尺寸契约。正文超过可用高度时只滚动正文；Header、运行状态条和 Footer 不滚动。

正文从上到下只有六组：

1. 运行状态：Ready、Queued、Running、Canceling、Partial、Failed、Complete、Canceled；显示等待时间，未知进度用不确定动画。
2. Provider：Provider、Model、可用性和设置入口。
3. 输入摘要：对象清单/自由提示词、参考图数量、风格提示词名；点击摘要跳到上游节点，不在本卡复制编辑上游文本。
4. 生成核心参数：最终提示词只读预览、目标宽、目标高、比例锁、单提示词结果数；对象 rows 有效时数量只读。`native_pixel=false` 时另显示只读“Provider 输出尺寸”，明确提示结果保持原生尺寸、需要时在清洗节点缩到目标尺寸。
5. Provider 动态参数：只从 descriptor/schema 生成；seed、quality、transparent background 等在这里；Advanced 默认折叠；不支持的字段不显示。
6. 固定 Footer：费用 estimate/actual/unknown 和唯一主按钮；按钮行为只能来自下表，不能按最后一个错误临时猜。

| 卡片/错误条件（从上到下匹配） | Footer 唯一主按钮 |
|---|---|
| Ready | “生成” |
| Queued/Running | “取消” |
| Canceling | 禁用“正在取消” |
| Complete/Canceled | “再次生成”；preflight 后创建新 Output |
| 任一 `cancel_failed` | 禁用“取消失败”；只允许从错误框关闭/查看安全详情，避免立刻重复下单 |
| Partial/Failed 且至少一个 retryable 槽仍在 Retry-After | 禁用“可在 Ns 后重试” |
| Partial/Failed 且至少一个 retryable 槽可执行 | “仅重试可重试失败项”；复用原 Output |
| 无可重试槽且有 `auth_failed/quota_exceeded` | “打开 Provider 设置”；状态不变 |
| 无可重试槽且有 `content_policy` | “修改提示词”；状态不变 |
| 无可重试槽且有 `invalid_request` | “返回生成卡”；聚焦相关字段，状态不变 |
| 无可重试槽且有 `timeout/ambiguous_result` | “重新生成…”；二次确认可能重复计费，preflight 后创建新 Output |
| 仅剩 `provider_internal` | “再次生成”；preflight 后创建新 Output，不冒充原 slot Retry |

多个不可重试错误同时存在时，固定优先级为 `cancel_failed > auth/quota > content_policy > invalid_request > timeout/ambiguous_result > provider_internal`。`malformed_response` 只有 retryable=true 才合法，因此走 Retry 行；`result_count_mismatch/interrupted` 也走 Retry 行。Footer 动作和错误弹框动作可以不同，但都不能修改错误的 retryable 值。

运行前尺寸、Provider、模型、凭据等本地错误显示在对应字段下并聚焦字段，不弹终态错误框。

### 9.2 `pixel_cleanup` 清洗卡

固定尺寸：

```text
default = 420 × 680
min     = 360 × 480
max     = 800 × 1000
header  = 40
footer  = 56
```

Header、32px 运行状态条和 Footer 固定；只有正文滚动。正文分组与顺序不得改变：

1. **输入摘要**：显示来源类型与标题（Output / Image Input / Reference Set）、可处理素材数和只读派生目标尺寸；点击跳到来源。来源不存在、类型不在 §6.6 白名单、batch 没有可见成功素材、image/reference 为空或任一素材损坏时在本组显示内联错误并禁用开始。
2. **清洗预设**：选择 CleanupPreset 时把完整 settings 复制进节点并写 preset id；用户随后改动任一控件立即清空 preset id，但不还原其他值。
3. **网格检测**：Auto/Manual、只读 base size 先验，以及唯一一组共享 scale、offset x/y。Auto 时 shared scale/offset 继续可见但禁用；Manual 时启用；base size 始终只读。切换模式不清空禁用字段。
4. **重采样**：enabled、mode、只读 target size，并注明使用上组 shared scale/offset，不再画第二组控件。关闭 enabled 后 mode/target 提示保持原位置但禁用，不折叠、不产生布局跳动。
5. **量化**：enabled、mode、palette、strategy、k、dither、strength、chroma、density。关闭 enabled 或 mode=`none` 时其余控件可见但禁用；`auto_k` 只启用 strategy/k；`fixed_palette` 只启用 palette；dither 不是 `none` 时才启用 strength/chroma/density。Strength 同时写 `dither_strength` 与 `dither_contrast`。
6. **上次报告**：运行结束后默认折叠，只展示 input/output size、实际 grid、每步 enabled、颜色数、逐项失败数和耗时；报告不包含新的执行按钮，也不改变 settings。

调色板下拉、颜色条预览、导入和删除必须复用现有 `PaletteRegistry`；导入/删除是资源动作，不得向 settings 再加 `palette_json/path/colors` 第二份真相。改变任何参数只更新 Graph params 和 Undo，不安排 preview Timer、不调用 pipeline、不创建素材。

Footer 是唯一执行入口：

- Ready：主按钮“开始清洗”；
- Queued/Running：同一位置变为“取消”；Queued 显示排队，Running 状态条显示确定的“已完成 x/y”和由协调器计算的 elapsed；单张 pipeline 内部没有真实比例时不显示百分比；
- Canceling：按钮禁用并显示“正在取消”；
- Partial/Failed 且存在满足 §8.5 Retry 前置的 `interrupted` 槽：显示“仅重试中断项”，只把这些槽按原 input snapshots 排回同一 Output；不得重跑已成功项，也不得读取当前节点新设置；
- Complete/Canceled，以及没有可重试 interrupted 槽的 Partial/Failed：显示“开始清洗”，再次点击读取当前输入/设置并创建新的 Output；
- 来源节点或 snapshot 不存在时不显示“仅重试中断项”；standalone Output 只能保留审计，不能借清洗卡或 Output 菜单恢复 Retry。

点击“开始清洗”时一次性快照有序输入 asset ids 和完整 settings；运行中编辑被禁用。任何实现都不得边处理边读取可变控件值。

## 10. Output 最终 UI

### 10.1 参考边界

本轮复刻的是 Infinite-Canvas 的应用行为，不是视觉资产：

- 多图 Output 最多显示三行；
- 超过三行后网格内部纵向滚动；
- pending 先出现并原位回填；
- 图片可便捷拖出成独立卡；
- 旧 Output 保留为历史，不被新结果覆盖。

固定参考：

- [最多三行的布局常量](https://github.com/hero8152/Infinite-Canvas/blob/bc7efbde9ddab02f11abf738d7309b5689dbfa22/static/js/smart-canvas.js#L1292-L1298)
- [多图网格滚动行为](https://github.com/hero8152/Infinite-Canvas/blob/bc7efbde9ddab02f11abf738d7309b5689dbfa22/static/js/smart-canvas.js#L7180-L7185)
- [滚动样式证据](https://github.com/hero8152/Infinite-Canvas/blob/bc7efbde9ddab02f11abf738d7309b5689dbfa22/static/css/smart-canvas.css#L407-L417)
- [拖出图片行为](https://github.com/hero8152/Infinite-Canvas/blob/bc7efbde9ddab02f11abf738d7309b5689dbfa22/static/js/smart-canvas.js#L15745-L15772)

### 10.2 几何

所有公式中的 `n` 固定为 `result_slots` 中 `detached=false` 的槽位数，不区分 queued/running/succeeded/failed/canceled。detached 成功槽保留审计计数，但不占网格位置。

固定值：

```text
default_width       = 600
min_width           = 360
max_width           = 960
top_rail_height     = 32
horizontal_padding  = 16
vertical_padding    = 16
tile_gap            = 8
max_columns         = 4
max_visible_rows    = 3
tile_min            = 96
tile_max            = 176
empty_height        = 240
```

当 `n >= 2`：

```text
capacity_columns =
  clamp(floor((card_width - 2*horizontal_padding + tile_gap)
        / (tile_min + tile_gap)), 1, 4)

desired_columns = clamp(ceil(sqrt(n)), 1, 4)
columns = min(capacity_columns, desired_columns)

tile_size =
  min(tile_max,
      floor((card_width - 2*horizontal_padding
             - (columns - 1)*tile_gap) / columns))

rows = ceil(n / columns)
natural_visible_rows = min(rows, 3)
natural_grid_height =
  natural_visible_rows*tile_size
  + max(0, natural_visible_rows - 1)*tile_gap

natural_card_height =
  top_rail_height + 2*vertical_padding + natural_grid_height
```

滚动条必须画成网格右缘的 overlay：视觉宽 `4px`，命中宽 `12px`，不占布局宽度。因此上述列数和 tile 公式不减滚动条宽度；不得在有/无第四行时让列宽跳变。

默认宽 `600`、`n >= 10` 时为四列，tile `136`；三行网格高 `424`，自然卡高 `488`。`13`、`50` 或更多结果都不会继续向下增长。

`n == 1`：

- 图片按原始比例 `contain`；succeeded 槽使用解码图片真实宽高比，queued/running/failed/canceled 槽统一使用该 slot 的 `planned_size` 宽高比；
- `source_w/source_h` 为成功图片真实尺寸，其他状态为 `slot.planned_size`；不得从当前生成卡 target、已编辑清洗节点或来源素材现场重算；
- `single_viewport_height = clamp(round((card_width - 32) * source_h / source_w), 176, 420)`；
- `natural_card_height = 32 + 32 + single_viewport_height`；
- 默认宽 `600` 时可用宽 `568`，视口高不超过 `420`；
- 图片不得裁切；
- 自然卡高最大 `484`。

`n == 0`：

- 高度 `240`；
- 只允许两种数据原因：`result_slots=[]`，或所有 slots 都是 `succeeded && detached=true`。failed/canceled/queued/running 槽不能 detached，因此只要存在就有 `n>0` 并显示自己的终态 tile；
- 所有成功图都已拆出时，按 `origin_graph_id/origin_batch_node_id/origin_slot_id` 查当前画布：至少一个对应 sprite 仍存在时显示“所有图片已拆出”和唯一动作“在画布中定位”；全部对应 sprite 都已被用户删除时显示“拆出的图片卡已删除”和唯一动作“恢复到 Output”。恢复命令把这些 slots 的 detached 原子改回 false、不复制位图，并产生一条 Undo；混合存在/删除时主动作仍为定位，删除项只可通过各自删除 Undo 恢复；
- 真正没有 slot 且仍有来源节点时显示“尚未运行”和唯一动作“运行来源节点”；standalone 空容器显示“暂无图片”且无虚假 Retry；
- 不显示空白网格。

与 2B 的结合方式：

- Output 卡保存用户请求的卡片 `size.x/size.y`，与生成目标尺寸无关。
- 宽度允许 `360..960`；这条明确替代 Beta 0.6 对 Output 的旧 `1600` 最大宽，其他类型卡的 2B 尺寸范围不变。
- `n >= 2` 时高度范围精确为 `top_rail_height + 2*vertical_padding + tile_size` 到 `natural_card_height`。
- `n == 1` 时高度范围为 `240..natural_card_height`；`n == 0` 时固定 `240`。
- 用户缩小高度时网格内部滚动；允许露出下一行的一部分作为滚动提示。
- 用户放大到上限后也不能显示第四行。
- 双击缩放手柄恢复自然尺寸。
- 通用折叠保留；折叠只显示标题、数量和状态，不恢复旧 Review 模式。

### 10.3 32px 顶部信息轨

从左到右固定为：

1. 本地化“结果”或用户自定义标题；
2. 成功数 / 总槽位数，例如 `6 / 8`；
3. 执行状态：排队、生成中、部分成功、完成、失败或已取消；history Output 在状态旁另加 `历史 · {原终态}`，`role` 不得覆盖原终态；
4. 批量下载；
5. 拆出全部；
6. Graph 端口。

信息轨不得放清洗、抠图、描边、量化参数。

### 10.4 网格滚动

- 网格内容高度大于当前网格视口时才启用纵向滚动。卡片处于自然高度时这等价于“第四行开始滚动”；用户按 2B 主动缩短卡片后，第二或第三行也可以进入同一个网格滚动区。
- 鼠标在网格时，普通滚轮先滚网格；到顶部/底部后才传给画布。
- 画布缩放修饰键仍优先。
- 状态更新、单张回填和失败重试不重置滚动位置。
- 新 run 的新 Output 从顶部开始。
- 滚动后的缩略图继续支持点击、双击、拖出、悬停动作和准确命中。

### 10.5 pending 与终态槽位

- 创建运行时立即建立全部稳定 slot。
- Queued：静态占位和排队图标。
- Running：shimmer 和已等待时间；无真实进度不显示百分比。
- Succeeded：原槽原位替换图片。
- Failed：保留原槽并显示错误图标；只有同时满足 §8.5 的 retryable、等待、role、来源和 snapshot 全部前置才显示“重试此项”，等待中显示禁用倒计时，其他情况只显示对应的设置/提示词/重新生成/关闭动作或纯审计状态。
- Canceled：保留灰色槽。
- Succeeded 且 `detached=true`：不在网格显示，但继续按成功终态计数并保留来源审计。
- 同一 run 的成功、失败、等待槽混合原位显示，不因返回顺序重排。

### 10.6 选择和拆出

单图：

- 单击选中；
- 双击大图预览；
- 选中后在 Output 上方显示浮动工具条；
- 工具条顺序固定为“预览 → 打开编辑器 → 拆出图片 → 下载”；
- pending/failed/canceled 不显示图片工具条。
- Output 最新 run 为 Queued/Running/Canceling 时，成功 tile 仍可选中、预览和下载，但“打开编辑器”“拆出图片”“拆出全部”禁用并显示“运行结束后可用”；拖动不得进入拆出阈值，也不得创建 Undo。终态后立即恢复。

拖出是“移动出 Output”，不是复制：

1. 成功缩略图按下左键；
2. 屏幕累计移动超过 `8px` 进入拆出；
3. 独立图片卡跟随鼠标；
4. 原 slot 保持 Succeeded，把 `detached` 设为 true 并从 Output 隐藏；
5. 独立卡引用同一 `asset_id`，不复制位图；
6. 独立卡写 `origin_graph_id / origin_batch_node_id / origin_slot_id` 完整三元组；
7. 整个动作只有一条 Undo；
8. Esc、pointer cancel 或无效 drop 完整恢复原 slot。

“拆出全部”：

- 只处理当前 Output 中 `status=succeeded && detached=false` 的 slot；
- 在 Output 右侧最多四列、卡间距 `24` 排列；
- 保持原顺序；
- 是一个 Undo 事务；
- 超过 12 张先显示本地化确认框；
- 不删除 Output，不处理 pending/failed/canceled。

必须允许拆出最后一张；最后一张拆出后 Output 保留并显示空态，因为 Graph 节点不能被隐式删除。这是 PixelForge 相对参考项目的刻意差异：参考项目可以移除最后图片并删除/收起容器，本项目必须保留 Graph 节点身份和 Undo 来源。

### 10.7 必须删除的旧 Batch 行为

从实现、持久化、菜单和测试中删除，而不是只隐藏：

- 3C 自动增高和全部展开公式；
- Contact / Focus 两套结果布局；
- Keep / Reject / Flag；
- All / Pending / Keep / Reject / Flag 审阅筛选；
- `focus_asset_id / compare_asset_ids / compare_mode`；
- Current / Previous / Split；
- 旧多选审阅工作流；
- Output 内直接清洗、重采样、量化以及右侧检查器的临时清洗参数；
- 新结果覆盖或混入旧 Output；
- 旧 `batch_card` 兼容渲染路径；
- 把审阅 pending 与运行 pending 混用的代码。

保留并重接到新 UI：

- 标题编辑和尺寸保存；
- Preview；
- 打开编辑器；
- 单张/批量下载；
- 拆出；
- `asset_list` 下游；
- provenance；
- Retry failed；
- Undo/Redo；
- 保存和重开。

既有抠图、切片、描边等独立工具入口若当前已经实现，必须接回现有 overflow/全局动作并继续调用原对话框和服务；它们不是 `pixel_cleanup` 参数，也不是本轮删除或重做范围。

## 11. 连线“发光液体推进”状态机

连线效果只读统一运行协调器状态，UI 不得根据卡片文字自行猜。

`GenerationRunCoordinator` 与 edge renderer 都必须通过构造/初始化注入 `Clock` 接口；生产实现读取 monotonic time，测试使用可手动推进的 `FakeClock`。业务代码不得直接读取 wall clock。固定截图先把 fake clock 推到指定 elapsed/phase 后采样，保证连线位置和等待时间可复现。

状态：

```text
idle | queued | active | succeeded | partial | failed | canceled
```

转换：

```text
点击且本地校验、预算确认、排队都成功 → queued
Provider 接受任务或本地清洗开始          → active
本次下游成功产出                        → succeeded
本次下游有成功也有失败                  → partial
终态错误且允许的自动尝试已耗尽          → failed
用户取消确认                            → canceled
succeeded 保持 800ms 后                  → idle
partial 保持 1200ms 后                   → idle
failed 保持 1200ms 后                    → idle
canceled 保持 400ms 后                   → idle
```

视觉：

- idle：现有静态线，`2px`。
- queued：源端低频呼吸光点，不前进。
- active：静态底线之上叠加外层 `8px` 青绿色 `alpha 0.28` 和内层 `2.5px` 亮青色；dash `14/10px`，按源到目标方向 `90 屏幕 px/s` 前进。
- succeeded：整线亮起后淡出。
- partial：停止推进后整线做一次 warning 琥珀色脉冲。
- failed：停止推进后红色短脉冲一次。
- canceled：灰色淡出。

规则：

- 只动画当前 `run_id` 目标执行闭包内的边。
- 并发 run 使用独立相位和状态，不让无关分支发光。
- Canceling 立即停止“向前成功”的视觉，改为静态 warning 线，等待 Canceled。
- Partial 在最后一个请求终态后进入 partial 琥珀脉冲，然后回 idle；一条 Graph 边不得同时伪装成“成功边”和“失败边”。
- 线动画不进入 Graph、Undo 或项目视觉字段；项目重开把残留 active slots 标成 `failed/interrupted`，不恢复网络任务或流光。
- 没有 active edge 时停止 animation tick，空闲画布不得持续刷新。
- 10%/25% LOD 只显示单个移动光点，不画外发光。
- 动画不得改变端点、命中区、选择、相机或卡片 bounds。

## 12. 错误弹窗

### 12.1 不弹框的情况

- 宽高、数量、Provider、模型、凭据、预算等运行前校验失败：字段内错误并聚焦。
- 安全允许的网络尝试仍在进行：保持运行反馈。
- 用户主动取消且所有 cancel tasks 成功：不弹错误框；`cancel_failed` 仍按终态执行错误弹一次。
- 项目打开时恢复出的 `interrupted`：不在启动时打断用户；在原 slot/Output 显示“上次运行被中断”和可重试动作。

### 12.2 终态弹框

自动尝试耗尽、Provider 拒绝、鉴权、额度、内容策略、超时、不确定结果或损坏响应，按以下顺序：

1. 停止该 run 的连线推进；
2. 保存已经成功的素材；
3. 把失败/缺失槽更新为 Failed；
4. 写入脱敏 PFError；
5. 每个 run 只弹一个本地化错误框。

Partial 等全部分片终态后弹一次汇总，例如“完成 6 张，2 张失败”。至少一个失败槽 `retryable=true` 时，主要动作才是“仅重试可重试失败项”，且不可重试槽保持原状。全部不可重试时不显示 Retry，按固定优先级选择一个修复动作：`auth/quota → 打开 Provider 设置`，`content_policy → 修改提示词`，`invalid_request → 返回生成卡`，`timeout/ambiguous_result → 重新生成…并二次确认`，其余 → 关闭并保留 request id。

错误框固定包含：

1. 本地化标题；
2. 通俗原因；
3. 受影响结果数；
4. 推荐下一步；
5. 主要动作；
6. “关闭”；
7. 折叠技术详情，只允许错误码、Provider 名和脱敏 request id。

§8.4 每个固定 PFError code 都必须有 English/简中静态映射；会进入终态弹框或 slot 动作的映射固定如下：

| code | 主要动作 |
|---|---|
| `auth_failed` | 打开 Provider 设置 |
| `rate_limited` | 关闭；显示可重试时间 |
| `quota_exceeded` | 打开 Provider 设置 |
| `invalid_request` | 返回生成卡并聚焦字段 |
| `network` | 关闭并检查网络 |
| `timeout / ambiguous_result` | 关闭；明确提示可能已扣费，不自动重发 |
| `content_policy` | 返回提示词输入 |
| `provider_internal` | 关闭并保留 request id |
| `cancel_failed` | 关闭；说明本地停止失败且远端可能继续/计费 |
| `malformed_response` | 仅在 `retryable=true` 时重试；否则契约要求已改码 `ambiguous_result` |
| `result_count_mismatch` | 仅重试缺失项 |
| `interrupted` | 不弹启动框；在原 Output 重试中断项 |
| `cleanup_failed` | 调整清洗设置后重新清洗并创建新 Output |

禁止显示 Provider raw message、完整响应、Header、密钥、绝对路径或未翻译的 English 技术句子。

## 13. 内置实例重做

### 13.1 唯一示例流程

```text
prompt_preset ─┐
text_prompt ───┼→ ai_generate
reference_set ─┘

[为运行时 Output 预留空位]    pixel_cleanup（初始不连接）
```

默认示例不得包含 `object_list`，也不得预建 source/cleaned Output。`text_prompt` 放一个本地化安全示例；`reference_set` 默认空并标“可选”；`prompt_preset` 使用内置提示词。`pixel_cleanup` 的空输入态明确显示“生成完成后连接 Output，再点击开始清洗”。对象清单只在单独的“批量对象生成”模板演示。不得新增或提交外部 PNG；需要占位图时只能在测试/示例 builder 中程序生成。

运行语义必须与普通项目完全一致：点击生成后 `ai_generate` 动态创建 current Output；用户手动把该 Output 连到 `pixel_cleanup`；点击开始清洗后才动态创建 cleaned Output。不得给示例写专用自动连接或自动清洗代码。

### 13.2 布局算法

禁止继续使用 `150 / 280` 等旧固定偏移。示例 builder 必须在卡片完成有效尺寸计算后布局：

```text
horizontal_gap = 80 world px
vertical_gap   = 80 world px

input column:
  prompt_preset
  text_prompt
  reference_set

generation column:
  ai_generate，垂直中心对齐 input column 的有效包围盒

runtime output reservation:
  ai_generate 右侧保留 default Output 宽 600 和两侧各 80 的空白带
  初始没有节点；第一次生成的 Output 必须落在这条带内

cleanup column:
  pixel_cleanup，与 ai_generate 顶部对齐，x 位于预留带右缘再加 80
```

普通相邻列的 x 必须等于前一列最大有效 right + `80`；同列 y 等于上一卡有效 bottom + `80`。生成与清洗列之间按上述运行时 Output 预留带计算，不能引用旧默认宽高推算。

### 13.3 示例门禁

- 所有卡 effective bounds 两两不相交，独立断言最小间距 `80`。
- 边只进入端口，不穿过无关卡。
- 初始图不存在任何 batch/Output 节点或指向 cleanup 的输入边。
- 用 mock 完成一次生成后，Output 落在预留带且不重叠；再手工连线并完成一次清洗后，cleaned Output 位于 cleanup 右侧且不移动任何既有卡。
- Open Example 后 Fit All；`1280×720` 首屏完整可见，LOD 不低于 25%。
- Open Example 是一次 Undo；Undo 删除整张示例图，Redo 恢复相同位置、参数和连线。
- 不改任何已打开用户项目的坐标。
- 示例名、节点标题、描述和提示全部走 i18n。

## 14. 粘滞平移修复

当前确定根因：

- Space + 左键开始平移后，如果先松 Space、再松左键，释放分支不会清 `_is_panning`。
- Motion 路径不核对 `button_mask`，因此没有按键也会继续移动相机。

实现要求：

- 记录发起平移的按钮 mask，不只记录 Space 当前是否按下。
- 对应左键或中键 release 无条件清除该手势。
- Motion 收到 `button_mask=0` 时先自愈停止，并且本次 motion 不移动相机。
- 窗口/应用失焦、鼠标离开有效窗口、模态弹出和场景退出时取消全部指针手势。
- 文本输入获得焦点时 Space 不启动画布平移。
- 不用 Timer 猜松键，不靠下一次点击修复。

新建 `pixel/tests/unit/test_canvas_navigation_input.gd`，覆盖：

1. 中键按下/移动/释放；
2. Space → 左键 → 左键先释放；
3. Space → 左键 → Space 先释放 → 左键后释放；
4. 平移中 Motion `button_mask=0`；
5. 左/中键平移中应用失焦；
6. 模态弹出前取消；
7. 文本框焦点时按 Space。

## 15. i18n 架构收口

当前确定事实：

- `strings.gd` 仍有约 460 行 English 常量；
- 至少 23 个生产 UI 文件直接访问；
- 现有守护只检查两个 JSON 的 key/占位符一致，不检查源码绕过；
- Provider schema、模板、错误和动态状态仍可能产生裸 English。

最终要求：

- `pixel/ui/shell/strings.gd` 只保留 `text(key, args)` 兼容入口，不保留任何用户可见 English 常量。
- 生产 UI 对 `Strings.UPPERCASE_CONST` 的直接访问为 0。
- Provider/node schema 只用 `label_key / help_key / placeholder_key`。
- Provider 和模型官方专名可原样显示；周围说明、错误和动作必须翻译。
- PFError、run state、项目和 provenance 保存 code+args，不保存已渲染语言。
- 动态状态使用显式静态 key 映射；普通业务代码不允许 `Strings.text(dynamic_key)`。
- 新增唯一动态 schema 访问层 `pixel/services/schema_text_resolver.gd`（class `SchemaTextResolver`）。Provider/node/preset schema 注册时必须调用 `validate_schema(schema)`，逐个验证所有 `*_key` 在 English/简中 catalog 都存在且非空；UI 只调用 `resolve(schema_entry, "label_key"|"help_key"|"placeholder_key", args=[])`，不得自己取 key 再翻译。
- 只有 `schema_text_resolver.gd` 可以调用 `LocalizationService.text(dynamic_key, args)`；它先验证字段名白名单和 catalog，再解析。其他源码仍只能以字面量 key 调用 `Strings.text()`/`LocalizationService.text()`。
- 已挂载主窗口在 `en → zh_CN → en` 切换时不重建场景；菜单、卡片、Provider 设置、错误框、示例、清洗参数和 tooltip 同步刷新。

扩展 i18n 源码守护，拒绝：

1. `Strings.UPPERCASE_CONST`；
2. `text/title/dialog_text/tooltip_text/placeholder_text` 直接赋 English 字面量；
3. schema 的 raw `label/help/description`；
4. `Strings.text()` 非字面量 key；
5. 缺失、空值或占位符顺序不同的 catalog key。

守护必须用结构规则只允许 `schema_text_resolver.gd` 内 `SchemaTextResolver.resolve/validate_schema` 的动态访问，不得按 key 或调用文件逐项加白名单。确有用户数据或官方专名时，代码结构必须让守护能区分数据与 UI 文案。

## 16. 执行卡和不可跨越的顺序

未来只有项目所有者明确授权 Beta 0.7 E 后，才能按下列顺序执行。普通“开始 Beta 0.7 开发”只授权 B7-0 至 B7-8，不授权候选构建。B7-0 只固定契约和测试清单并保持全绿；从 B7-1 开始，每张卡都必须先新增该卡最小失败测试、记录确实红，再实现并清零本卡新增红灯和相关旧红灯，才能进入下一卡。

任何卡新增用户可见文案时，必须在该卡同时加入 English/简中 catalog key、占位符测试和运行时刷新连接；禁止先写临时 English 等 B7-8 再翻译。每卡完成门都运行 catalog 校验。

B7-1 至 B7-8 每卡固定作业顺序：

1. 核对 E worktree/branch/HEAD/dirty，记录并避开所有既有 dirty；
2. 从 B7-0 test manifest 只取本卡测试，新增后先运行定向命令；至少一个新断言必须因尚未实现的目标行为失败，记录测试名和实际失败原因；若意外全绿，先修正测试，不能直接宣称已实现；
3. 只实现本卡范围，禁止把后卡视觉或功能顺手提前；
4. 先跑定向测试直到绿，再跑 catalog 校验、受影响集成测试、静态守护和全量 GUT；
5. 用 `git diff --check`、改动文件清单和 raster 守护核对范围；任何非本卡回归先清零；
6. 记录 red/green 命令、测试数、已知提示和用户可见变化，再进入下一卡。

### B7-0 — 契约与测试清单

目标：把 v2 字段、状态、范围保留项和替代测试先写死，但不把仓库留在红灯。

必须做：

- 修改 §5.2 的全部契约文档；
- 新建 `pixelforge-plan/03-milestones/reports/BETA_0_7_TEST_MANIFEST.md`。逐段扫描 §5 至 §15 的正文、列表、表格、JSON/GDScript shape、状态转换、公式和步骤；“必须/禁止/只允许/固定/不得”只是提示词，不是扫描边界。把每个可独立违反的规范拆成唯一 `B7-REQ-<section>-<nn>`；表格必须包含原文/表格行或公式引用、唯一 owner card、验证类型、测试文件、测试名、预期 red 原因、green 断言和命令。每条规范都必须有记录，不允许因句子没有关键词而遗漏；真实动画手感等只能人工验证的条款仍要有结构/状态自动化证据并标出人工项；
- 在同一文件建立旧测试失效台账：旧测试文件/测试名、对应 §3/§10.7 退役条款、删除或改写方式、同卡替代测试名和 owner card。未入台账的旧测试不得删除或弱化；
- 可以建立空的 mock response/fixture 目录和纯数据 fixture，但不得新增会失败、skip 或 xfail 的可执行测试；
- 在清单中指定 `test_generation_run_coordinator.gd`，要求 B7-4 新建独立协调器测试，不继续把状态塞进既有大 controller；
- 逐条登记因 3C 被撤销而需要改写的旧测试，记录新条款；不得静默删除；
- 在未改 `pixel/` 前运行一次全量基线；预期为 `396/396 tests、7718 assertions`，并记录既有 orphan/resource 提示。数量、结果或基线 SHA 不一致时停止并退回 P，不能自行重定义基线。

完成门：契约之间无同义字段；§5–§15 requirement ID 无遗漏、无双主责；旧测试失效台账每项有替代测试；现有全量套件保持绿色；没有可执行红测、skip/xfail 或产品实现混入本卡。

### B7-1 — PF-SEC-01 与 HTTP 安全

目标：先关闭密钥和重复下单风险。

主要修改面固定为：

- `pixel/infra/http_client.gd`；
- OpenAI Image 与 RetroDiffusion 两个范围内 Provider；
- `pixel/tests/integration/test_http_client.gd`；
- Provider contract tests。

必须做：

- 先新增凭据 sentinel、Header 大小写/空格和无幂等生成 POST 请求次数测试，运行并确认它们因当前缺陷失败；
- 完成 §8.6 脱敏；
- 生成 POST 自动重试设为 0；
- 删除 RetroDiffusion 的哑元生成“凭据验证”；保存配置网络请求数为 0；
- 为 Retro 安全验证状态和所有新错误同时加入 en/zh_CN key；
- 日志不记录 request/response body；
- 建立可复用凭据 sentinel 扫描器；本卡先接 transport、log、task、PFError 和当时已有持久化表面，raw mock transport 只用于正向“确实发送”断言；
- 安全 GET 与生成 POST 重试策略分开。
- 为 `RetryScheduler` 注入 fake UTC/monotonic clock，本卡测试 HTTP-date 和 30s clamp，禁止真实等待。

完成门：`X-RD-Token` 任意大小写/空格均为 `[REDACTED]`；无原生幂等的生成 POST 在 timeout/network/429/5xx 下 mock server 请求数都为 1。

### B7-2 — 完整 v2 数据竖切、输入简化和预设拆分

目标：一次完成最终 v2 数据模型、持久化、registry、Provider 方法签名和一个明确命名的临时运行适配；卡片结束时仓库可运行、全量测试全绿，但不提前实现后续协调器或最终 UI。

必须做：

- hard cut v2；
- 实现 project/graph/provider/plugin/template/clipboard 版本常量、严格 validator 和 v1 明确拒绝；Provider v1 必须在注册前返回 `unsupported_provider_api_version`，Plugin v1 返回 `unsupported_plugin_api_version`；测试断言没有 adapter/alias 且 UI/服务都不可见；
- 保留并收紧 `object_list.rows`；
- 删除 `size_spec` 和兼容代码；
- 实现 `prompt_preset`；
- `target_width/target_height` 进入 `ai_generate`，reference 主路径改为有序 `asset_list`；
- 建立 CleanupPreset registry 和完整 settings snapshot；
- 在本卡建立 `SchemaTextResolver`、schema 注册校验、Provider/node/preset 所需的双语 schema keys 和动态访问结构守护；后续卡只能消费这一入口；
- 新增 PFProviderTaskV2/PFCancelTaskV2 wrappers；把 OpenAI Image 与 RetroDiffusion 改到 PFProvider API v2：接受新 request、返回新 result/error/progress 结构；本卡不得保留 v1 Provider 调用；
- 新增唯一 `get_visible_asset_ids(batch_params)` 投影，严格返回 `status=succeeded && detached=false` 的有序 asset ids；B7-5 前旧 Output UI 和所有下游都暂时只读这个投影，B7-5 再替换视觉，不得另存 `asset_ids`；
- 只允许一个临时 `legacy_generation_v2_adapter.gd`：沿用旧控制器的单次终态调用，把最终成功/失败转换为最终 `result_slots`，供旧 UI 和回归测试过渡。它不得创建 pending Output、分片、取消、计费或实现新状态机；文件头必须标记“B7-4 删除”，静态测试断言临时适配器恰好一个；
- 建立可运行的最小 v2 壳：prompt/generate 卡只读写新 params，cleanup 卡只保存完整 settings、绝不执行，旧 batch UI 只读 slots 投影；
- 更新 registry、模板、clipboard、project roundtrip、fixture；
- 把 B7-1 sentinel 扫描器接入 v2 project、generation/cleanup provenance 和 clipboard；
- 把所有内置 plugin manifests、插件模板、PluginService/PFPluginAPI 更新为 v2；注册面用 `register_prompt_preset/register_cleanup_preset` 替换 `register_style_preset`，其余注册能力原样保留；
- 删除旧 StylePreset 在 Graph 生成/清洗链中的消费。既有编辑器、地图、抠图、切片、描边和其他独立模块继续使用其模块内当前默认值，本卡不得删除或重构。

完成门：项目/Graph/Provider/Plugin/模板/剪贴板 v2 往返；OpenAI Image 与 RetroDiffusion 的 mock 单次终态流程只经该临时 adapter 可运行；v1 明确拒绝；Graph 主路径出现任何旧节点/端口即验证失败；旧 UI 只读 slot 投影；不存在第二个临时链；全量套件绿色。

### B7-3 — Provider、费用、幂等和结果计数

目标：只完成纯后端 request planner、Provider 调用语义和审计；本卡不创建/布局 Output，不绑定卡片或连线 UI。

必须做：

- 完成 PFProvider API v2 的纯后端行为；
- run/request/attempt 身份；
- 结构化 progress/error；
- 生成前 capability 校验；
- 分片与 slot 映射；
- 少返回、多返回、损坏响应；
- CostService `record_once`；
- OpenAI Image 与 RetroDiffusion 只用 mock HTTP 和录制响应验证；覆盖提交、等待、进度、成功、Partial、结构化失败、取消、超时和人工重试，不调用真实付费 API；
- 完成 PFProviderService 唯一配置入口、旧对话框重定向、五状态、凭据删除清内存以及 descriptor/schema validation；
- 输出纯领域事件给临时 adapter；禁止在本卡创建 pending card、edge animation 或最终 GenerationRunCoordinator。

完成门：estimate/actual/unknown 分开；同 request 重复回调不重复计费；失败分片重试不增加成功分片请求数；Provider 设置只有一条数据路径；没有新增 UI/Output 所有权。

### B7-4 — 统一运行协调、生成卡、连线反馈和错误框

目标：用户从点击到终态只看到一套真实状态。

必须新增独立 `pixel/services/generation_run_coordinator.gd`；名称虽然保留 generation，但它是 Beta 0.7 生成与清洗共用的唯一 run/slot/Output writer。B7-4 先完成 generation 路径并预留 typed cleanup operation 入口；卡片、Provider adapter、cleanup worker 和 edge renderer 都只订阅它，禁止继续把状态机塞回既有 controller。

必须做：

- Queued/Running/Canceling/Complete/Partial/Failed/Canceled；
- pending Output 原子创建；
- 生成卡六组 UI；
- 不确定进度；
- 仅重试失败 slot；
- §11 连线状态机；
- §12 每 run 一个错误框；
- 在本卡加入生成状态、进度、费用、错误框和 Provider 设置动作的全部 en/zh_CN key；
- 成功结果在失败/取消后仍保留。
- 把 sentinel 扫描器接入协调器可见状态和错误框技术详情；
- 本卡第一步删除 `legacy_generation_v2_adapter.gd` 和旧运行入口；最终协调器是唯一 run/slot/Output 原子事务写入者，静态测试拒绝旧入口复活。

完成门：信号顺序测试、并发 run 隔离、取消竞态、Partial、错误框和 idle 停 tick 全绿。

### B7-5 — Output 完全替换

目标：只消费 B7-4 已稳定的 slots/history domain，删除旧 Review，交付最终渲染、滚动、选择、拆出和命令交互；不得重写 Provider、planner、协调器或 slot 状态机。

必须至少按以下职责拆分，文件名固定以便静态守护：

- `output_card_controller.gd`：只做 Output UI 协调；
- `output_layout_calculator.gd`：只做纯几何计算；
- `output_slot_grid.gd`：只做 slot 网格、滚动和命中；
- `output_selection_toolbar.gd`：只做选择与浮动工具条；
- `detach_output_asset_command.gd`：只做单张/全部拆出原子命令与 Undo。

禁止继续把所有职责堆入已经很大的 `canvas_batch_card.gd`。

必须做：

- §10 全部 UI、几何和滚动；
- stable slots；
- 新 Output/历史 Output；
- 单张拆出和拆出全部；
- Preview/Edit/Download；
- 删除 §10.7 的全部旧行为；
- project/clipboard/template/Undo roundtrip；
- 同项目 Output 复制、跨项目拒绝和来源节点删除/Undo。
- 在本卡加入 Output 状态、空态、滚动、拆出、下载和历史标记的全部 en/zh_CN key。

完成门：`0/1/2/4/5/12/13/50` × `360/600/960` 布局、滚动命中、拆出、Undo、保存重开全绿。

### B7-6 — 独立 pixel_cleanup

目标：把临时检查器动作变成可见、可复现、必须显式开始的节点。

必须做：

- 实现 `get_execution_policy()`；
- 清洗卡展示预设和全部现有参数；
- Footer 唯一“开始清洗”按钮；
- 点击快照、严格顺序、单并发；
- 接受且只接受 §6.6 的 batch/image_input/reference_set 三类直接来源；batch 保存 batch/slot，image/reference 两项固定为空但保留来源 node/asset，直接 ai_generate 在 Output 前本地拒绝；
- 扩展 B7-4 的同一个 `GenerationRunCoordinator` 以调度本地 cleanup operations、写 slots/records/progress/Output；禁止新增第二个 cleanup coordinator、第二套 run state 或任何绕过该 writer 的 pipeline 回调；
- cleanup adapter 必须用 PFCancelTaskV2 实现 5 秒 settle、重复取消去重和“operation canceled 后 wrapper resolved”的固定顺序；不得直接依赖共享 PFTask.cancel() 的 void 返回值推断停止成功；
- 每次新 Output；
- 单项失败继续、Partial、取消；
- provenance 完整 settings/report；
- 移除检查器/批次直接清洗，同时保留既有独立抠图、切片、描边工具与测试。
- 在本卡加入清洗分组、参数、报告、运行/取消和错误的全部 en/zh_CN key。

完成门：普通 Graph Run 不执行清洗；每次点击新建输出；源与旧输出字节/引用不变；中断重开可重试。

### B7-7 — 内置实例和粘滞平移

目标：示例不再拥挤，画布不会无按键粘住。

必须做：

- §13 example builder 和 Undo；
- §14 input gesture state；
- 不改用户项目；
- 不引入外部图片。
- 在本卡加入示例标题、填写说明和清洗连接提示的全部 en/zh_CN key。

完成门：所有有效边界不相交；导航输入矩阵全绿。

### B7-8 — i18n 收口

目标：清算历史绕过并验证此前各卡已经使用的统一 key 驱动架构；本卡不得承担前卡新 UI 的首次翻译。

必须做：

- 迁移所有生产 UI 旧常量；
- Provider/node schema key 化；
- 错误、状态、示例和清洗参数 key 化；
- 加强 catalog 与源码守护；
- 运行时语言切换和 18 组几何矩阵。

完成门：直接常量访问为 0；源码守护无白名单；全 UI 两次切换后文字和几何正确。

### B7-9 — 总回归、固定证据、唯一候选和交接

前提：项目所有者在 B7-0 至 B7-8 完成后，另行给出明确包含“构建 Beta 0.7 候选”或“执行 B7-9”的授权。普通“开始 Beta 0.7 开发”、B7-0 至 B7-8 的工程授权或单项人工复验都不能推导出此权限；没有该授权时 E 必须停在 B7-8，报告工程状态并等待。

必须做：

- 本卡负责新建并维护 §18 的 `pixel/scripts/verify_beta_0_7.sh`、§19 的 deterministic screenshot harness 与 manifest generator；前卡只负责各自定向/全量测试，不得假定这些 B7-9 产物已经存在；
- 只在 B7-9 把 `pixel/core/util/app_info.gd` 的单点版本改为 `0.7.0-beta.1`，不得在组件或文件名之外再造版本常量；
- 运行唯一验证脚本；由该脚本生成固定截图和 manifest，只作结构证据，并逐项核对 manifest；
- 把凭据 sentinel 扫描器最后接入截图 manifest；manifest 出现 sentinel 立即失败且不得构建；
- 所有门绿后只在已忽略的 `scratch/candidates/beta0-7/` 构建唯一 `PixelForge-0.7.0-beta.1-macOS.zip`；
- 写工程报告和项目所有者人工清单；
- 记录 SHA-256；
- 不 merge、不 push、不发布。

完成门：只能写“工程通过”；等待项目所有者统一人工测试。

## 17. 自动化矩阵

### 17.1 安全与 HTTP

- `X-RD-Token` 任意大小写/空格；
- Cookie/Authorization/API key/token/secret；
- raw mock transport 收到凭据 sentinel；日志、task 可见字段、error、project、provenance、截图 manifest 全部收不到；
- 无幂等生成 POST 在 timeout/network/429/5xx 只有一次请求；
- Retro 保存配置/打开设置不发送生成 POST；首次真实生成只来自用户点击；
- 安全 GET 的 `Retry-After` 整数秒/HTTP-date、`0.25..30s` clamp、缺省 `0.5/1.0s` 和总 attempts=3；
- error detail 白名单。

### 17.2 Provider 与协调器

- Queued → Running → 终态；
- Running → Canceling → Canceled；
- Canceling 本地停止失败 → Failed；
- 重复取消；
- 不确定/确定进度；
- requested 4 / received 4 = Complete；
- 4 / 2 = Partial，保留 2 张和 2 个失败槽；
- 4 / 0 = Failed；
- 取消保留成功项；
- 两分片一成一败；
- `[4,1]` 只重试后一片；
- 每 run 一个错误框；
- §8.4 全部固定错误码的双语映射与确定动作；
- 成功素材不被失败覆盖；
- 并发 run 不串状态和连线；
- PFProviderTaskV2 的 progress 后恰好一个 completed/failed/canceled 终态；PFCancelTaskV2 恰好一个 resolved/rejected 终态、重复 cancel 返回同一 wrapper、PFCancelResult 四字段及 billing_update null/known 两支、5 秒 fake-clock settle；取消成功固定 generation canceled→cancel resolved，5 秒停止失败固定 generation failed(cancel_failed)→cancel rejected(同一 error)。两者终态后迟到业务信号忽略，且 Provider 不可写 Graph/Output/AssetRegistry；
- generate 调用栈内无信号/网络，返回后可先订阅；Provider task 排队时无 progress/attempt=0；出队后首个网络动作前恰好一次 submitting 使 queued→running/attempt=1；重复 submitting 不加 attempt，首个 HTTP 立即失败仍为 1；
- request 级 progress 与固定分母 run 聚合：active 全确定/一项不确定/分片依次完成/cleanup 不确定，completed_items 在所有终态达到 total 且 ratio 不倒退；
- target 与 provider output size 分离；native/non-native 选尺寸和技术后缀；
- reference asset id/SHA/ref_images 同序；缺失/损坏引用请求数 0；
- seed capability true/false；42 起 `[4,1]` 的第二片 seed=46；非连续失败 42/44 拆成两个 retry request；2147483647→0 强制断片；随机 seed 失败逐 slot 重试；actual seed 有值/null provenance；
- 新建 ai_generate 的 descriptor defaults；OpenAI↔Retro 和同 Provider model 切换在单一 Undo 内整体重建 extra、保留尺寸/数量/seed；旧 quality/remove_bg/strength 不串到新 model，缺 key/未知 key/错误类型本地拒绝；conditional param 保存但只在 mode 命中时发送；
- OpenAI 与 Retro 各 Provider 恰好一个 main default；四个云 model 的 capabilities、provider_meta_keys 与 cost_estimate flag 均符合 §8.8；`extra` 未声明 key 本地拒绝；999 结果上限在预算/Output/网络前拒绝；
- normalized items 的连续 index、单项 decode error、实际尺寸不等于 provider_output_size、少返回、额外成功、额外失败和 actual_seed；尺寸不符变 ambiguous_result 且不缩放，额外失败不创建 slot，额外成功 snapshot/provenance 完整；
- request record 的 provider_id/provider_meta 白名单、succeeded/partial/failed 聚合和 received_count 可大于 requested_count；
- 已接受生成 POST 的坏 shape → ambiguous_result 且无自动 retry；只有明确未接受/未计费 fixture → malformed_response/retryable。
- PFError 除 provider_code 外的固定键全部必填、null/空 provider_id 规则、provider_code 唯一可省略、未知键拒绝；PFValidationIssue/PFLoadError/PFCommandError 不被误塞 attempts/message；
- cancel 的 5 秒 fake clock 只约束本地停止、独立 3 秒 fake clock 约束远端确认：本地未停才 rejected；本地已停而远端无能力/失败/3 秒超时均 resolved false；queued 未提交项 resolved true 且不调用 Provider；cancel_failed 必须把相关 slot/record 终态化，不能残留 busy；
- 最新 retry run 一成一败时按全部当前槽聚合 Output；最新 run 有 canceled 时显示 Canceled，cancel_failed 优先 Failed；cutoff 后图片不落地，已在本地停止前到达的规范费用只经 PFCancelResult.billing_update record_once，wrapper 终态后所有回调忽略；
- `get_config_schema` 只接受 string/password/bool/enum 的精确 shape；两个范围内 Provider schema 逐字段相等，旧 text/raw label/未知字段注册失败，password 不从 CredentialStore 回填；

### 17.3 费用

- estimate/actual/unknown；
- unknown 不显示 `$0`；
- record_once 去重；
- Partial 费用一次；
- 多 request run 按 request/charge 分别 `record_once`，十进制求和；
- Failed 无 actual 不计；
- 预算取消请求数 0；
- 单项 Retry、失败项批量 Retry、完整重新生成三条人工路径都重新 preflight，blocked/取消确认时 slot 与请求数不变。
- `cost_estimate=false → null`、`rd_pro batch=1/2 → 0.250000/0.500000`、声明 true 却 null/float/负数/非法字符串 → blocked；
- 多 request 十进制求和、任一 null 使整次 unknown、budget=0、刚好等于阈值、跨越阈值 needs_confirmation、confirm/cancel、provider/model 缺失和 int64 overflow 的完整 `reason_code`/null 字段 shape；
- OpenAI/Retro 四个云 model 的 estimate flag；unknown 不进入月累计。

### 17.4 Output

对 slot 数 `0/1/2/4/5/12/13/50`、宽度 `360/600/960`：

- columns 不超过 4；
- 可见行不超过 3；
- `n` 包含所有 detached=false 状态、排除 detached=true；overlay scrollbar 不改变 tile 宽；
- 单图横/竖/方图按精确公式得到 `176..420` 视口；
- queued/running/failed/canceled 单图都使用 slot.planned_size；generation、cleanup resample 开/关和 clipboard 的 planned_size 来源逐一断言；
- `n=0` 只覆盖真正无 slot 和全部成功已 detached 两种原因；只要有 failed/canceled 就渲染 tile；
- 13/50 内部滚动；
- 卡片不按总结果无限增高；
- 端口/线端点同帧更新；
- 滚动后命中正确；
- 乱序返回、少返回、多返回；
- 单项 Retry；
- Retry 除 retryable/wait 外还要求 current/history、来源节点仍存在且类型相同、snapshot 有效；删除来源形成的 standalone 与剪贴板纯素材 Output 在卡片 Footer、slot 和菜单三处都不显示 Retry；
- 滚动位置不被回填重置；
- 拆出单张、第四行、最后一张、全部、Esc、pointer cancel；
- Undo/Redo、保存重开、origin；
- 新完整运行不覆盖旧 Output；
- 终态 Output 同项目复制只含成功可见槽、跨项目拒绝；
- 粘贴纯素材 Output 严格清空 snapshots/records/run/source/unexpected 并使用真实 planned_size；
- manifest project id 的 New/Save/Save As 和 clipboard origin_project_id；
- crash reopen 的 queued/running slot 与 stale record 原子恢复；全成功补 succeeded、成功+失败补 partial、全失败补 failed；mid-cancel 已有 canceled slot 但 remote=null 时补 canceled/remote=false 并聚合 Canceled，cancel_failed 仍优先 Failed；
- 来源节点忙时拒绝删除，终态删除变 standalone，Undo 恢复 role/边。
- busy Output 禁止拆出、拆出全部、编辑、复制、删除和普通 Undo；仅允许选择/预览/下载已成功槽；终态后恢复动作；
- failed 槽只在 `retryable=true` 且等待结束时出现单项 Retry；auth/quota、invalid input、content policy、timeout/ambiguous、provider internal、cancel failed、cleanup failed 分别命中 §8.5 固定按钮或无重试动作；
- 拆出/复制/Undo/保存重开都保持 `origin_graph_id/origin_batch_node_id/origin_slot_id` 完整三元组；全部成功图已拆出且至少一张对应 sprite 存在时唯一动作是“在画布中定位”且不改 detached；全部对应 sprite 都已删除时唯一动作是“恢复到 Output”，原子把相关 slots 的 detached 改回 false、网格重新出现并聚焦第一张恢复 tile，不得执行定位或停在空态；
- input snapshot 与 asset provenance 的 reference asset/hash 往返；history scanner 保留这些引用，清 orphan 不得删除仍被失败 Retry 或审计使用的参考素材。

### 17.5 清洗

- 普通 Run 停在 Ready；
- 点击后严格输入顺序和单并发；
- 单项失败继续；
- Partial/Failed/Canceled；
- 每次新 Output；
- 源 asset 和旧 Output 不变；
- preset 复制、编辑后 preset_id 清空；
- 六个内置预设逐字段快照；HD-2D 量化禁用；base_size 进入 detector；
- Auto/Manual、resample enabled、quantize mode/dither 的控件启用矩阵；参数变化不运行 pipeline；
- 0 个输入、1000 个输入均在创建 Output 前拒绝；
- 完整 settings 进入项目/模板/clipboard/provenance；
- generated target 逐素材进入 effective target；cleaned→cleanup 链继续继承 effective target；非 generated 使用 `[0,0]`；resample disabled 不按 target 改尺寸；
- fixed palette 在点击时冻结有序 RGBA/hash，运行时删除 registry palette 也不 fallback；interrupted Retry 使用 snapshot 后输出字节一致；新完整运行缺 palette 在 Output 前拒绝；
- 完整 cleanup report 含 input/output/effective target/grid/steps/color counts/elapsed，asset wrapper 与 parent/history 引用往返；
- 每 input 一个本地 operation record 且永不 partial，run 聚合才允许 Partial；
- running 重开变 interrupted。
- cleanup Footer 覆盖 Queued/Running 取消、Canceling 禁用、可重试 interrupted 原 Output“仅重试中断项”、其他终态新建 Output；中断重试不读取当前设置或重跑成功项；
- batch/image_input/reference_set 三类合法来源分别保存正确 `input_source_kind/input_source_node_id/source_asset_id`；只有 batch 写 batch/slot，另外两类同时留空；直接 ai_generate 来源在 Output/worker 前拒绝；
- 同一协调器同时覆盖 generation 与 cleanup typed operation，但同一时刻只运行一项 cleanup；取消顺序为 worker 停止、operation PFTask canceled、PFCancelTaskV2 resolved，5 秒用 fake clock；
- palette save/insert 缺失或 hash 不匹配均按契约拒绝；snapshot palette 在 registry 后续删除/修改时仍确定复现。

### 17.6 示例与画布输入

- 默认示例不含 `object_list`，以 `text_prompt` 为默认内容入口，同时保留可选 `prompt_preset/reference_set`；无预建 Output、cleanup 未连接，mock 运行后的 Output 进入预留带；
- 示例 effective bounds、80 间距、边路由、Fit All、Undo/Redo；
- 中键；
- 两种 Space/左键释放顺序；
- `button_mask=0`；
- 失焦；
- 模态弹窗；
- 文本框 Space。

### 17.7 i18n 和几何

运行时 `en → zh_CN → en`，覆盖主窗口、菜单、生成卡、Output、Provider 设置、错误框、示例、清洗卡和 tooltip。

固定 18 组：

```text
locale: en / zh_CN
window: 1080×560 / 1280×720 / 1440×900
ui_scale: 1.0 / 1.25 / 1.5
```

断言无文字重叠、底部截断、关键入口丢失、卡内容越界和端口错位。

另做结构守护：所有 schema 注册必须通过 `SchemaTextResolver.validate_schema`；只有 `schema_text_resolver.gd` 存在动态 catalog 访问；任一 schema key 在任一语言缺失/空值即失败。

### 17.8 v2 硬切与插件边界

- project/Graph/Provider/Plugin manifest/workflow template/clipboard v1 分别返回各自 `unsupported_*_version`，没有 adapter、alias、部分打开或 UI 可见残留；
- Plugin API v2 删除 `register_style_preset`、新增 prompt/cleanup preset 注册，其余范围内既有注册能力保留；第三方 v1 隔离；
- Plugin v2 不实现签名：可信来源警告继续显示，契约和 UI 不声称已验签，静态扫描不存在伪 signature/verified 字段；
- Graph 主路径旧 size_spec/spec/style 端口拒绝；不存在范围外后端的专用节点、端口、模板或 fixture；
- v2 项目/模板/剪贴板 roundtrip 保持 title/2B size/Output slots/history/snapshots，旧格式拒绝文案双语且不崩溃。

## 18. 唯一总验证脚本

新建 `pixel/scripts/verify_beta_0_7.sh`，顺序固定：

1. lint / format；
2. 全量 GUT，本地 mock HTTP；
3. catalog 校验；
4. i18n 源码守护；
5. UI scaling；
6. 18 组几何；
7. Beta 0.7 固定截图与 manifest；
8. export template；
9. `git diff --check`；
10. raster 守护：合并扫描 `git diff --cached --name-only`、`git diff --name-only 26a6070...HEAD`、`git diff --name-only` 和 `git ls-files --others --exclude-standard`；除仓库既有 `addons/gut` 图标例外外，出现任何新增或修改的 `png/jpg/jpeg` 都失败。

任一步红即停止，不构建候选。只有 B7-0 失效台账中的旧测试可删除/改写，且必须在同卡加入新契约替代测试；每卡结束的可执行测试总数不得低于前卡，B7-8/B7-9 总数不得低于 B7-0 的 396 基线，新契约 requirement 覆盖必须净增加。既有 orphan/resource 提示不得增长。不能删除或改弱与新契约不冲突的旧测试。

## 19. 固定截图

截图和 manifest 统一写入已忽略的 `scratch/beta0-7-evidence/`，工程报告只记录命令、文件名、SHA-256 和结构结论，不提交 raster。脚本截图只证明结构，不证明手感：

1. `1280×720 / en / 1.0`：重排后的内置实例；
2. `1440×900 / zh_CN / 1.0`：生成卡 Ready，宽高和费用可见；
3. `1440×900 / en / 1.0`：Running、pending Output、连线 active 相位；
4. `1440×900 / zh_CN / 1.0`：12 张三行 Output；
5. `1440×900 / en / 1.0`：13/50 张内部滚动；
6. `1440×900 / zh_CN / 1.0`：单图拆出后的独立图片卡；
7. `1440×900 / en / 1.0`：pixel_cleanup 全参数和 Running；
8. `1080×560 / zh_CN / 1.5`：Partial 错误框和仅重试失败项。

headless 连线截图只采一个固定相位；动画速度、流向和手感由项目所有者人工签收。

## 20. 项目所有者最终人工复验

候选存在后只要求一次统一人工测试：

1. 打开内置实例，确认卡不拥挤、连线不穿卡。
2. OpenAI 与 RetroDiffusion 各做一次最小 `batch=1`。
3. 观察 Queued、Running、不确定反馈、连线流向和结果原位回填。
4. 用错误 key 验证 auth 弹窗；断网前提交验证 network。
5. 启动后取消，确认先 Canceling、再 Canceled，且不弹错误框。
6. 查看 Output 三行上限、内部滚动、单图拖出、拆出全部、Undo。
7. 连接 pixel_cleanup，修改一个参数，点击开始，确认顺序执行并生成新 Output，源 Output 不变。
8. 确认 OpenAI 无实际费用时显示“未知”而不是 `$0`；Retro 有实际费用时只累计一次。
9. English/简中各走一次主旅程。
10. 保存重开，确认成功、Partial、拆出标记、清洗 provenance 和历史 Output 不丢。
11. 按 Space/左键的两种释放顺序操作，确认鼠标不再粘住画布。

不要求项目所有者故意制造 rate limit、quota、content policy、partial、timeout 或重复计费；这些由录制契约和 mock 自动化负责，避免真实花费。

## 21. 完成口径

- B7-0 至 B7-8 全绿但未授权/未执行 B7-9：只可写“Beta 0.7 实现卡完成，候选未授权”，不得写整版工程通过。
- 自动化、静态门、固定截图、导出模板和唯一候选全部通过：只可写“Beta 0.7 工程通过”。
- 项目所有者完成 §20 并明确签收：才可写“Beta 0.7 人工通过”。
- merge 到 `main`、push、签名、公证、分发或发布：都需要独立明确授权。
- 单项人工复验成功不能扩大为整版人工通过。
- 候选存在不能写成发布通过。

## 22. 未来 E 的启动和交接

项目所有者以后明确说“开始 Beta 0.7 开发”后，P 才执行：

1. P 对项目所有者批准后的本文件计算 SHA-256，把 hash、批准时间和只读副本写入 ignored `scratch/thread-handoffs/`；聊天内容不能替代该快照。该 hash 只覆盖本执行书，不覆盖会随活动状态更新的 README/CURRENT-STATE；
2. 从 `codex/beta0-6-adaptive-shell-repair@26a6070` 创建新分支 `codex/beta0-7-workflow-output`；
3. 创建 ignored worktree `scratch/worktrees/beta0-7-workflow-output`；
4. 创建全新 E 任务，标题严格为 `PF · E · Beta 0.7 工作流重构`；
5. E 先只读握手，返回 ROLE、WORKTREE、BRANCH、HEAD、WINDOW、批准计划 SHA-256 和待命状态；hash 不一致即停止；
6. 身份确认后再发送本执行书，不复用 Beta 0.6 反馈修复 E；B7-0 的第一个 docs commit 必须把与批准 hash 字节一致的本执行书带入 E 分支，同时由 E 把 README/CURRENT-STATE 从“待审/无 E”更新为真实的活动分支、worktree、task id、批准时间和 B7-0 状态。README/CURRENT 不要求保持规划阶段字节；禁止在首个 commit 前语义改写已批准执行书；
7. E 只按 B7-0 至 B7-8 连续执行并停下报告，不得跳过红灯、merge、push 或发布；
8. 项目所有者另行明确授权候选/B7-9 后，P 才把 B7-9 转交同一 E。没有该授权不得运行候选构建。

每卡交接至少记录：完成提交、修改契约、验证命令/结果、已知失败、下一卡；用通俗语言说明用户体验变化，不能只粘测试数字。

## 23. 禁止清单

- 禁止真实 API 进入自动化或 CI。
- 禁止无服务端幂等证据重试生成 POST。
- 禁止把 timeout 当成“肯定未扣费”后静默重发。
- 禁止按失败 row 重跑已成功分片。
- 禁止把 Partial 写成 Failed 或 Complete。
- 禁止失败/取消覆盖已成功素材。
- 禁止伪造百分比或 `$0`。
- 禁止日志和弹窗保存 Header、key、完整响应、用户图片或完整 prompt；项目/provenance 只能按 PROJECT-FORMAT 保存用户自己的 prompt 文本、素材引用和安全快照，禁止保存凭据、Header、完整响应或内嵌外部响应图片字节。
- 禁止 Provider English raw message 直接面向用户。
- 禁止新增 Strings English 常量或 i18n 白名单。
- 禁止为了示例自动移动用户项目。
- 禁止复制 Infinite-Canvas 代码、样式、截图、资产或文案。
- 禁止用 Computer Use 或脚本截图冒充项目所有者人工通过。
- 禁止在当前 P 规划阶段构建候选、stage/commit、merge、push 或发布。
