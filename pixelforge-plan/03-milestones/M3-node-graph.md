# M3 — 节点工作流（功能3a：节点系统 + 画布集成，暂用 Mock 生成）

> 目标：GRAPH-SCHEMA.md 契约的完整实现：图模型、执行器、GraphEdit UI、与无限画布联动。AI 生成节点先用 mock provider 占位，M4 接真。
> 依赖：M0–M2（process 类节点直接包装 M1/M2 算法）。
> 先例依据：Material Maker 证明 GraphEdit 可承载 200+ 节点的生产级工具（RESEARCH-NOTES §1）。

---

## M3-1 图领域模型（pf_graph.gd / pf_node.gd / node_registry.gd）

**目标**：纯逻辑图模型，零 UI 依赖，可 headless 测试。

**技术实现指导**：
- 按 GRAPH-SCHEMA §1/§3 实现：PFGraph（nodes: Dictionary[id→PFNode 实例+params+position], edges: Array）、增删节点/边 API、`can_connect(from_node, from_port, to_node, to_port) -> {ok, reason}`（类型规则 §2 单点实现：含 image→image_list 自动包装标记、环检测——加这条边后 DFS 检环）。
- `node_registry.gd`：`register(type, script)`、`create(type) -> PFNode`、`list_by_category()`。启动时注册内置节点。type 冲突时后注册失败并 error 日志（防插件覆盖内置）。
- 序列化：`to_json/from_json` 严格对齐 schema；未知节点类型 → 幽灵节点对象（GRAPH-SCHEMA §6：保留原始 JSON，is_ghost=true）。
- PFNode 基类 + 参数校验辅助（按 get_param_schema 的 min/max/enum 校验 params，越界回退默认并 warn）。

**验收标准**：
1. 单测覆盖：连接规则全矩阵（7 端口类型两两组合）、环检测、幽灵节点 round-trip 不丢字段。
2. graph JSON round-trip（含 2 个幽灵节点）逐字节语义一致。

---

## M3-2 执行器（executor.gd）

**目标**：GRAPH-SCHEMA §4 执行语义完整实现。

**技术实现指导**：
- Kahn 拓扑排序 → 分层调度（同层无依赖节点并行提交 task_queue，受并发槽限制）。
- **批量 map 展开**：输入是 list 而节点 `handles_list()==false` 时逐项调用——注意 seed 递增语义（ai_generate 每项 seed+1，保证可重现且不同图）。
- 记忆化缓存：`(node_id, hash(params), hash(inputs))`→输出。Image 哈希用降采样 8×8 灰度 + 尺寸 + 参数串拼接 MD5（足够区分，避免全图哈希开销）。缓存上限 1GB LRU。
- `select` 节点的暂停语义：executor 状态机 `running → waiting_interaction → running`；UI 收到信号弹出选择浮层，用户勾选后 resume。超时无限（用户主导）。取消时 pending 节点清理。
- 整图执行包装为单个 PFTask（子进度按节点数加权）；单节点失败默认中断下游、已完成结果保留并可见（部分成功是常态——批量场景）。
- mock provider（`plugins/provider_mock/`）：生成确定性占位图（seed 决定颜色/图案的 base_size 方块），延迟参数模拟网络（0.5–2s），供本里程碑全部测试。

**验收标准**：
1. 单测：菱形依赖图（A→B,C→D）执行顺序合法、B/C 并行（时间戳断言重叠）。
2. 批量：text_list 5 项 × batch 2 → 下游收到 10 图列表，seed 序列确定可重现。
3. 缓存：改一个下游节点参数重跑，上游 ai_generate 不重复执行（mock 计数断言）。
4. 取消：执行中取消，运行中任务收到 cancel、waiting 节点不启动、已出结果保留。

---

## M3-3 GraphEdit 节点编辑器 UI

**目标**：可拖拽搭建工作流的图形界面，嵌入主窗口（画布/图编辑 分栏或 Tab，布局可调）。

**技术实现指导**：
- `graph_editor/` 封装 GraphEdit：右键/Tab 添加节点菜单（registry 按 category 分组+搜索框）；GraphNode 子类按 PFNode 端口声明动态生成 slot（颜色按 §2 表，左入右出）；连接请求回调全部转发 `pf_graph.can_connect`（**UI 不自写规则**），拒绝时 toast 显示 reason。
- 参数面板：选中节点 → 检查器按 `get_param_schema()` 自动渲染（kind→控件映射表：int/float→SpinBox, enum→OptionButton, text_multiline→TextEdit, palette→调色板选择器复用 M1 控件, provider→下拉, seed→SpinBox+骰子按钮）。零自定义 UI 代码加新节点（验收硬指标）。
- 执行控制：工具栏 Run/Cancel/进度条；节点上实时状态角标（排队/运行/完成/失败/缓存命中，GraphNode overlay 图标）；失败节点红框 + tooltip 错误详情。
- 与画布联动：`graph_anchor` 画布元素 ↔ 图（双击 anchor 打开对应图）；`output_to_canvas` 结果在 anchor 右侧网格排布（间距 = base_size，整齐铺开）；`image_input` 节点可"从画布选取"（进入拾取模式点击元素）。
- 图持久化进 .pxproj（graphs/ 目录，M0-4 的 project_service 扩展 entries.graphs）。
- GraphEdit 已知坑（调研）：minimap 默认关（性能）；zoom 限制与画布手感对齐；连线样式默认即可，不深度定制（省工时，v2 美化）。

**验收标准**：
1. 冒烟：编排 PRODUCT.md 用户旅程的 7 节点链（style→size→object_list→ai_generate(mock)→pixel_cleanup→slice→output_to_canvas）全程鼠标操作可完成，Run 后画布出现 mock 素材阵列。
2. 类型不符连线被拒且有提示；删除有连接的节点边一并清理。
3. 图保存重开后布局/参数/连线一致；含幽灵节点的图可显示（灰色）且 Run 被阻断并提示。
4. 新增测试节点（仅声明 schema）不写 UI 代码即获得完整参数面板（评审检查）。

---

## M3-4 内置 process/input/output 节点全集

**目标**：GRAPH-SCHEMA §5 清单中除 ai_generate 真实现外的全部节点落地。

**技术实现指导**：
- process 节点是 M1/M2 算法的薄包装：execute 里调 pipeline/matting/segmenter/outliner/palette，params schema 映射既有参数契约。**不复制算法代码**（lint 检查 import 方向）。
- `select` 节点 UI 浮层：缩略图网格 + 勾选 + 全选/反选，确认后输出子列表。
- `size_spec` 输出 spec dict `{width, height, per_subject}`：宽高从 base_size 派生默认。
- 共 13 个节点（除 ai_generate），每个 ≤ 150 行。

**验收标准**：
1. 每节点至少 1 个执行单测（mock 输入→断言输出）。
2. 端到端：M3-3 验收链的输出素材确实经过清洗（色数≤预设）与切分（多物体 mock 图成多素材）。

---

## M3 整体验收

- mock 全流程用户旅程顺畅（录屏评审）；图执行性能：50 节点图调度开销 < 100ms（不含节点本体耗时）。
- 预估 ~3000 行。GraphEdit 深坑（slot 动态刷新、缩放手感）预留 20% buffer 工时。
