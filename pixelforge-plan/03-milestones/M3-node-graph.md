# M3 — 节点工作流（功能3a：画布原生轻节点 + 批次内容节点，暂用 Mock 生成）

> 目标：图模型 + 执行器 + **画布原生轻节点（自绘端口/连线）** + **批次内容节点** + **整批菜单处理**，全部长在 PFInfiniteCanvas 上。AI 生成节点先用 mock provider 占位，M4 接真。
> 依赖：M0–M2（process 类节点直接包装 M1/M2 算法；批次卡复用画布选择/拖拽/undo）。
> 先例依据：节点改为**画布自绘**（统一画布决策，取代独立 GraphEdit 面板——见 04-research/无限画布架构审阅.md 顶部决策更新）；连线交互手感参照 Lorien / GraphEdit，但不复用其 GraphNode 容器。

---

## M3-1 图领域模型（pf_graph.gd / pf_node.gd / node_registry.gd）

**目标**：纯逻辑图模型，零 UI 依赖，可 headless 测试。

**技术实现指导**：
- 按 GRAPH-SCHEMA §1/§3 实现：PFGraph（nodes: Dictionary[id→PFNode 实例+params+position], edges: Array）、增删节点/边 API、`can_connect(from_node, from_port, to_node, to_port) -> {ok, reason}`（类型规则 §2 单点实现：含 image→image_list 自动包装标记、环检测——加这条边后 DFS 检环）。
- PFNode 基类新增 `is_canvas_resident()` / `get_canvas_actions()`（GRAPH-SCHEMA §3）；`batch` 节点物化 `asset_id` 队列，序列化进 graphs（§5a）。
- `node_registry.gd`：`register(type, script)`、`create(type) -> PFNode`、`list_by_category()`（含新类别 `container`）。启动时注册内置节点。type 冲突时后注册失败并 error 日志（防插件覆盖内置）。process 类标记为「扩展」分组（默认折叠）。
- 序列化：`to_json/from_json` 严格对齐 schema；未知节点类型 → 幽灵节点对象（GRAPH-SCHEMA §6：保留原始 JSON，is_ghost=true）。
- PFNode 基类 + 参数校验辅助（按 get_param_schema 的 min/max/enum 校验 params，越界回退默认并 warn）。

**验收标准**：
1. 单测覆盖：连接规则全矩阵（7 端口类型两两组合）、环检测、幽灵节点 round-trip 不丢字段、batch 节点 asset_ids 物化 round-trip。
2. graph JSON round-trip（含 2 个幽灵节点 + 1 个 batch 节点）逐字节语义一致。

---

## M3-2 执行器（executor.gd）

**目标**：GRAPH-SCHEMA §4 执行语义完整实现。

**技术实现指导**：
- Kahn 拓扑排序 → 分层调度（同层无依赖节点并行提交 task_queue，受并发槽限制）。
- **批量 map 展开**：输入是 list 而节点 `handles_list()==false` 时逐项调用——注意 seed 递增语义（ai_generate 每项 seed+1，保证可重现且不同图）。
- **批次落点**：生成/处理结果默认流入 batch 节点（§4.6）；batch 等 `is_canvas_resident()` 节点的物化输出持久保存，重算整图不重生成（除非显式重跑该节点）。
- **菜单处理路径**（§4.7）：批次卡菜单动作对批内图调 core，记 undo + provenance（graph_id 可空），**不**入图、不进拓扑执行。与对应 process 节点共用同一 core 函数。
- 记忆化缓存：`(node_id, hash(params), hash(inputs))`→输出。Image 哈希用降采样 8×8 灰度 + 尺寸 + 参数串拼接 MD5。缓存上限 1GB LRU。
- `select` 节点的暂停语义：executor 状态机 `running → waiting_interaction → running`；UI 收到信号弹出选择浮层，用户勾选后 resume，输出为独立子批次。超时无限（用户主导）。取消时 pending 节点清理。
- 整图执行包装为单个 PFTask（子进度按节点数加权）；单节点失败默认中断下游、已完成结果保留并可见（部分成功是常态——批量场景）。
- mock provider（`plugins/provider_mock/`）：生成确定性占位图（seed 决定颜色/图案的 base_size 方块），延迟参数模拟网络（0.5–2s），供本里程碑全部测试。

**验收标准**：
1. 单测：菱形依赖图（A→B,C→D）执行顺序合法、B/C 并行（时间戳断言重叠）。
2. 批量：text_list 5 项 × batch 2 → 下游 batch 节点收到 10 图列表，seed 序列确定可重现。
3. 缓存：改一个下游节点参数重跑，上游 ai_generate 不重复执行（mock 计数断言）；batch 物化内容不被重算覆盖。
4. 取消：执行中取消，运行中任务收到 cancel、waiting 节点不启动、已出结果保留。

---

## M3-3 画布原生节点与连线层（canvas_node_view / canvas_edge_layer）

**目标**：在 PFInfiniteCanvas 上自绘节点与连线，与参考卡/批次卡同坐标共存、可互连。**不使用** GraphEdit 的 GraphNode。

**技术实现指导**：
- `canvas_node_view`：在画布世界坐标系自绘节点卡，按 PFNode 端口声明画端口点（颜色按 GRAPH-SCHEMA §2，左入右出）；标题/参数摘要随 LOD 切显示详略（GRAPH-SCHEMA §8）。
- `canvas_edge_layer`：连线从 graphs 渲染（不存 canvas.json）；拖端口连线的交互全部转发 `pf_graph.can_connect`（**UI 不自写规则**），拒绝时 toast 显示 reason；删除有连接的节点时边一并清理。
- 添加节点：画布右键/Tab 菜单（registry 按 category 分组 + 搜索框；process 类折叠在「扩展」）。
- 参数面板：选中节点 → 检查器按 `get_param_schema()` 自动渲染（kind→控件映射表：int/float→SpinBox, enum→OptionButton, text_multiline→TextEdit, palette→调色板选择器复用 M1 控件, provider→下拉, seed→SpinBox+骰子按钮）。**零自定义 UI 代码加新节点**（验收硬指标）。
- 执行控制：工具栏 Run/Cancel/进度条；节点上实时状态角标（排队/运行/完成/失败/缓存命中）；失败节点红框 + tooltip 错误详情。
- 联动：`output_to_canvas` / 生成结果 → 落入 batch 节点（M3-5）；`image_input` 节点可"从画布选取"（进入拾取模式点击元素，含参考卡）。
- 持久化：节点逻辑进 graphs/（.pxproj），画布布局进 canvas.json 的 `node` 元素（PROJECT-FORMAT §4，逻辑/视图分离）。
- 已知坑：连线层与画布平移/缩放/框选的输入优先级（端口命中优先于框选）；连线 hit-test 用粗略 bbox + 距离判定，避免逐像素；连线样式默认贝塞尔即可，不深度定制（省工时，v2 美化）。

**验收标准**：
1. 冒烟：在画布上自绘 PRODUCT.md 用户旅程链（style→size→object_list→ai_generate(mock)→batch）全程鼠标操作可完成，Run 后结果落入批次卡阵列。
2. 类型不符连线被拒且有提示；删除有连接的节点边一并清理。
3. 图保存重开后布局/参数/连线一致（graphs ↔ canvas.json 对账）；含幽灵节点的图可显示（灰色）且 Run 被阻断并提示。
4. 新增测试节点（仅声明 schema）不写 UI 代码即获得完整参数面板（评审检查）。
5. 节点与参考卡/批次卡在同一画布共存：平移/缩放/框选互不打架，节点端口可连、卡片可拖。

---

## M3-4 预设工具节点 + 内置 input/output 节点

**目标**：GRAPH-SCHEMA §5 清单中除 ai_generate 真实现、batch（见 M3-5）外的全部节点落地。

**技术实现指导**：
- **预设工具节点**（pixel_cleanup / matting / slice / outline / palette_map）：M1/M2 算法的薄包装，execute 里调 pipeline/matting/segmenter/outliner/palette，params schema 映射既有参数契约。**不复制算法代码**（lint 检查 import 方向）。默认归「扩展」分组——它们是"可复现流水线"路径，日常处理走批次菜单（M3-5）。
- input 节点：`text_prompt` / `object_list` / `size_spec`（输出 spec dict `{width, height, per_subject}`，宽高从 base_size 派生默认）/ `image_input` / `style_preset`。
- output 节点：`output_to_canvas`（落入 batch）/ `output_to_library`（入库得 asset_list）。
- `select` 节点 UI 浮层：缩略图网格 + 勾选 + 全选/反选，确认后输出独立子列表（= 拆小批次）。
- 每个节点 ≤ 150 行。

**验收标准**：
1. 每节点至少 1 个执行单测（mock 输入→断言输出）。
2. 端到端：M3-3 验收链 + 接一个 pixel_cleanup 预设节点，输出素材确实经过清洗（色数≤预设）。
3. 预设工具节点与批次菜单（M3-5）对同一输入调用 core 得到逐像素一致结果（共用函数验证）。

---

## M3-5 批次内容节点 + 整批菜单 + 拆小批次（canvas_batch_card）

**目标**：实现 GRAPH-SCHEMA §5a 的核心新概念——批次卡：装一队图、整批菜单处理、拆小批次、分离单图。

**技术实现指导**：
- `canvas_batch_card`：在画布上渲染为容器卡，内部网格铺该批次的素材缩略（随 LOD 切详略）；持有 graphs 节点的 `asset_ids` 队列。
- 边框菜单（`get_canvas_actions()` 声明）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。每项调 core（与预设工具节点同函数），结果写回批次为新素材版本，记 undo + provenance（origin="edited"/"cleaned"，parent_asset 链，graph_id 空）。
- 拆小批次：卡内勾选子集 → 生成子 batch 卡（引用子集 asset_id），可独立处理（复用 select 子集逻辑）。
- 分离单图：拖某张出卡 → 成为独立 sprite 卡。
- 发送到编辑器：选中批内某图 → 触发跳转 M6 编辑视图 + 共享元素过渡（M6-1）；M6 实装前灰显占位 + tooltip 说明。

**验收标准**：
1. 菜单"整批清洗"对 50 张批次执行可整体撤销（Ctrl+Z 回退全批）；provenance 正确（parent_asset、origin）。
2. 拆小批次得到独立可处理子批次，且原批次不受影响；分离单图后该图脱离批次仍在画布。
3. 批次卡保存重开后队列/位置/折叠态一致（graphs asset_ids + canvas.json node 引用对账）。

---

## M3 整体验收

- mock 全流程用户旅程顺畅（录屏评审）：画布自绘节点链 → Run → 结果落批次卡 → 批次菜单整批清洗 → 拆小批次 → （精修入口跳转，M6 前占位）。
- 图执行性能：50 节点图调度开销 < 100ms（不含节点本体耗时）。
- 精修入口仅"跳转编辑器"（M6 实装前灰显占位 + tooltip）；**M3 不含画布内像素编辑**。
- 预估 ~3000 行。画布自绘连线层（端口命中、连线渲染、与画布交互优先级）较 GraphEdit 路线多 ~30% UI 工时，预留 25% buffer。
