# PROJECT-FORMAT.md — .pxproj v2 项目文件契约

> `format_version = 2`。Beta 0.7 一次性硬切：v1 返回
> `unsupported_project_version`，不部分打开、不迁移、不猜字段。

## 1. 容器与身份

`.pxproj` 仍是压缩级别 6 的标准 ZIP：

```text
manifest.json
canvas/canvas.json
graphs/{graph_id}.json
assets/{asset_id}.png
assets/{asset_id}.meta.json
palettes/{palette_id}.json
boards/{board_id}.json
anim/{anim_id}.anim.json
thumbs/
```

`manifest.json` 必须包含：

```json
{
  "format_version": 2,
  "id": "lowercase-uuid-v4",
  "app_version": "current AppInfo version",
  "name": "My Project",
  "created_at": "RFC3339 UTC",
  "modified_at": "RFC3339 UTC",
  "custom_palettes": [],
  "entries": {"canvases":["canvas"],"graphs":[],"boards":[],"asset_count":0}
}
```

New Project 生成新 id；Save 和 Save As 都保持同一 id。项目不保存全局
StylePreset、PromptPreset 或 CleanupPreset；节点保存自己实际使用的完整 snapshot。
自定义 palette 仍由 `custom_palettes` 指向 ZIP 内资源，并在 Graph/素材解析前注册。

## 2. Graph 与 canvas 的唯一职责

Graph 文件必须符合 `GRAPH-SCHEMA.md` 的 `graph_version=2`，保存节点类型、参数、
端口和边。`canvas.json` 只保存 camera 和布局项。graph node 布局字段为：

```json
{
  "id":"canvas-item-id", "type":"node",
  "graph_id":"graph-id", "node_id":"node-id",
  "position":[0,0], "z_index":0,
  "display_title":"optional user text", "size":[360,300],
  "collapsed":false, "locked":false, "frame_id":null
}
```

Output 的 `role/source_node_id/source_run_id/input_snapshots/request_records/result_slots`
只在 Graph 的 `batch.params`，禁止复制到 canvas。canvas 不再读写 `batch_card`、
review/filter/focus/compare 字段或 graph_anchor；v2 遇到这些旧形态必须按版本门在
打开项目前拒绝，不能局部兼容。

`display_title` 是用户文本：换行和 Tab 转空格、trim、最多 80 个 Unicode code
point；空白等于删除。`size` 是世界整数请求尺寸，最大 1600x1200；折叠高度 56
不覆盖请求高度。普通节点、sprite 与 frame 继续使用 Beta 0.6 的标题、缩放、
LOD、锁定、Undo/Redo 和整数命中规则。`prompt_preset` 继承默认 320x280、最小
280x220；删除 `size_spec` 尺寸项。Output 尺寸与内部滚动严格见 §5。

frame 仍保存固定 `id/type/graph_id/title/color/position/size/z_index`，成员唯一由
node.frame_id 表达；不嵌套、不自动吸附、不保存 member_ids。跨 graph 成组拒绝；
坏 frame 引用原文往返并显示结构化警告。boards 与 anim 的 v1 已有字段和校验
原样保留：board layer 只允许 tile/free、blend 只允许 normal/add/multiply；动画
frames 与 durations_ms 等长且非空。

## 3. 素材与来源

素材公共字段 `id/name/tags/size/origin/palette_ref/anim` 保留。生成素材：

```json
{
  "id":"asset-id", "origin":"generated",
  "provenance": {
    "graph_id":"graph-id", "created_at":"RFC3339 UTC",
    "generation_snapshot": {
      "provider_id":"provider-id", "model_id":"model-id", "mode":"txt2img",
      "target_width":32, "target_height":32,
      "provider_output_size":[1024,1024],
      "actual_width":1024, "actual_height":1024,
      "requested_seed":-1, "actual_seed":null,
      "run_id":"run-id", "request_id":"request-id",
      "source_node_id":"generate-id", "source_row_id":"",
      "prompt_preset_id":"preset-id-or-empty", "prompt_prefix":"actual prefix",
      "prompt":"actual final prompt",
      "reference_asset_ids":[], "reference_content_sha256s":[], "extra":{}
    }
  }
}
```

snapshot 从 slot input snapshot 复制安全输入再补实际结果；禁止重新读生成节点。
provider_output_size 是远端请求尺寸，actual 是解码尺寸，target 是真像素目标。
reference id/SHA 必须等长同序；extra 只含 descriptor 允许的规范键。项目可保存
用户自己的 prompt，但日志、错误框和固定截图 manifest 不得保存；项目也不得保存
negative prompt、凭据、Header、完整响应或响应图片字节。

清洗素材：

```json
{
  "id":"cleaned-id", "origin":"cleaned",
  "provenance": {
    "graph_id":"graph-id", "parent_asset":"source-id",
    "cleanup": {
      "source_asset":"source-id", "input_source_kind":"batch",
      "input_source_node_id":"input-id", "source_batch_node_id":"batch-id",
      "source_slot_id":"slot-id", "cleanup_node_id":"cleanup-id",
      "run_id":"run-id", "request_id":"operation-id",
      "preset_id":"cleanup-16bit-db32-or-empty",
      "effective_target_size":[32,32], "settings":{},
      "palette_snapshot":null, "report":{}
    }
  }
}
```

成功记录的 settings/report 禁止为空。settings 是三组完整规范快照；palette_snapshot
是输入快照对象或 null。report 至少含 input_size/output_size/effective_target_size、
detected_grid `{cell_size,offset}`、steps `{detect_grid,resample,quantize}`、
input_color_count/output_color_count/elapsed_ms。source kind 与 batch/slot 条件字段必须
原样复制；失败项不创建素材 provenance。

从 Output 拆出的 sprite 除原字段外必须同时保存：

```json
{"origin_graph_id":"graph-id","origin_batch_node_id":"batch-id","origin_slot_id":"slot-id"}
```

三元组不可部分存在，来源后来删除也不得改写。

## 4. Output 持久化

`batch.params` 固定为：

```json
{
  "label":"", "source_node_id":"source-id", "source_run_id":"run-id",
  "role":"current", "input_snapshots":{}, "request_records":[],
  "result_slots":[]
}
```

不存在 `asset_ids`、`expected_count`、review/filter/focus/compare；槽数就是
result_slots.size，数组顺序就是 UI 顺序，不存第二个 order。label="" 使用本地化
默认，禁止保存裸 English 默认标题。role 只允许 current/history/standalone，同一
source 最多一个 current。current/history 的 source_node_id/source_run_id 非空；
standalone 的 source_node_id 必须空。删除来源形成的审计 standalone 保留旧 run/
records；Clipboard 纯素材 standalone 必须同时清空 run/records/slot run+request。

每个 slot 精确字段如下；非 succeeded 时禁止出现 asset_id，detached 仍是必填 bool
但只能 succeeded 为 true：

```json
{
  "slot_id":"slot-id", "run_id":"run-id", "request_id":"request-id",
  "source_row_id":"", "source_asset_id":"", "input_snapshot_id":"snapshot-id",
  "planned_size":[32,32], "status":"queued",
  "detached":false, "unexpected":false, "error":null
}
```

status 只允许 queued/running/succeeded/failed/canceled。failed 必须有安全 PFError；
其他状态 error=null。unexpected=true 只允许 Provider 多返回追加的 succeeded 槽；
正常预建槽 false。每个非 Clipboard 纯素材 slot 必须引用本 Output 唯一 snapshot。
slot 当前非空 run/request 必须找到唯一 record；旧 records 可继续引用已被重试更新的槽。

planned_size 为两个正整数且创建后不变：generation=实际 provider_output_size；cleanup
在 resample enabled 且 effective target 为正时用 target，否则用来源真实尺寸；
Clipboard=图片真实尺寸。它只稳定非成功 tile；成功图使用实际解码尺寸。

generation snapshot 精确为：

```json
{
  "kind":"generation", "graph_id":"graph-id", "source_node_id":"generate-id",
  "provider_id":"provider-id", "model_id":"model-id", "mode":"txt2img",
  "prompt":"final prompt", "source_row_id":"", "prompt_preset_id":"",
  "prompt_prefix":"", "reference_asset_ids":[], "reference_content_sha256s":[],
  "target_width":32, "target_height":32, "provider_output_size":[1024,1024],
  "requested_seed":-1, "extra":{}
}
```

cleanup snapshot 精确为：

```json
{
  "kind":"cleanup", "graph_id":"graph-id", "source_node_id":"cleanup-id",
  "input_source_kind":"batch", "input_source_node_id":"source-id",
  "source_batch_node_id":"batch-id", "source_slot_id":"slot-id",
  "source_asset_id":"asset-id", "effective_target_size":[32,32],
  "preset_id":"cleanup-16bit-db32-or-empty",
  "settings":{"detect_grid":{},"resample":{},"quantize":{}},
  "palette_snapshot":null
}
```

三个 settings 对象实际必须是 CLEANUP-PRESETS 的完整有效 shape。input_source_kind 只
允许 batch/image_input/reference_set；batch 的 batch/slot 非空且匹配，另外两类两项
同时为空。Retry 只读原 snapshot，不重读节点、提示词、参考图、settings 或 registry。
snapshot 禁止凭据、Header、raw response、Image 字节、私有请求体和渲染文案。

request record 精确字段：

```json
{
  "kind":"provider", "provider_id":"openai_image", "run_id":"run-id",
  "request_id":"request-id", "source_row_id":"", "slot_ids":["slot-id"],
  "requested_count":1, "received_count":1, "attempts":1, "state":"succeeded",
  "actual_cost_usd":null, "charge_id":"", "provider_meta":{},
  "remote_cancel_confirmed":null, "error":null
}
```

kind 只 provider/cleanup；cleanup 的 provider_id=""、meta={}、cost=null、charge=""。
state 只 queued/running/succeeded/partial/failed/canceled；单 cleanup operation 禁止
partial。requested_count 正整数；slot_ids 前 requested_count 项是预期槽，多返回成功
追加 unexpected 槽到尾部。received_count 初始 0、终态为全部成功解码数且可大于请求。
attempts 0..3，真正启动后至少 1。charge/meta/cost/PFError 按 PROVIDER-API 精确校验。
remote_cancel_confirmed 只在 canceled 为 bool。succeeded=预期全成功；partial=预期有成
有败；failed=预期无成功且有失败；partial/failed 有安全汇总 error，其他为 null。

Provider 少返回把尾槽改 result_count_mismatch；多返回成功在末尾建 unexpected 槽、
新 snapshot 和完整 provenance，多返回失败只安全记录不建槽。多返回且全部预期成功仍
Complete，但显示非阻断 mismatch 警告。所有 Output/snapshot/record 数据禁止 body、
prompt 日志副本、Header、raw response、用户图片字节或已渲染语言。

## 5. Output 画布与历史

Output 固定值：default width=600、min=360、max=960、top rail=32、horizontal/
vertical padding=16、tile gap=8、max columns=4、max visible rows=3、tile min=96、
tile max=176、empty height=240。`n` 是全部 detached=false 槽，不区分状态。

`n>=2` 精确公式：

```text
capacity_columns = clamp(floor((width - 2*16 + 8)/(96 + 8)), 1, 4)
desired_columns = clamp(ceil(sqrt(n)), 1, 4)
columns = min(capacity_columns, desired_columns)
tile_size = min(176, floor((width - 2*16 - (columns-1)*8)/columns))
rows = ceil(n/columns)
natural_visible_rows = min(rows, 3)
natural_grid_height = natural_visible_rows*tile_size + max(0,natural_visible_rows-1)*8
natural_card_height = 32 + 2*16 + natural_grid_height
```

默认 width=600 且 n>=10 时必须是 4 列、tile=136、三行网格=424、自然高=488；
13/50 不继续增高。scrollbar 是右缘 overlay，视觉 4px、命中 12px，不占公式宽度。

`n==1`：成功用解码真实宽高，其他状态用 planned_size；
`viewport_h=clamp(round((width-32)*source_h/source_w),176,420)`，natural height=
`32+32+viewport_h`，图片 contain 不裁切。`n==0` 固定 240，只允许 slots=[] 或全部
succeeded 且 detached。仍有 failed/canceled/queued/running 必须显示 tile。

用户缩短高度后同一网格可滚动并露出下一行一部分；放大也不显示第四行；双击 handle
恢复自然尺寸。折叠只显示标题/数量/状态。普通滚轮在网格先滚，边界后交给 canvas；
canvas zoom modifier 优先。回填/失败/Retry 不重置 scroll，新 Output 从顶部开始。
滚动后的点击、双击、drag、hover 与命中必须映射真实 slot id。

32px 顶轨顺序固定为 title、成功/总数、状态（history 另加历史+原终态）、下载、拆出
全部、Graph port；不得放清洗参数。Succeeded 单图工具条顺序固定 Preview/Edit/Detach/
Download；其他状态没有图片工具条。拖出阈值为屏幕累计 8px，同 asset、不复制位图、
完整来源三元组、一条 Undo；Esc/pointer cancel/无效 drop 完整恢复。“拆出全部”只成功
可见槽，在右侧最多 4 列、gap 24、保序，超过 12 先确认，最后一张也允许且 Output
保留。全部已拆出时，有任一来源 sprite 就只“定位”；全被删就只“恢复到 Output”并
一条 Undo；混合时仍定位。

§10.7 的 review/filter/focus/compare/current-previous-split/batch_card/直接清洗和新结果
覆盖旧 Output 必须从实现、持久化、菜单和测试删除。标题/尺寸/Preview/Edit/Download/
Detach/asset_list/provenance/Retry/Undo/保存重开及独立工具入口保留。

每次完整生成或清洗创建新 Output；旧 current 变 history，保留 slots 和下游边，
新 Output 变 current。仅重试失败项复用同一 Output/slot。历史关系是灰色虚线且不进
执行闭包。自动放置只扫描来源卡右侧（间距 80，冲突向下 `card_height+56`），不
移动旧卡。忙状态禁止复制、删除、拆出、打开编辑器和普通 Undo。

拆出命令原子执行 detached false→true、创建 sprite 和来源三元组；Undo 恢复同一
slot/sprite id，Redo 不复制位图。删除 sprite 不反向修改 detached。下游输出、下载
和拆出全部只使用 succeeded && detached=false。

删除终态来源节点时，关联 Outputs 原子改 standalone 并清 source_node_id，保留全部
素材/slots/records；Undo 恢复。忙来源返回 source_node_busy。删除忙 Output 拒绝；
恢复被删 Output 时若来源已有 current，只能恢复为 history，永不产生两个 current。

## 6. Clipboard v2

`PAYLOAD_VERSION=2`，v1 返回 unsupported_clipboard_version。顶层必须保存
origin_project_id，且只允许粘贴到相同 manifest.id；否则 clipboard_project_mismatch。
busy/Canceling 节点返回 clipboard_node_busy。

prompt_preset 复制完整 preset；ai_generate 只复制配置；pixel_cleanup 复制
preset_id/settings，不复制运行或 target；终态 Output 只复制 succeeded 且未 detached
槽。粘贴 Output 必须成为新 standalone batch：清空 source/run/snapshots/records，
槽使用新 slot id、同项目 asset id、实际图片 planned_size、空运行身份、succeeded、
detached=false、unexpected=false、error=null，因此不可 Retry。sprite 同项目复制并
完整保留来源三元组。payload 禁止 task/request/progress/raw detail/Header/response。

## 7. 素材引用完整性

扫描器只识别明确字段，不递归猜 JSON：

- live：sprite.asset_id；image_input.asset_id；reference_set.asset_ids；
  succeeded && detached=false 的 result_slots.asset_id；board/animation 素材；
- history：detached 成功槽 asset_id；generation input snapshot 和 provenance 的
  reference_asset_ids；cleanup input snapshot source_asset_id；provenance parent_asset
  与 cleanup.source_asset；
- Undo 快照中的 Output 素材在该 Undo 项出栈前同样阻止清理。

live 与 history 都进入项目资源清单并阻止字节被当作 orphan。失效引用保留原文并
产生 `{code,path,asset_id,strength}` 警告。只有两类都无引用且无运行占用的素材可删。
palette snapshot 已内嵌 colors/hash，不依赖 palette registry 后续存在。

## 8. 加载恢复、读写与错误

load validator 完成后、UI 观察 Graph 前，以不可 Undo 的原子事务处理全部残留：

1. queued/running slot→failed/interrupted/retryable=true。对应 record attempts=0 时
   stage=queue；provider attempts>0 为 provider；cleanup attempts>0 为 cleanup。复制安全
   provider/request/count，保留其他终态、素材、detached、费用与 meta。
2. 逐个收敛所有 queued/running record。received_count 从 slot_ids 全部成功槽重算并
   包含 unexpected。预期槽优先级：cancel_failed→failed；否则任一 canceled→canceled
   且 remote null→false；否则全成功→succeeded；有成有败→partial；无成有败→failed。
   partial/failed 汇总 error 优先本次 interrupted，否则预期槽首个安全 error。
3. 按 source 最新 source_run_id 重算卡状态：最新 run cancel_failed→Failed；否则任一
   canceled→Canceled；否则按全部当前预期槽（排除 unexpected、包含 detached）聚合
   Complete/Partial/Failed。禁止只信保存前文字或只看 retry 子集。
4. 连线全部 idle；不建 PFTask、不发 HTTP、不跑 worker、不弹启动框。之后只有
   current/history、同 id/同类型来源和完整 snapshot 同时满足时可 Retry；standalone
   或来源缺失只保留审计。

保存仍使用 `.pxproj.tmp` 原子 rename；autosave 默认 3 分钟、保留 5 份。打开按需
加载素材。坏 PNG 不阻止项目打开：保留元数据与已有坏字节，缺失时不伪造空图。
幽灵 node/frame 引用保留原文并警告。错误必须是静态 code+安全 args；v1 的本地化
说明固定表达“预发布格式已不支持，请新建项目”，不得崩溃或显示裸 code。
