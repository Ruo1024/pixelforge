# ARCHITECTURE.md — 总体架构与工程规范

> 每个执行任务前必读。本文件回答：代码放哪、模块怎么分、谁可以依赖谁、怎么写测试。

## 1. 技术选型结论（依据见 04-research/RESEARCH-NOTES.md）

| 决策 | 选择 | 关键理由 |
|---|---|---|
| 引擎 | Godot 4.6.x | Pixelorama（像素编辑器）与 Material Maker（GraphEdit 节点工具）双重先例证明可行；自带 GraphEdit/TileMapLayer/HTTPRequest/WebSocketPeer；MIT 协议可自由商用 |
| 主语言 | GDScript | 开发迭代最快；Pixelorama 全 GDScript 证明可承载同体量工具；性能热点后置优化 |
| 性能逃生舱 | GDExtension (Rust) + Compute Shader | 仅当 GDScript 实测不达标才启用；接口已按可替换设计（见 §7） |
| 测试框架 | GUT 9.x | Godot 社区事实标准，支持 headless CI |
| 节点图 UI | 画布原生自绘（canvas-native） | 统一画布决策（2026-06-16）：节点与参考卡/批次同坐标互连；GraphEdit 仅作交互手感参考，不复用其 GraphNode 容器 |
| 项目文件 | ZIP 容器 + JSON 清单 + PNG 资产 | 人类可检查、git 友好、向前兼容（见 PROJECT-FORMAT.md） |
| AI 接入 | Provider 抽象层 | 云 API / ComfyUI / 本地模型统一接口，先云后本地（见 PROVIDER-API.md） |
| 插件机制 | 运行时加载 PCK/GDScript | EditorPlugin 在导出后不可用，PCK 动态加载是唯一正路（见 PLUGIN-API.md） |

## 2. 顶层架构：四层洋葱

```
┌─────────────────────────────────────────────────┐
│  UI 层 (ui/)            画布、面板、节点图、编辑器视图   │
│    ↓ 只准调用 ↓                                      │
│  应用服务层 (services/)  项目管理、任务队列、撤销栈、素材库 │
│    ↓ 只准调用 ↓                                      │
│  领域核心层 (core/)      像素算法、节点图模型、风格预设    │
│    ↓ 只准调用 ↓                                      │
│  基础设施层 (infra/)     文件IO、HTTP、设置、日志        │
└─────────────────────────────────────────────────┘
        插件 (plugins/) 通过 PluginAPI 单点接入，可触达 core 与 services 的注册表
```

**依赖铁律**：
- 上层可以调用下层，下层**禁止** import 上层。
- `core/` 必须是纯逻辑：**不依赖任何 Node/Control/场景树**，只用 RefCounted/Resource/Image。这保证算法可以 headless 测试、未来可平移到 GDExtension。
- 跨层通信回传用信号（signal）或回调，不允许下层持有上层引用。
- UI 层之间不互相调用，通过 `services/EventBus`（autoload 单例）发事件。

## 3. 目录结构（git 仓库根）

```
pixelforge/
├── project.godot
├── core/                          # 领域核心（纯逻辑，零场景树依赖）
│   ├── pixel/                     # 像素算法库
│   │   ├── grid_detector.gd       #   网格检测（功能1）
│   │   ├── resampler.gd           #   重采样（功能1）
│   │   ├── quantizer.gd           #   颜色量化（功能1）
│   │   ├── palette.gd             #   调色板对象与最近色映射
│   │   ├── ditherer.gd            #   抖动（功能1）
│   │   ├── matting.gd             #   色键抠图（功能2）
│   │   ├── segmenter.gd           #   连通域切分（功能2）
│   │   ├── outliner.gd            #   描边添加/移除（功能2）
│   │   └── pipeline.gd            #   清洗管线编排器
│   ├── graph/                     # 节点图领域模型（功能3，无 UI）
│   │   ├── pf_graph.gd            #   图模型：节点集 + 边集
│   │   ├── pf_node.gd             #   节点基类（参数、端口、execute）
│   │   ├── node_registry.gd       #   节点类型注册表（插件注入点）
│   │   ├── executor.gd            #   拓扑排序执行器（异步、可取消）
│   │   └── nodes/                 #   内置节点实现（每类一个 .gd）
│   ├── style/
│   │   └── style_preset.gd        #   风格预设对象（见 STYLE-PRESETS.md）
│   └── util/
│       ├── app_info.gd            #   应用名/版本单点定义
│       └── image_math.gd          #   公共图像数学
├── services/                      # 应用服务（autoload 或被 UI 持有）
│   ├── project_service.gd         #   项目打开/保存/自动恢复
│   ├── asset_library.gd           #   素材库（标签、搜索、引用计数）
│   ├── task_queue.gd              #   异步任务队列（AI 调用、重活）
│   ├── undo_service.gd            #   全局撤销/重做
│   ├── provider_service.gd        #   AI Provider 注册与凭据管理
│   ├── plugin_service.gd          #   插件发现/加载/沙箱
│   ├── event_bus.gd               #   全局事件总线（autoload）
│   └── settings_service.gd        #   用户设置持久化
├── ui/
│   ├── shell/                     # 主窗口、菜单、停靠布局、主题
│   ├── canvas/                    # 无限画布（统一宿主：参考卡 + 轻节点 + 批次容器）
│   │   ├── infinite_canvas.gd     #   Camera2D 平移缩放 + 元素管理
│   │   ├── canvas_item_sprite.gd  #   画布上的图像元素
│   │   ├── canvas_item_frame.gd   #   编组/画板框
│   │   ├── canvas_node_view.gd    #   画布原生节点渲染（自绘端口，功能3）
│   │   ├── canvas_edge_layer.gd   #   连线层（从 graphs 渲染 + 连线交互）
│   │   └── canvas_batch_card.gd   #   批次内容节点卡（队列网格 + 边框菜单）
│   ├── editor_transition/         # 画布↔编辑器 共享元素过渡（替代旧 graph_editor/）
│   ├── inspector/                 # 右侧参数检查器（清洗参数、节点参数）
│   ├── map_composer/              # 地图拼接画板（功能4）
│   ├── pixel_editor/              # 像素编辑器（功能5a）
│   └── widgets/                   # 通用控件（调色板条、缩放标尺、进度角标）
├── infra/
│   ├── http_client.gd             #   带重试/超时的 HTTP 封装
│   ├── ws_client.gd               #   WebSocket 封装（ComfyUI 用）
│   ├── file_io.gd                 #   ZIP 读写、PNG 编解码、原子写
│   └── logger.gd                  #   分级日志（文件 + 控制台）
├── plugins/                       # 出厂内置插件（与第三方同机制，自食狗粮）
│   ├── provider_retrodiffusion/
│   ├── provider_openai/
│   └── bridge_comfyui/            #   M7
├── assets/                        # 内置静态资源（调色板、预设、图标、主题）
│   └── palettes/                  #   db32.json, pico8.json, ...
├── tests/                         # GUT 测试（镜像 core/ 与 services/ 结构）
│   ├── unit/
│   ├── integration/
│   └── fixtures/                  #   测试用图像样本（伪像素图、白底图……）
└── addons/gut/                    # 测试框架
```

## 4. 关键架构机制

### 4.1 Image 是数据流通货币

整个系统中图像数据统一用 Godot `Image`（RGBA8）传递，渲染时才包装成 `ImageTexture`。core 层算法签名一律 `func apply(src: Image, params: Dictionary) -> Image`（纯函数、不修改入参）。大图优化（tile 化、就地修改）留给后续版本，先保证正确性。

### 4.2 任务队列与异步

所有耗时操作（AI 请求、批量清洗、导出）必须通过 `task_queue.gd` 执行：

```gdscript
class_name PFTask
# id: String, kind: String, payload: Dictionary
# signal progress(ratio: float, message: String)
# signal finished(result: Variant)
# signal failed(error: PFError)
# func cancel() -> void
```

- 队列默认并发 2（可设置），CPU 重活走 `WorkerThreadPool`，网络走 HTTPRequest 异步。
- UI 通过 task id 订阅进度，在画布元素上画进度角标（见 PRODUCT.md 原则2）。
- **GDScript 线程注意**：WorkerThreadPool 内禁止触碰场景树；算法纯函数化天然满足。

### 4.3 撤销/重做

用 Godot 内置 `UndoRedo`，按"动作"粒度注册 do/undo 闭包。图像级修改存**修改区域的前后快照**（BBox + 两块子 Image），不存全图，控制内存。画布结构修改（增删元素、移动）存轻量命令对象。

### 4.4 错误处理

统一 `PFError { code: String, message: String, detail: Dictionary, recoverable: bool }`。core 层算法失败返回 `null` 并通过最后一个参数（可选 `out_error`）或返回 Dictionary `{ok, value, error}` 传递——任务卡中明确各函数采用哪种。**禁止**在 core 层弹 UI 或打印用户级提示，那是 UI 层的事。

### 4.5 风格预设贯穿机制

`StylePreset` 资源在三处被消费：生成端（PROVIDER-API 请求中的 style 字段 → 拼接提示词模板）、清洗端（pipeline 的默认参数来源）、编辑端（编辑器默认调色板与网格）。这是产品的核心一致性机制，改动 StylePreset schema 必须三处同步检查。

### 4.6 画布-图绑定

图逻辑（graphs/）与画布布局（canvas.json）分离：UI 层 `canvas_node_view` / `canvas_edge_layer` 按 node_id 对账渲染节点与连线，连线只从 graphs 渲染、不写进 canvas.json（PROJECT-FORMAT §4）。core 层 `pf_graph` / `executor` 不感知画布，保持 headless 可测（依赖铁律不变）。批次内容节点（GRAPH-SCHEMA §5a）的菜单处理走 services 层调 core 算法（与 process 节点同函数），记 undo + provenance，不改图结构。

## 5. 编码规范（gdlint 默认 + 以下补充）

- 类名 `PF` 前缀 PascalCase（PFGraph, PFTask）；文件 snake_case。
- 所有公共函数显式类型标注（参数与返回值）。
- 信号命名过去式（`task_finished`），方法命令式（`run_task`）。
- 每个 core 类文件头部注释块：职责一句话 + 输入输出契约 + 引用的契约文档（如 `# contract: 02-contracts/GRAPH-SCHEMA.md §3`）。
- 魔法数字一律提常量；用户可见字符串集中到 `ui/shell/strings.gd`（为未来 i18n 留口，v1.0 前 UI 英文、注释与文档中文——与 HexDungeon 项目同样的 CJK 字体考量，待打包自带 CJK 字体后再上中文 UI）。
- **UI 缩放**：界面缩放由 `Window.content_scale_factor`（启动按 `_resolve_interface_scale()` 检测）统一驱动，所有 Control 尺寸/字号写逻辑常量、由 factor 等比放大，禁止 `_scaled_int()` 与组件级 `ui_scale` 注入。画布美术不随 chrome 二次放大：设备倍率 `F_canvas = max(1, round(F))`，净美术放大 = `camera_zoom × F_canvas`（整数对齐、NEAREST 硬边）。新增 UI 不需要任何缩放接线；`scripts/check_ui_scaling.sh` 做静态守护，合法例外用 `# scale-exempt:` 放行。
- PixelForge 的编辑器调试默认禁用 Godot Game embedding（全局 editor setting `run/window_placement/game_embed_mode=2`，可运行 `pixel/scripts/configure_editor_game_view.sh` 设置），让 Play 行为接近导出后的独立桌面窗口。若临时启用 Game bar 调试，内嵌 Game View 必须使用 `Stretch to Fit`（本地 `.godot/editor/project_metadata.cfg` 的 `embed_size_mode=2`）；默认 `Fixed Size` 会按项目基准分辨率居中显示并暴露外圈盲区，这是编辑器调试视图设置，不应在产品窗口代码中补偿。

## 6. 测试策略摘要（详见 05-quality/QUALITY.md）

- core 层：纯单元测试，目标行覆盖 ≥80%。算法用 `tests/fixtures/` 合成样本（程序生成已知答案的伪像素图）做黄金测试。
- services 层：集成测试（项目保存→重开→比对；任务队列并发与取消）。
- ui 层：冒烟测试为主（场景能实例化、关键信号连通），不追求 UI 自动化覆盖。
- 每张任务卡的验收标准包含其测试要求；CI 红灯禁止合并。

## 7. 性能预算与逃生舱

| 场景 | 预算 | 超标时的替换路径 |
|---|---|---|
| 清洗 512×512 AI 图（检测+重采样+量化） | < 2s | grid_detector/quantizer 移植 Rust GDExtension |
| 批量清洗 50 张 | < 60s，UI 不卡 | WorkerThreadPool 并行（先做）→ Rust |
| 画布 500 个元素平移缩放 | 60 fps | 元素纹理 LOD + 视口剔除（M0 已内置设计） |
| 编辑器画笔延迟 | < 16ms | 脏矩形更新（M6 设计要求），不重建全图纹理 |

**规则**：先用 GDScript 写对，测出真实数字，再按表替换。禁止过早优化，但**接口必须按可替换设计**——core 算法纯函数 + 显式参数字典，恰好满足。

## 8. 兼容性与升级策略

- `.pxproj` 清单含 `format_version`（int）。读旧版本走迁移函数链（v1→v2→v3…），写永远最新版。迁移函数与测试样本一起提交。
- 节点图 schema 同理（GRAPH-SCHEMA.md §6）。
- Provider/Plugin 接口有 `api_version`；主程序加载时校验，不匹配则拒载并提示。
- Godot 升级：锁 4.6.x；升 4.7+ 单独开任务卡评估（GraphEdit/TileMapLayer API 变动风险点已在调研中标注）。
