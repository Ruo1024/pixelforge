# M7 — 插件系统 + ComfyUI 桥（功能3c）

> 目标：PLUGIN-API.md 落地（插件加载器 + 内置插件迁移自检）+ ComfyUI 桥接插件（本地免费生成路线）。
> 依赖：M4（provider 体系成熟）。
> 现状依据：RESEARCH-NOTES §2（ComfyUI /prompt + WebSocket 模式 2026 仍是标准；workflow API JSON 导出方式）。

---

## M7-1 插件加载器（plugin_service.gd）

**目标**：PLUGIN-API §3 机制完整实现。

**技术实现指导**：
- 启动扫描 `user://plugins/*/plugin.json` 与 `user://plugins/*.pck`；清单校验（api_version/min_app_version 不符→拒载+UI 列表中灰显原因）。
- PCK：`load_resource_pack` 后从 `res://plugins/{id}/{entry}` 加载；路径根校验。
- `PFPluginAPI` 实现：每插件一个 api 实例记账注册项，`_exit_app`/卸载/重载时反向清理（节点类型从 registry 摘除→已打开图中相应节点转幽灵——复用 M3 机制，数据不丢）。
- 失败隔离：入口脚本加载/执行包 try（GDScript 无异常：用 `load()` 空检 + `call` 前 `has_method` 检 + 入口分步校验），单插件失败仅日志+提示。
- 插件管理 UI：列表（启用开关/版本/权限声明展示/卸载）；"打开插件目录"按钮；安装=拖 .pck 入窗口或文件选择。
- 开发者文档 `docs/plugin-dev.md`：从模板（仓库 `templates/plugin_template/`）到打包 .pck（提供 `scripts/pack_plugin.sh` 用 godot --headless --export-pack）的全流程教程 + PFPluginAPI 参考。

**验收标准**：
1. 集成：示例插件（注册 1 节点+1 菜单）目录态/PCK 态均可装载卸载，卸载后图中节点变幽灵、重装恢复。
2. 故意损坏的插件（语法错/清单缺字段/版本不符）三案例均被隔离且 UI 说明原因。
3. CI：内置 provider 插件逐个移除后主程序启动正常（PLUGIN-API §5 解耦验证）。

---

## M7-2 ComfyUI 桥 Provider（plugins/bridge_comfyui/）

**目标**：连接用户本地（或局域网）ComfyUI 实例为生成后端，工作流模板化复用。

**技术实现指导**：
- 配置：endpoint（默认 http://127.0.0.1:8188）、连通检测（GET /system_stats）。
- **工作流模板机制**（核心设计）：
  - 用户在 ComfyUI 里调好工作流 → 导出 API 格式 JSON → 导入本插件成"模板"。
  - 模板参数绑定 UI：插件解析 JSON 节点树，列出常见可绑定槽位（启发式识别：KSampler.seed、CLIPTextEncode.text、EmptyLatentImage.width/height、LoadImage.image），用户把 PFGenRequest 字段（prompt/seed/width/height/ref_image）映射到具体节点输入路径（下拉选择 `node_id.input_name`）。映射存模板元数据。
  - 内置 2 个出厂模板：SDXL+pixel-art-LoRA txt2img、img2img 重绘（JSON 随插件分发，注明所需模型清单与 civitai 链接，缺模型时错误信息透传）。
- 执行：填充模板 JSON → POST /prompt → WebSocketPeer 连 /ws 听进度（executing/progress 消息→task progress；缺 websocket 时降级轮询 /history）→ 完成后 GET /history/{prompt_id} → /view 拉图。
- 图片上传（img2img）：POST /upload/image multipart。
- ref_image/结果均走临时文件命名空间（uuid 前缀）避免冲突；任务取消调 POST /interrupt。
- capabilities 动态：依模板能力声明（含 inpaint 模板时 inpaint=true）。
- raw_pixel=false（SD 输出伪像素，清洗管线接力——与 M4-4 同语义）。

**验收标准**：
1. 契约测试（mock ComfyUI 服务器 fixture：录制真实消息序列回放）：模板填充正确性（JSON 路径写入）、ws 进度解析、取消、断连重试。
2. --manual 真实例：出厂模板出图入库全链路；进度条平滑；中途断 ComfyUI 错误人话提示。
3. 模板导入：拿一个社区复杂工作流 JSON（30+ 节点）导入→绑定→运行成功（兼容性证明）。

---

## M7-3 节点级 ComfyUI 集成（comfyui.run_workflow 图节点）

**目标**：把 ComfyUI 模板暴露为节点图中的一等节点（带模板选择参数），与内置节点混排。

**技术实现指导**：
- 插件经 `register_node_type("comfyui.run_workflow", ...)` 注入；param schema 动态：模板下拉 + 所选模板的绑定槽位生成参数项（get_param_schema 支持依赖刷新——M3-3 检查器需支持 schema 变更重渲染信号，若缺此能力本卡先补 M3 检查器）。
- 输入端口 image（可选 ref）/text/style；style 处理：模板含 LoRA 槽时 hint 映射，否则模板尾缀拼接。
- 批量语义遵循 executor map 展开；ComfyUI 端排队天然串行，并发槽=1 注记 capabilities.max_batch。

**验收标准**：
1. 混合图端到端（手动）：object_list → comfyui.run_workflow → pixel_cleanup → slice → 库。与云 provider 节点在同图共存执行。
2. 插件卸载→图节点幽灵化→重装恢复（回归 M7-1）。

---

## M7 整体验收（= v1.0 出口）

- 三类生成后端（云×2、ComfyUI、mock）在同一 Provider 抽象下无特判共存（代码评审：ai_generate 节点与 executor 无任何 provider 特例分支）。
- 插件开发文档可用性验证：一名未参与开发的工程师（或 AI）仅凭文档从模板做出"图像反相节点"插件 ≤ 1 小时。
- v1.0 发布检查单（05-quality/QUALITY.md 附录）全过。
