# GRAPH-SCHEMA.md — Graph v2 节点、端口与执行契约

> 版本：graph_version = 2。Beta 0.7 为一次性硬切；v1 返回
> unsupported_graph_version，不迁移、不猜字段、不注册旧节点别名。
>
> 本文件是 Graph 逻辑的唯一事实来源。画布布局只在 PROJECT-FORMAT.md；
> Provider 请求与运行结果结构分别在 PROVIDER-API.md 和 PROJECT-FORMAT.md。

## 1. Graph v2 顶层

Graph 必须且只能以 graph_version=2 打开。节点只保存 id、type 与 params；边保存
from/to 二元组。position、display_title、size 与 collapsed 只在 canvas 布局保存。
未知的第三方 v2 node type 可作为 ghost 原文往返且不能执行。已知 v2 node 的 params
必须按本文件精确白名单 fail closed；未知参数、旧参数、旧端口和旧节点类型均返回
结构化 validation issue，不得静默忽略后继续打开。特别是 items、preset_ref、
per_subject、batch.asset_ids、review_*、focus_*、compare_* 均为非法旧字段。

主生成与清洗旅程只允许以下八类节点：

| type | category | 用途 |
|---|---|---|
| text_prompt | input | 自由提示词 |
| object_list | input | 可选结构化批量对象行 |
| prompt_preset | input | 正向提示词前缀 |
| image_input | input | 单一项目素材 |
| reference_set | input | 有序项目素材集合 |
| ai_generate | generate | 生成请求与 Provider 参数 |
| pixel_cleanup | process | 显式手动像素清洗 |
| batch | container | 用户可见名称“结果”/“Output” |

既有全局抠图、切片、描边、编辑器、地图和调色板能力继续保留，但不是本轮
Graph 主路径节点。matting、slice、outline、palette_map、select、
output_to_canvas、output_to_library 当前均为延期/未实现的 Graph 类型；Beta 0.7
不得借硬切补做，也不得删除对应已存在的全局工具与算法。

size_spec、style_preset 以及 spec/style/text_list/image/image_list 旧端口在 v2
中非法；validator 必须拒绝，不能隐藏后继续读取。

## 2. 唯一端口类型与连接

| 类型 | JSON/运行载荷 | 用途 |
|---|---|---|
| text | String | 自由提示词 |
| prompt_prefix | {prefix, preset_id} | 正向前缀快照 |
| subject_list | Array[{id,text,count}] | 有序批量对象 |
| asset_list | Array[String] | 有序项目素材 id |

固定端口：

    text_prompt.prompt              -> ai_generate.prompt
    object_list.subjects            -> ai_generate.subjects
    prompt_preset.prefix            -> ai_generate.prefix
    image_input.assets              -> ai_generate.references
    reference_set.assets            -> ai_generate.references
    ai_generate.assets              -> batch.in
    batch.assets                    -> pixel_cleanup.assets
    pixel_cleanup.assets            -> batch.in

同一输入最多一条边。image_input.assets 恰好输出一个 asset id；reference_set
按用户顺序输出 0..descriptor.max_reference_images 个 id。其他类型不隐式转换。
ai_generate.assets 只有素材先注册成功后才输出。

pixel_cleanup.assets 只允许一个直接上游，来源仅 batch、image_input、
reference_set。ai_generate 直连返回 cleanup_requires_output_source，要求生成结果
先物化为可见 Output。

## 3. 节点基类

PFNode 的描述、参数、执行和画布能力沿用现有职责，并新增：

    func get_execution_policy() -> String

返回值只允许 automatic 或 manual；默认 automatic。pixel_cleanup 固定 manual。
普通 Graph Run 到达 manual 节点时停止向下执行并标为 Ready，绝不隐式调用管线。

用户可见 schema 只保存 *_key。schema 注册必须经过 SchemaTextResolver；
组件不得保存或解释 raw label/help/description。

## 4. 输入节点

### 4.1 text_prompt

params 只有 text:String；输出 prompt:text。空白在生成预检阶段与 subjects 一起
判断，不由节点偷偷补默认文案。

### 4.2 object_list

params 唯一字段为 rows：

    [{id:String, text:String, count:int, enabled:bool}]

规则：

- id 非空且本节点唯一；
- text 去首尾空白后非空；
- count 为整数 1..999；
- 只输出 enabled=true 的 {id,text,count}，顺序不变；
- 旧 items 无论是否伴随 rows 都验证失败，不读取、不转换；
- 有有效 rows 时，各行 count 是结果数量唯一真相，总和不得超过 999。

它只是可选批量提示词表，不是场景实体、素材、关系或嵌套对象系统。

### 4.3 prompt_preset

无输入；输出 prefix:prompt_prefix；params 只有完整 preset。格式与六个内置值见
PROMPT-PRESETS.md。新节点默认嵌入 prompt-16bit-db32。

旧 style_preset、style 端口、prompt_template、provider_hints 与 negative prompt
均不存在。卡片继续使用 Beta 0.6 的默认 320x280、最小 280x220、最大
1600x1200，并保留标题、尺寸、复制与 Undo。

### 4.4 image_input / reference_set

image_input.params.asset_id 必须是单一 String；reference_set.params.asset_ids
必须是有序 String 数组。执行只解析项目素材，不接受绝对路径。

协调器在网络前把每个 id 解析为 RGBA8 Image 和内容 SHA-256，顺序必须一致。
缺失、损坏或超出模型上限返回字段级 validation issue，网络请求数为 0。
Provider 只接触 ref_images，不接触 Graph asset id。

## 5. ai_generate

输入 prefix/prompt/subjects/references 均可选且每类最多一条；至少有非空 prompt
或一个有效 subject。输出 assets:asset_list。

params 固定为：

    {
      provider_id, model_id,
      target_width, target_height,
      batch_size, seed,
      extra
    }

规则：

- provider_id/model_id 必须显式存在且可解析；不隐藏回退；
- 新节点写入当前默认 provider、其唯一默认 model、seed=-1 与该 descriptor
  全部 dynamic param defaults；
- 切换 provider/model 在一个 Undo 中整体重建 extra，保留 target/batch/seed；
- target_width/height 是正整数真像素目标，按 descriptor target constraints 验证；
- 无 subjects 时 batch_size=1..999；有 subjects 时数量由行 count 总和决定；
- MAX_RESULTS_PER_RUN=999，在预算、Output、队列和网络前拒绝超限；
- seed 只允许 -1 或 0..2147483647，且永远位于顶层；
- extra 必须恰好含当前 model 声明的全部 dynamic keys，无未知/缺失/错类型值；
- visible_when 未命中时规范值仍保存，但请求不发送该字段；
- 修改参数即时写 Graph 并进入 Undo，不提供 Apply。

最终提示词按 prefix、自由 prompt、row.text 顺序跳过空值后用逗号空格连接。
native_pixel=false 时再追加：

    pixel art designed for a {w}x{h} true-pixel target, flat colors, crisp edges

Provider 不得追加隐藏业务提示词。无 subject 时预览唯一完整 prompt；有 subject
时主预览第一行，并以“共 N 行/M 张”展示有序只读列表，不按 count 展开 999 行。

native_pixel=true 时 Provider 请求尺寸等于 target。否则协调器从 descriptor 的
provider_output_sizes 选择比例误差最小项；并列取数组靠前项。误差比较必须使用
64 位整数交叉乘法，不用浮点猜测。生成素材保留 Provider 原始尺寸，不在生成阶段
自动缩到 target。

逻辑 slot 按有效 row 与行内 count 的全局顺序编号。支持 seed 且 seed 非负时：

    requested_seed = (node_seed + logical_index) mod 2147483648

planner 不允许单 request 跨 2147483647 到 0；随机 seed 的失败 slot 逐项重试。
不支持 seed 的模型不显示/不发送 seed，snapshot 写 requested_seed=-1。

## 6. pixel_cleanup

params 为 preset_id 与完整 settings；结构、值域、共享 scale/offset、不变
base_size、palette snapshot 和六个内置默认值见 CLEANUP-PRESETS.md。新节点默认
嵌入 cleanup-16bit-db32。params 与模板不得保存 target_size 或 palette colors。

点击“开始清洗”前一次性验证并快照有序输入、来源字段、完整 settings 与 palette
snapshot。输入数必须为 1..999。batch 只读取 succeeded 且 detached=false 的有序
slots；image/reference 按 id 顺序读取。运行中不再读取边、上游、控件或 registry。

执行严格单并发，按顺序逐张调用现有 pipeline。单项失败继续；成功注册新素材且
绝不覆盖源素材；每次完整点击创建新 Output。全成功 Complete，混合 Partial，
全失败 Failed；取消后不启动下一张，已成功保留，其余 Canceled。

effective_target_size 按输入逐张派生：generated 读取 generation snapshot；
cleaned 继承上一轮 cleanup；其他来源为 [0,0]。只有执行副本把正 target 注入
pipeline resample，永不写回节点。

普通 Graph Run 不执行本节点。只有卡片 Footer 可以开始；参数修改不得运行预览、
创建素材或安排 Timer。

## 7. batch / Output

batch 输入 in:asset_list 可选，输出 assets:asset_list。params 的运行真相为：

    label
    source_node_id
    source_run_id
    role
    input_snapshots
    request_records
    result_slots

role 只允许 current/history/standalone。同一 source_node_id 最多一个 current。
Output 不保存 asset_ids 或 expected_count；成功可见素材由
status=succeeded && detached=false 的 slots 有序投影。label="" 使用本地化默认
标题，不持久化默认 English。

slot 状态只允许 queued/running/succeeded/failed/canceled。slot 顺序就是 UI
顺序；planned_size 创建后不变；只有 succeeded 可出现 asset_id；detached 始终是
必填 boolean，但只有 succeeded 可为 true；
unexpected 只用于 Provider 多返回的追加成功项；failed 必须有安全 PFError。

input_snapshots 与 request_records 的完整 shape、重试、计费、取消、恢复和
provenance 规则见 PROJECT-FORMAT.md 与 PROVIDER-API.md。它们是可复现审计真相，
不得保存凭据、Header、raw response、图片字节或已渲染文案。

## 8. 执行与恢复

GenerationRunCoordinator 是 generation 与 cleanup 共用的唯一 run/slot/Output
writer。Provider、pipeline、卡片和 edge renderer 都不得直接改 Graph/Output/
AssetRegistry。完整运行在网络或 worker 前原子创建新 current Output 与稳定 slots；
失败则完整回滚上一 current role/edge。

新完整运行保留旧 Output，旧 current 改 history；只重试失败项复用原 Output 和
原 snapshot，创建新 run/request id。来源节点删除与 Output 删除/Undo 的完整冲突
规则见 PROJECT-FORMAT.md。

项目加载后，在 UI 观察 Graph 前，以不可 Undo 事务把所有残留 queued/running
slots 和 records 收敛为 interrupted/终态，保留已有成功、费用、provider meta 与
审计；不得恢复网络、worker、流光或启动弹框。

### 8.1 Edge 状态接口

协调器向 edge renderer 只发布
`idle|queued|active|succeeded|partial|failed|canceled` 与所属 run_id/执行闭包；
renderer 禁止根据卡片文字猜状态。GenerationRunCoordinator 和 renderer 都注入 Clock，
生产只读 monotonic time，测试使用 FakeClock；业务代码不得读 wall clock。

queued 只呼吸不前进；Canceling 立即停推进并显示静态 warning，等待 canceled。终态
保持时间固定为 succeeded 800ms、partial 1200ms、failed 1200ms、canceled 400ms，
随后 idle。只动画当前 run 执行闭包；并发 run 的相位/状态隔离；项目不持久化动画；
无 active edge 时停止 tick。10%/25% LOD 只显示移动光点。动画不得改变端点、命中区、
选择、相机或卡片 bounds。idle 静态线 2px；active 在底线上叠外层 8px 青绿色
alpha 0.28 与内层 2.5px 亮青色，dash 14/10px，沿 source→target 以 90 屏幕 px/s
前进；succeeded 整线亮起淡出，partial 单次琥珀脉冲，failed 单次红脉冲，canceled
灰色淡出。renderer 契约测试必须逐值断言。

### 8.2 UI/示例/输入边界引用

ai_generate 与 pixel_cleanup 卡片的尺寸、六组正文、固定 Header/status/Footer、动作
优先级和滚动唯一遵守批准 `BETA-0.7-PLAN.md §9`；错误弹框唯一遵守 §12。默认示例
Graph 与布局唯一遵守 §13，不得建立示例专用自动连接/清洗入口。Canvas pointer gesture
状态机唯一遵守 §14；它不属于 Graph 数据，不得持久化或进入 Undo。

## 9. 版本与错误

- graph_version != 2 返回 PFLoadError unsupported_graph_version；
- 不提供 v1 migration、adapter、alias 或按方法存在性猜版本；
- 未知插件节点仍可作为幽灵保存，但不能绕过 v2 主路径和端口 validator；
- 所有 load/validation/command 错误保存静态 code+安全 args，不保存最终文案；
- 错误文案必须从集中 English/简中 catalog 解析。

所有 node/preset/provider schema 注册必须通过唯一 SchemaTextResolver.validate_schema。
schema 只允许 label_key/help_key/placeholder_key；UI 只调用 resolver.resolve。只有
schema_text_resolver.gd 可动态访问 LocalizationService.text；其他业务代码只允许
字面量 key。run/error 状态使用显式静态 key 映射，数据只保存 code+args。完整源码
守护与运行时 en→zh_CN→en 刷新规则由批准计划 §15 固定。
