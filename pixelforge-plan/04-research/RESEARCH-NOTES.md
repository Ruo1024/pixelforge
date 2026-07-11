# RESEARCH-NOTES.md — 2026-06 调研结论存档

> 本文件是技术选型的事实依据。主体结论核实于 2026年6月；落地实现前涉及外部 API 的部分应重新验证（标注 ⚠ 的尤其如此）。M4-V1 的 OpenAI 小节已于 2026-07-11 复核。

## 1. Godot 技术栈核实

- **当前稳定版**：Godot 4.6.3（2026-05-20）。4.6 起默认现代主题；LibGodot 可嵌入；多窗口稳定。曾有 `low_processor_usage_mode` 多窗口 CPU 回归（Issue #101058/#102914），4.6 已修复——工具应用必须开启此模式，CI 加空载 CPU 检查。
- **Pixelorama 先例**：纯 GDScript、运行于 Godot 4.6.3、8.5k+ stars，功能含时间线/洋葱皮/平铺/调色板/混合模式——证明 GDScript 性能上限足够本产品全部 2D 需求。
- **Material Maker 1.4 先例**（2025-10，Godot 4.4.1）：GraphEdit 承载 200+ 节点的程序化纹理工具，节点工作流形态与本产品功能3高度同构。GraphEdit 注意点：类型端口/缩放平移/minimap 原生支持；端口类型校验逻辑需自写；深度自定义连线样式成本高（v1 不做）。**（2026-06-16 更新：本产品最终选择画布原生自绘节点，不复用 GraphEdit——统一画布决策，节点与参考卡/批次同坐标互连；GraphEdit 仅作交互手感参考。见 ARCHITECTURE §1、M3、无限画布架构审阅 顶部。）**
- **TileMapLayer**：4.2 起替代 TileMap。内置 Terrain（autotile）运行时 API 难用且有 bug（peering bits 异常案例多）；Better Terrain 插件是编辑器态方案，**运行时自实现 blob 匹配表更可控**（M5-2 采用）。
- **网络**：HTTPRequest（单节点禁并发，需池化）、WebSocketPeer 需逐帧 poll——满足 ComfyUI ws 进度协议。
- **性能逃生舱**：GDScript 数值运算慢是定论；PackedByteArray/PackedFloat32Array 批操作可缓解；Rust GDExtension（godot-rust/gdext）成熟；Compute Shader 在 Compatibility 渲染器不可用（**Forward+ 默认的依据之一**）。
- **插件机制**：EditorPlugin 导出后不可用；`ProjectSettings.load_resource_pack()` 运行时加载 PCK 可行（GDScript only，C# 有缺陷）——PLUGIN-API 的技术基础。
- **Aseprite**：专有软件（2016 年起非开源，源码可见禁再分发），$19.99；LibreSprite（旧 GPL fork）停滞。→ 本产品内置编辑器无版权风险参考其交互（交互范式不受版权保护），但**不可抄代码**。

## 2. AI 生成生态核实

### 像素专用服务
- **Retro Diffusion** ⚠：活跃；REST API（github.com/Retro-Diffusion/api-examples）+ MCP；<$0.01/张按量计费；能力：16×16–512×512、透明背景（remove_bg）、tileset/动画风格、12+ 风格、自定义调色板；生成内容可商用（授权数据训练）。Aseprite 插件 $65/$20 证明"像素工具+AI 插件"付费模式成立。
- **PixelLab.ai** ⚠：活跃；API+MCP；8 方向角色、骨架动画、Wang tileset；订阅 ~$9–22/月。动画能力超出 v1 范围 → M7 后候选。

### 通用大厂 API
- **OpenAI（2026-07-11 复核）**：官方当前推荐图像模型为 `gpt-image-2`，生成端点为 `POST /v1/images/generations`，响应图像位于 `data[].b64_json`。该模型不支持透明背景，输出尺寸为 1024/1536 固定档，因此很适合 M4-V1 暴露“高分辨率伪像素 → PixelForge 清洗”的价值。V1 使用 low quality 草稿档，不把未知实时费用伪装成精确估算。来源：[Image generation guide](https://developers.openai.com/api/docs/guides/image-generation)、[GPT Image 2 model](https://developers.openai.com/api/docs/models/gpt-image-2)。
- **Google**：Imagen 4 / Gemini 系图像 $0.02–0.13；透明背景未明确支持 + 强制 SynthID 水印 → 不入 v1 首选。
- **FLUX (BFL)**：FLUX.2（2025-11）；Kontext 编辑系；Fill 支持 alpha 掩码 inpaint；schnell 开源 Apache 2.0（本地/ComfyUI 路线素材）。
- **Stability**：SD3.5 API 在役，$0.03–0.08/张。

### ComfyUI ⚠
- POST /prompt（API 格式 JSON）→ GET /history/{id} → /view 取图；WebSocket /ws 进度推送——2026 仍是标准模式。
- API 格式 JSON 需在设置开 Dev Mode 后 "Export (API)"；与 UI 保存格式是两套 JSON（桥接插件只认 API 格式，文档须向用户强调）。
- 2025-26 变化：官方桌面版、Comfy Cloud（免费层无 API）。生态封装层（comfy-pack 等）众多但桥接直连原生 API 最稳。

### 关键认知：伪像素问题（功能1 的存在理由）
通用扩散模型输出高分辨率"像素风"图：网格不对齐、数百色、AA 边缘。社区标准管线 = 网格检测 → 降采样（众数）→ 量化 → 调色板映射 → 边缘清理。现成参照：ComfyUI-PixelArt-Detector、sd-webui-pixelart、Retro Diffusion 自研 pixeldetector。**结论：清洗管线是行业共识缺口，做成产品核心正确。**

### 商用授权速查
RetroDiffusion 可商用｜OpenAI 可商用（输出不训练）｜Stability 年收入<$100万免费｜FLUX schnell Apache2.0 / dev 非商用｜Google 可商用但带水印。美国判例（Thaler 案）：纯 AI 产物无版权，人工实质介入部分可保护——**产品内置"人工介入"工具链客观上提升用户素材的可保护性，可作宣传点（措辞谨慎，不构成法律意见）。**

## 3. 算法路线核实（功能1/2 实现依据）

1. **网格检测**开源先例：unfake.js（JS+Py，最完整）、proper-pixel-art（Hough 线聚类）、ai-pixelart-extractor、PixelRefiner、Pixel-Extractor（支持非方形像素+自动切分）。主流原理：边缘投影/自相关/FFT 找周期 + 相位搜索——M1-2 技术指导的依据。GDScript 重实现而非绑定（依赖最小化；算法本身 <500 行）。
2. **重采样**：众数采样是抗噪首选（unfake/proper-pixel-art 默认）——M1-3 依据。
3. **量化**：median cut（快）/k-means（质）/libimagequant（最优但 C 依赖，v1 不绑定）；固定板映射用 OKLab 距离（优于 RGB，实现 ~40 行）。Lospec 调色板数据 CC0 可内置，亦有公开 API（lospec.com/palettes/api）。
4. **抖动**：像素画社区美学偏好 ordered（Bayer）而非误差扩散（网格感一致、Obra Dinn 先例）；FS 仅照片转换场景——M1-4 默认值依据。
5. **抠图**：纯色底 → flood fill + 色键足够，**无需 AI**；复杂底才考虑 rembg isnet-anime（v1 范围外，插件点留白）。连通域（8-连通 BFS/two-pass）+ 近距合并启发做 sprite 切分——M2-3 依据。
6. **描边**：形态学膨胀/腐蚀，OpenCV 文档级标准操作，GDScript 直写。
7. **体素**：MagicaVoxel 仍是事实标准，.vox 格式公开；AI text→voxel 早期（text2vox 开源不稳定、VoxAI 商业初期）→ M8 推迟决策的依据。

## 4. 风格体系与竞品核实（功能5 风格预设 + 产品定位依据）

### 风格分类维度（STYLE-PRESETS 六维模型的来源）
分辨率档（8-bit/16-bit/Hi-bit/HD-2D）× 调色板限制（NES 3+1色/精灵、GB 4 色等硬件史塑造的风格语言）× 基准尺寸 × 描边 × 抖动 × 透视（侧/俯/3⁄4/等距）。
锚点参数：Celeste（320×180 基分辨率、8×8 tile、角色 16×16 ~12 色）；Stardew（16×32 NPC、16×16 物件）；HLD（480×270、角色 32×32）；Dead Cells（3D 渲染转 2D 像素管线——"3D 参考辅助"远期灵感）；HD-2D（高清像素精灵+3D 环境，Octopath 系）。
素材构建逻辑：blob 47（256 邻接态→47 独特块）是 autotile 行业标准（M5-2 映射表依据）；spritesheet 行=方向/动作列=帧惯例；idle 2-4 帧 walk 4-8 帧；VFX 与角色分层是行业习惯（M5-3 动效层依据）；视差背景 3-5 层。
调色板文化：Lospec 社区标准；DB16/DB32/PICO-8/Endesga/AAP-64 是公认经典（内置清单依据）。

### 竞品格局与定位空隙
- 传统编辑器：Aseprite（$19.99 事实标准）、Pixelorama（免费开源 Godot）、PyxelEdit（tileset 特长）、Pro Motion NG——**无 AI 整合**（Aseprite 有第三方 RD 插件）。
- AI 工具：PixelLab（最全：方向/动画/tileset）、Retro Diffusion（像素原生质量最高）、Scenario（风格训练）——**全是"生成器"，无清洗/拼图/批量工作流/本地工具链**。
- 用户痛点（社区调研）：①AI 出图非真像素（网格/色数）②风格一致性差 ③动画几乎不可用 ④"AI 出 70% 人修 30%"是共识工作流但工具链断裂（生成在网页、修图在 Aseprite、拼图在 Tiled——三处割裂）。
- **定位结论：PixelForge 不与生成模型竞争，做"生成之后的全部"——清洗、统一、批量、拼装、人修一体化。这是当前市场空白。**
- 交互参照：ComfyUI（节点表达力强但门槛高——简化版节点+模板降门槛）、Invoke unified canvas（画布+AI 融合体验标杆）、Figma/tldraw（无限画布交互范式）。

## 5. 后续需持续跟踪的不确定项
- ⚠ RetroDiffusion/PixelLab API 字段与价格：落地 M4/M7 前重新核对官方文档。
- ⚠ gpt-image 系列型号更替快；每次进入真实 Provider 施工前重新核对推荐型号、尺寸、透明背景和价格。
- ⚠ Godot 4.7 的 GraphEdit/TileMapLayer API 变化（升级评估卡触发）。
- ⚠ FLUX/SD 像素 LoRA 生态月度演进（出厂 ComfyUI 模板的模型选择在 M7 时点重选最优）。

## 附录 A. M1.1 GUT coverage 调研结论

- 调研时间：2026-06-13。
- 当前仓库 vendored GUT 未包含可搜索到的 `coverage` 命令、报告器或 headless 参数；`addons/gut/gut_cmdln.gd` 的现有出口参数只覆盖收集/运行/退出等流程。
- 结论：M1.1 不把“代码行数比”包装成覆盖率数字，采用 `05-quality/COVERAGE-MATRIX-M1.md` 的 public API / 分支矩阵替代，并用 `pixel/scripts/check_m1_1_coverage_matrix.sh` 在出口脚本中校验矩阵引用的测试名真实存在。

## 附录 B. Godot 4.6.3 headless 下 Image 线程安全调研（M1.1 批量压测）

- 调研时间：2026-06-13（M1.1 批量帧时间测试实现期间），M1.1 改进期从完成报告风险区升格至此，供 M2+ 架构决策引用。
- 现象：用 `WorkerThreadPool` 在 headless 模式下并行执行 `Image` 清洗（resample/quantize 全管线）不稳定——存在偶发崩溃/挂起，无可复现的最小用例但复现率足以阻断 CI。
- 当前结论：M1.1 批量压测改为主线程分帧 Apply 口径（每帧处理一张 + `await` 一帧）；产品现有 TaskQueue 路径暂未改分帧。
- 对 M2+ 的影响：若做大批量生产任务（批量抠图/切分/导出），必须先专项验证 `Image` 在线程内的安全边界（候选方案：每线程独立 `Image` 副本、仅在线程内做纯字节数组运算后主线程回写、或 Godot 官方 `Image` 线程安全声明确认后放开）。
- 关联：`pixel/tests/integration/test_cleanup_batch_performance.gd` 头部注释、M1.1 完成报告 §5。
