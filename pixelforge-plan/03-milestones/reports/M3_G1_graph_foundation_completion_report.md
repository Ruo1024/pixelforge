# M3 G-1 Graph Foundation 完成报告

> 日期：2026-06-17  
> 分支：`codex/m3-g1-graph-foundation`  
> 范围：M3 `G-1 Graph 最小核 + batch 持久化` 的从无到有基础铺垫。  
> 完整代码 diff：`pixelforge-plan/03-milestones/reports/M3_G1_graph_foundation_full_code.diff`

## 本轮实现

- 新增 `core/graph` 最小领域模型：
  - `PFNode`：节点基类、端口声明、参数 schema 校验、ghost 节点保留。
  - `PFGraph`：graph JSON 往返、节点/边容器、端口类型连接规则、`image -> image_list` 自动包装标记、环检测。
  - `PFNodeRegistry`：内置节点注册、按类别枚举、重复 type 拒绝。
  - `PFBatchNode`：M3 正式 `batch` 节点骨架，持久化 `asset_ids`，声明 canvas action id / label_key / core_op。
- 项目格式读写骨架接入：
  - `PFProject` 增加 `graphs` 内存字段。
  - `ProjectService` 保存/打开 `.pxproj` 时读写 `graphs/{graph_id}.json`，维护 `manifest.entries.graphs`。
  - `canvas` 中 `type=node` 项加载时规范化 `node_id / graph_id / collapsed`。
- 测试与门控：
  - 新增 graph 单测覆盖 registry 冲突、7 类端口矩阵、环检测、batch asset_ids round-trip、ghost 节点字段保留。
  - 扩展 project round-trip 集成测试，验证 `graphs/graph_main.json` 进入 zip 并重开恢复。
  - 新增 `pixel/scripts/verify_m3_g1.sh` 作为本卡本地出口脚本。

## 修改文件

- `pixel/core/graph/pf_node.gd`
- `pixel/core/graph/pf_graph.gd`
- `pixel/core/graph/node_registry.gd`
- `pixel/core/graph/nodes/batch_node.gd`
- `pixel/services/pf_project.gd`
- `pixel/services/project_service.gd`
- `pixel/ui/shell/strings.gd`
- `pixel/tests/unit/test_graph_model.gd`
- `pixel/tests/integration/test_project_roundtrip.gd`
- `pixel/scripts/verify_m3_g1.sh`
- `pixel/CHANGELOG.md`
- 对应 Godot `.gd.uid` 文件

## 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：122/122 passed。
- `./pixel/scripts/verify_m3_g1.sh`：通过，输出 `verify_m3_g1: ok`。
- staged 图片红线：`git diff --cached --name-only | grep -iE '\.png$|\.jpe?g$'` 无输出。

已知现象：GUT 仍报告既有 orphan/leaked resource 警告，但 run summary 为 all tests passed，且本轮未引入图片资源。

## DoD 核查

| 项 | 状态 | 证据/路径 |
|---|---|---|
| 代码规范 | 通过 | `./pixel/scripts/lint.sh` |
| 自动测试 | 通过 | `./pixel/scripts/run_tests.sh`，122/122 |
| 手动测试 | 不适用 | 本轮为 headless graph/project 基础卡 |
| 契约同步 | 不适用 | 未修改 `02-contracts/`，按现有 M3/GRAPH/PROJECT 契约实现 |
| TODO | 通过 | 未新增 TODO/FIXME/HACK |
| 性能预算 | 不适用 | 本轮不含 executor/渲染性能路径 |
| 跨平台 | 延期登记 | 本轮仅本机 headless；M3 UI 卡再做实机 UX 验收 |
| 出口门控 | 通过 | `./pixel/scripts/verify_m3_g1.sh` |

## 边界与下一步

本轮是 M3 地基，不代表完整节点体验完成。尚未实现画布节点 UI、连线层、mock executor、M2 临时 `batch_card` 自动迁移、完整 process 节点或 batch 菜单新架构。

建议下一张卡进入 `G-2 Mock generate 落 batch` 或先做 `UX-1/UX-3` 的导航与批次审阅地基；如果继续 graph 主线，优先把 `object_list -> size_spec -> ai_generate(mock) -> batch` 的最小链路接到当前 `PFGraph`。
