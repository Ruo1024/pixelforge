# PROVIDER-API.md — Provider API v2、安全、状态与结算审计契约

> api_version = 2。Beta 0.7 只迁移 OpenAI Image 与 RetroDiffusion。
> api_version != 2 的 Provider 在注册阶段返回
> unsupported_provider_api_version，不能进入列表、设置或运行服务。
> 禁止 v1 adapter、旧方法别名和按方法存在性猜版本。

## 1. 固定接口与所有权

PFProvider v2 只暴露：

	func get_api_version() -> int
	func get_config_schema() -> Array[Dictionary]
	func get_model_descriptors() -> Array[Dictionary]
	func generate(request: PFGenRequest) -> PFProviderTaskV2
	func cancel(request_id: String) -> PFCancelTaskV2

Provider 只负责远端请求、解码与安全归一化。不得读取或写入 Graph、Output、
AssetRegistry、Undo、费用产品状态、卡片、连线或弹窗。GenerationRunCoordinator
是应用状态的唯一 writer。

现有共享 PFTask 继续服务 HTTP、TaskQueue、cleanup 与其他模块；本契约新增
pf_provider_task_v2.gd 与 pf_cancel_task_v2.gd，不全局改名，也不提供旧信号别名。
普通 UI/Graph 不得直接订阅 Provider task。

Beta 0.7 生产注册范围只有 openai_image 与 retrodiffusion。mock 只能作为自动化
替身；ComfyUI 和其他实验后端保持禁用/不注册，不迁移 v2、不扩建验收。

## 2. 身份与请求

run_id 表示一次用户点击；request_id 表示一个 Provider 分片或 cleanup operation；
attempt 表示同一 request 真正启动一次。生成 POST 没有自动重试，故其 attempts
终态只能是 0 或 1。

PFGenRequest 精确字段：

    {
      run_id, request_id, idempotency_key,
      provider_id, mode, model_id, prompt,
      target_width, target_height,
      provider_output_size,
      batch, seed,
      ref_images,
      extra
    }

mode 只允许 txt2img/img2img；ref_images 为空时固定 txt2img，非空时固定 img2img。
删除 style、negative_prompt、单数 ref_image、mask、旧 width/height。Provider
收到的是协调器已拼好的最终 prompt，不读取 PromptPreset，也不追加业务提示词。

target 是用户选择的固定交付尺寸；provider_output_size 是远端实际接收尺寸。当前
GPT Image 2 主路径由固定 delivery policy 把 12 组交付尺寸映射到 12 组请求尺寸：
720p、1440p、2160p 的尺寸相同，1080p 的三个请求尺寸分别为
1920×1088、1088×1920、1088×1088，协调器只做居中裁切得到对应的
1920×1080、1080×1920、1080×1080 交付尺寸。Provider 不能静默缩放、改变交付档位
或丢参考图。

协调器总生成稳定 idempotency_key 供本地审计。只有 descriptor 同时声明
native_idempotency=true 且契约测试证明实际发送，Provider 才能把它送到远端。
本版 OpenAI/Retro 均为 false。

## 3. 异步 wrapper

PFProviderTaskV2 信号固定为：

    progress(PFProviderProgress)
    completed(PFGenResult)
    failed(PFError)
    canceled(request_id)

generate 必须立即返回 wrapper，网络启动 deferred 到下一 queue turn，使协调器先
连接信号。零到多次 progress 后恰好一个终态；终态后的信号幂等忽略。

PFCancelTaskV2 只允许恰好一次：

    resolved(PFCancelResult)
    rejected(PFError code=cancel_failed)

同一 request 重复 cancel 返回同一 wrapper。Provider 成功取消顺序为：停止本地
回调，generation task 发 canceled，cancel wrapper resolved。cleanup 顺序为：
worker 停止，operation task 发 canceled，cancel wrapper resolved。

本地停止 settle deadline 为 5000ms；无法证明停止时，generation task 先
failed(同一 cancel_failed)，再让 cancel wrapper rejected。已证明本地停止后，
远端确认另有 3000ms deadline；远端无能力、失败或超时均 resolved false，
不能变成 rejected。两种 deadline 均由注入的 monotonic clock/scheduler 驱动，
测试不得真实等待。

PFCancelResult 精确字段：

    {
      request_id,
      local_stopped: true,
      remote_cancel_confirmed: bool,
      billing_update: null | {
        actual_cost_usd,
        charge_id,
        provider_meta
      }
    }

billing_update 只接收取消 cutoff 后、本地停止完成前已经归一化的隐藏结算审计；非 null 时
恰好包含 actual_cost_usd/charge_id/provider_meta，且 actual_cost_usd 非 null；不能含
图片、普通错误或 raw payload。cleanup 与未提交 queued request 固定 null。queued
未提交由协调器直接 resolved
`{request_id,local_stopped:true,remote_cancel_confirmed:true,billing_update:null}` 且不调
Provider；cleanup 成功取消 remote_cancel_confirmed=true。wrapper 终态后所有回调忽略。

## 4. Progress

PFProviderProgress 精确字段：

    {
      phase,
      determinate,
      ratio,
      completed_items,
      total_items
    }

phase 只允许 submitting/provider_processing/downloading/decoding；total_items
等于 request.batch；completed_items 单调 0..batch。determinate=true 时 ratio
为单调 0..1，false 时 ratio 必须 null。Provider 不发 elapsed、materializing
或 cleaning。

wrapper 在本地队列中不发 progress。真正出队后、首个网络动作前恰好发一次
submitting/determinate=false/ratio=null/completed=0；协调器以它把 record
queued 转 running、attempts 0 转 1。重复 submitting 不增加 attempt。

Run 级 PFRunProgress 由协调器生成，可增加 materializing/cleaning 和 elapsed_ms。
多个 request 以固定 slot 总数作分母；只有全部活跃 Provider 都有真实比例且未
materializing 时才显示百分比。否则显示不确定动画与已完成 x/y，绝不伪造 0%。

## 5. 结果归一化

PFGenResult 精确字段：

    {
      request_id,
      items: [
        {index, image, actual_seed, error}
      ],
      actual_cost_usd,
      charge_id,
      provider_meta
    }

items 保持远端顺序；index 必须从 0 连续递增且唯一。成功项恰有 RGBA8 Image、
error=null；失败项 image=null、actual_seed=null、error 为安全 PFError。
actual_seed 只允许 null 或 0..2147483647。禁止过滤坏图后压缩数组。

每张成功图实际尺寸必须等于 request.provider_output_size；不等时不缩放，改为
ambiguous_result(stage=decode,retryable=false)。其他合法项继续保留。

index 小于 requested_count 原位回填预建 slot。少返回的尾槽失败为
result_count_mismatch。额外成功在末尾追加 succeeded/unexpected slot 和独立
安全 snapshot；额外失败不创建 slot，只记安全诊断。received_count 统计全部
成功项，可大于 requested_count。重复/负数/断裂 index 或已接受请求的坏 shape
归一化为 ambiguous_result，不自动重试；只有机器可验证“未接受且不计费”时才可
malformed_response/retryable=true。

actual_cost_usd 为 null 或规范 USD String；它与 charge_id 只作为隐藏结算审计保存，
不得派生估价、预算、月累计、确认框、脚注或其他用户费用 UI。null 是 unknown，不是 0。charge_id
匹配 [A-Za-z0-9._:-]{0,128}。provider_meta 只能含 descriptor 的
provider_meta_keys；内置范围唯一允许 remote_task_id，值匹配
[A-Za-z0-9._:-]{1,128}。未知键使结果校验失败，不能宽松丢弃。raw response
只存在解析函数局部变量。

## 6. PFError 与非执行错误

PFError 只表示已经进入 Queued/Running 后的执行失败，精确字段为：

    code, stage, provider_id, retryable,
    retry_after_seconds, status_code,
    request_id, attempts,
    expected_count, received_count,
    provider_code(唯一可省略)

除 provider_code 外全部字段必填；provider_code 是唯一可省略字段。不适用
provider_id 用 ""；expected_count/received_count 非负。允许 code：

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

stage 只允许 queue/http/provider/decode/materialize/cleanup/cancel。queue attempts=0；
其他 stage attempts=1..3。retry_after_seconds 为 null 或 0..86400；status_code
为 null 或 100..599；provider_code 若存在必须匹配
[A-Za-z0-9._:-]{1,64}。不允许额外键、message、detail、Header、body、prompt、
绝对路径、凭据、图片或 raw response。canceled 是状态，不是错误 code。

运行前输入问题使用 PFValidationIssue {code,field,args}；加载使用 PFLoadError；
剪贴板/删除等命令使用 PFCommandError。它们只保存静态 code 与安全 args，
不伪造 attempts 或已渲染文案。

retryable 与动作唯一按批准计划 §8.5：auth/quota/content_policy/invalid_request/
provider_internal/cancel_failed/cleanup_failed 均不可原槽重试；network 只有可证明未发出
才可；timeout/ambiguous 不可自动/原槽重试；malformed 只有明确未接受且未计费才可；
result_count_mismatch/interrupted 可重试。显示 Retry 还必须 role=current|history、来源
同 id/同类型存在、snapshot 完整且等待结束；standalone 永不 Retry。

## 7. 自动重试与人工重试

生成 POST 网络尝试固定 1 次，自动重试 0 次。timeout、断网、429、5xx 都不得
静默重发。提交结果不确定时返回 ambiguous_result/retryable=false，并明确可能
生成或计费。

只有无副作用凭据验证 GET 可自动尝试最多 3 次。Chat Completions 连通测试 POST
固定只尝试 1 次且不跟随重定向。Retry-After 接受整数秒或
HTTP-date；单次等待 clamp 到 0.25..30.0 秒；缺失时固定 0.5、1.0 秒。使用注入
RetryScheduler 与 fake UTC/monotonic clock，禁止真实 sleep。

人工“仅重试失败项”只收失败/缺失 slots。可合并的 slots 必须同 source row、
snapshot 相同且原顺序连续；当前固定 seed=-1。人工 Retry 与完整重新生成都直接使用
既有安全 snapshot，不经过估价、预算或费用确认。POST 仍然每个 request 恰好一次尝试。

## 8. 分片、固定参数与 seed

先按 object rows 顺序建立逻辑组；无 rows 时单组 count=batch_size。每组按
descriptor.max_batch 从前向后连续切片，不跨 row 合并，并保持 slot 顺序。Graph
参数只允许 provider_id、model_id、resolution_preset、orientation、batch_size、
seed=-1、extra={}；旧宽高、比例锁、quality、用户 seed 和非空 extra 都拒绝。
一次用户运行总结果数为 1..16；5..16 张确认发生在 slot 与网络任务创建之前。

## 9. 隐藏结算审计

Provider 原样归一化其响应中的 actual_cost_usd、charge_id 和允许的 provider_meta，
协调器把它们保存到 request record 作为隐藏审计。该数据不加总、不估算、不设预算、
不触发确认，也不显示在生成卡、设置、Output、状态栏或报告截图中。生产路径不存在
CostService、estimate_cost、费用 ledger 或月度预算设置。

## 10. Provider 配置

唯一数据路径：

    ProviderSettingsDialog -> PFProviderService -> CredentialStore/Provider

删除或重定向旧 OpenAI session/config 入口。插件不得直接读写 SettingsService
或 CredentialStore。secret 只在 CredentialStore；项目、Graph、模板和 provenance
只保存 provider/model id 与非敏感参数。

状态只允许 unconfigured/configured/validating/verified/invalid。保存后是
configured，不伪装 verified。OpenAI safe_validation=true：Images 模式使用安全 GET；
Chat Completions 模式只在用户点击测试时向所填端点发送一次不含图片的轻量 POST，
自动重试和重定向都为 0。验证成功的精确配置可生成。若 Images 模式服务可达但模型列表
返回无法确认，用户测试后保存的精确地址、远端模型、协议与凭据指纹仍可在 configured
状态生成；未测试的 configured 配置不可生成，修改任一字段后必须重新测试。
Retro safe_validation=false：不显示验证按钮，保存/打开设置网络请求数为 0；configured
可由用户明确点击真实生成，首次成功后 verified，鉴权失败后 invalid。删除凭据清除
Provider 内存配置、verified 与无法确认模型的显式许可。

配置 schema kind 只允许 string/password/bool/enum。string/password/bool 必须且
只能含 key/kind/label_key/help_key/required/default；enum 另有 values。key 匹配
[a-z][a-z0-9_]{0,63} 且唯一；password default="" 且不回填已存 secret。全部
label/help key 经 SchemaTextResolver 双语校验。raw label/help/description、
旧 text kind、未知键或错类型使注册失败。

内置配置精确为：

```json
{
	"openai_image":[
	  {"key":"base_url","kind":"string","label_key":"OPENAI_FIELD_BASE_URL","help_key":"OPENAI_FIELD_BASE_URL_HELP","required":true,"default":"https://api.openai.com/v1"},
	  {"key":"api_key","kind":"password","label_key":"OPENAI_FIELD_API_KEY","help_key":"OPENAI_FIELD_API_KEY_HELP","required":true,"default":""},
	  {"key":"remote_model","kind":"string","label_key":"OPENAI_FIELD_REMOTE_MODEL","help_key":"OPENAI_FIELD_REMOTE_MODEL_HELP","required":true,"default":"gpt-image-2"},
	  {"key":"api_mode","kind":"enum","label_key":"OPENAI_FIELD_API_MODE","help_key":"OPENAI_FIELD_API_MODE_HELP","required":true,"default":"images","values":["images","chat_completions"]}
  ],
  "retrodiffusion":[
    {"key":"api_key","kind":"password","label_key":"RETRO_FIELD_API_KEY","help_key":"RETRO_FIELD_API_KEY_HELP","required":true,"default":""},
    {"key":"endpoint","kind":"string","label_key":"RETRO_FIELD_ENDPOINT","help_key":"RETRO_FIELD_ENDPOINT_HELP","required":true,"default":"https://api.retrodiffusion.ai/v1/inferences"}
  ]
}
```

string/password default 必须 String；bool default 必须 bool；enum values 是非空唯一
String 数组且包含 default。enum 除六键外恰好多 values。所有 key 类型和额外键都按
精确 shape 拒绝。

生产 schema 不暴露 generation_url/edit_url/validation_url；测试 URL 仅构造注入。
base_url 可为兼容 API 根地址或完整的 `/chat/completions`、`/images/generations`
端点；完整端点决定实际协议，设置 UI 同步对应 api_mode。根地址按 api_mode 追加路径，
不得按主机名猜测地址或模型。

Graph 与 descriptor 中的 `openai_image/gpt-image-2` 是本地产品能力 id，继续决定固定交付
尺寸、参考图上限和运行快照；远端请求的 `model` 必须使用已保存的 remote_model，生成卡
只显示该已配置值，不得把某个中转站 URL 或远端模型名写死到产品代码。Images 请求发送
model/prompt/n/size；Chat 请求发送 model/messages/temperature/n/size，messages 中的用户
提示词不得被 Provider 隐式追加或改写。两种生成 POST 都只尝试一次。

## 11. Model descriptor

descriptor 必须包含 provider_id、model_id、display_name、is_default、ui_scope、
provider_meta_keys、capabilities 与 dynamic_params。每 Provider 恰一个默认；
ui_scope=main；同 Provider 的 provider_meta_keys 必须为排序唯一相同数组。

capabilities 必须完整定义 txt2img/img2img/max_reference_images/max_batch、
target_size_constraints/provider_output_sizes/native_pixel/native_idempotency、
safe_validation/seed/transparent_bg。

dynamic param 精确含 key/kind/default/required/values/min/max/step/label_key/
help_key/advanced/template_safe；不适用值写 [] 或 null。kind 只允许
bool/int/float/enum/string；条件显示唯一额外 shape 为
visible_when:{mode:"img2img"}。未知 shape 注册失败。

固定 descriptor（`provider_meta_keys=["remote_task_id"]`，ui_scope=main，所有模型
txt2img/img2img=true、native_idempotency=false）：

| provider/model | target | provider sizes | refs/batch | 关键 flags |
|---|---|---|---|---|
| openai_image/gpt-image-2 | GPT Image 2；720..3840 step1；allowed_sizes=下列 12 组交付尺寸 | 下列 12 组请求尺寸 | 4/4 | default=true, native=false, seed=false, transparent=false, safe_validation=true |
| retrodiffusion/rd_plus | Retro Diffusion Plus；16..128 step1；allowed_sizes=[] | [] | 1/4 | default=true, native=true, seed=true, transparent=true, safe_validation=false |
| retrodiffusion/rd_pro | Retro Diffusion Pro；16..256 step1；allowed_sizes=[] | [] | 1/4 | default=false, native=true, seed=true, transparent=true, safe_validation=false |
| retrodiffusion/rd_fast | Retro Diffusion Fast；16..384 step1；allowed_sizes=[] | [] | 1/4 | default=false, native=true, seed=true, transparent=true, safe_validation=false |

target_size_constraints 精确包含 min_width/max_width/width_step/min_height/max_height/
height_step/allowed_sizes；OpenAI 与 Retro step=1。allowed_sizes 非空时
只接受列表正整数 pair；为空时按范围。native=true 必须 provider_output_sizes=[]；
false 必须非空。provider_meta_keys 排序唯一且同 Provider 每 model 完全一致。

OpenAI allowed_sizes（交付尺寸）恰为：

```json
[[1280,720],[720,1280],[720,720],
 [1920,1080],[1080,1920],[1080,1080],
 [2560,1440],[1440,2560],[1440,1440],
 [3840,2160],[2160,3840],[2160,2160]]
```

OpenAI provider_output_sizes（请求尺寸）恰为：

```json
[[1280,720],[720,1280],[720,720],
 [1920,1088],[1088,1920],[1088,1088],
 [2560,1440],[1440,2560],[1440,1440],
 [3840,2160],[2160,3840],[2160,2160]]
```

OpenAI dynamic_params 恰为 `[]`；请求不发送 quality。

三个 Retro model 恰为：

```json
[
 {"key":"remove_bg","kind":"bool","default":true,"required":false,
  "values":[],"min":null,"max":null,"step":null,
  "label_key":"GEN_PARAM_REMOVE_BG","help_key":"GEN_PARAM_REMOVE_BG_HELP",
  "advanced":false,"template_safe":true},
 {"key":"strength","kind":"float","default":0.8,"required":false,
  "values":[],"min":0.0,"max":1.0,"step":0.01,
  "label_key":"GEN_PARAM_STRENGTH","help_key":"GEN_PARAM_STRENGTH_HELP",
  "advanced":false,"template_safe":true,"visible_when":{"mode":"img2img"}}
]
```

dynamic param 每个字段都必填，不适用 values=[]、min/max/step=null；唯一可选额外键
是上述 visible_when。OpenAI background=opaque/output_format=png 是固定 transport
值，不进 extra；Retro seed 只走顶层。

## 12. 日志与敏感数据

Header 名大小写不敏感。明确脱敏 authorization、proxy-authorization、x-api-key、
api-key、x-rd-token、cookie、set-cookie；名称包含 token/secret/credential/api-key
也必须脱敏。

日志只保留允许的 URL scheme/host/path、method、attempt 与安全状态；删除 query，
不记录 request/response body、完整响应、用户 prompt 或图片。Provider meta 只从
显式白名单构造。

自动化用唯一 credential sentinel：raw mock transport 必须收到 sentinel，证明
凭据确实发送；transport 接收缓冲不参加泄漏扫描。日志、task、PFError、项目、
clipboard、provenance、协调器状态、错误框与后续 screenshot manifest 都不得出现。
