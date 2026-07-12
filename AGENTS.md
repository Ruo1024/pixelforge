# PixelForge 工作区约定（所有 agent 必读）

## 1. 文件范围与安全红线

- 代码只写入 `pixel/`；计划、研究与报告只写入 `pixelforge-plan/`；临时草稿写入已忽略的 `scratch/`。除既有工作区规则文件外，不在仓库根目录新增文件。
- 里程碑/修复报告写入 `pixelforge-plan/03-milestones/reports/`；算法研究写入 `04-research/`；外部算法参考写入 `06-algorithm-refs/`。
- 不修改、不纳入 git：`垃圾桶/`、`godot-interactive-guide/`。
- `test picture/` 与 `pixel/tests/fixtures/real/` 含未获公开许可的图像，绝不 commit 或 push，也不得绕过 ignore 规则。

## 2. 产品与工程默认规则

- 新功能先说明它服务哪段用户旅程；“完成”表示入口、过程反馈、结果和下一步在应用中连通，不能只以代码或单测存在为准。
- `pixelforge-plan/02-contracts/` 是跨模块接口的唯一事实来源。发现契约缺陷时提出修订并等待批准，禁止静默绕过。
- 用户可见文案必须经过集中 i18n 目录/访问层；不得在组件中散落裸字符串。`pixel/ui/shell/strings.gd` 可作为迁移期兼容入口。
- UI chrome 继承根窗口统一缩放策略；画布美术继续按设备像素整数对齐自管。不要在组件内私设第二套缩放倍率或硬编码像素字号；具体规则与守护见 `ARCHITECTURE.md §5` 和 `pixel/scripts/check_ui_scaling.sh`。
- 禁止裸 `print`；使用项目日志工具，并避免输出密钥、用户素材或完整外部响应。
- 注释只保留在关键逻辑节点：模块职责、契约边界、非显然不变量、兼容/安全原因，以及影响应用行为的重要实现决策。不要逐行复述代码、记录临时思考或用长注释代替文档。
- 文件约 1000 行是软目标；只按职责拆分，不为压行数破坏内聚性。
- 新增外部算法或资产参考时记录来源与许可证。既有 perfectPixel 集成说明见 `06-algorithm-refs/perfectPixel/INTEGRATION.md`。

## 3. 开发节奏与验收

- 任务卡仍是边界清晰的实现单元；当前 Beta 0.3–0.5 由一个 Goal 连续完成全部三版，无需在单卡、集成切片或版本出口停下等待用户。
- 开发中持续运行定向自动化测试；在集成边界运行全量回归。自动化红灯不得带入下一阶段。
- Beta 0.3–0.5 开发期间完全不使用 Computer Use，也不请求项目所有者分段测试。只允许自动化测试和脚本生成的固定截图；三版全部工程完成后再由项目所有者统一人工验收。
- 报告必须区分：`工程通过`、`人工通过`、`发布通过`。自动化与脚本截图不能替代项目所有者签收。
- UI、缩放、字体、跨平台等难定位问题先在隔离分支通过自动化矩阵、日志和脚本截图建立证据与根因，再实施最小修复；禁止把未经验证的猜测写成既定方案。
- 用户否决的原型必须标记为未通过、撤销或登记设计债，后续不得描述为已完成能力。
- 产品方向、体验取舍或契约含义存在实质歧义时，把选项、依据和影响交给用户决定。
- 子 agent 适合做原始资料收集、历史/源码定位和边界明确的并行实现；主 agent 负责产品判断、技术结论、集成与最终验收口径。
- Beta 0.3–0.5 卡片标注的无限画布交互若仍模糊，优先让低上下文子 agent 只读核对 `hero8152/Infinite-Canvas` 对应模块的入口、状态、反馈、结果和异常；不得复制其代码、样式、截图、资产或工作流文件。
- 交接只记录当前阶段、关键提交、验证命令、已知失败和下一步，避免重复粘贴大段源码或历史报告。

## 4. Git 纪律

- 开发在本地 `codex/` 分支或独立 worktree 进行；按整体切片保留可回退提交。Beta 0.3/0.4 出口只保留提交与测试日志，Beta 0.5 统一生成一次三版 diff 模式工程报告。
- 项目所有者统一人工验收通过前，不合并到 `main`、不 push。若候选不通过，优先修复当前未推送分支；需要整体放弃时保留证据并等待用户确认后再执行破坏性操作。
- 多 agent 并行改代码时各用独立 worktree 与分支，完成后由主 agent 审核并集成。
- commit 前检查 staged 文件；下列命令应无输出（`addons/gut` 自带图标除外）：

  ```bash
  git diff --cached --name-only | grep -iE '\.(png|jpg|jpeg)$'
  ```

## 5. 按需阅读索引

首次接触先读 `pixelforge-plan/README.md` 和 `03-milestones/CURRENT-STATE.md`，再按任务选择：

| 场景 | 必读 |
|---|---|
| 写代码或调整分层 | `01-architecture/ARCHITECTURE.md` |
| UI / 交互 / 用户旅程 | `00-vision/PRODUCT.md` |
| 项目格式、画布持久化 | `02-contracts/PROJECT-FORMAT.md` |
| 节点模型与执行 | `02-contracts/GRAPH-SCHEMA.md` |
| Provider / 队列 | `02-contracts/PROVIDER-API.md` |
| 插件 / 内置扩展 | `02-contracts/PLUGIN-API.md` |
| 风格与调色板 | `02-contracts/STYLE-PRESETS.md` |
| 测试与阶段出口 | `05-quality/QUALITY.md` + 当前 Beta 计划 |
| 像素算法 | `04-research/ALGORITHM_RESEARCH.md` + 对应 `06-algorithm-refs/` |

技术选型疑问先查 `04-research/RESEARCH-NOTES.md`，避免重复调研已有结论。
