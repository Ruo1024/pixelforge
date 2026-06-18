# M3 UX-4 LOD 撤销回执

日期：2026-06-19

## 撤销范围

本回执记录对下列两次 UX-4 LOD 相关提交的撤销：

- `6ef9915 Add M3 batch LOD profile`
- `0aa55ed Fix batch LOD redraw on zoom`

撤销方式采用 `git revert --no-commit 0aa55ed 6ef9915` 生成反向变更，再与本回执一起提交；没有使用 `git reset`，没有回滚用户已有本地改动。

## 两次修改曾尝试实现的内容

1. 新增 `PFCanvasLODProfile`，按画布 art scale 分出 `overview / review / inspect` 三档。
2. 在 `PFCanvasBatchCard` 中根据 LOD 档位切换绘制：
   - overview：摘要底板、状态分布条、可见数量。
   - review：保留 contact sheet / focus view 缩略图审阅。
   - inspect：放大后叠棋盘底和像素网格。
3. 新增 `verify_m3_ux4.sh` 与单元测试，覆盖 LOD 阈值、overview 几何命中、inspect 档位。
4. follow-up 中补过一次 redraw 修复：尝试让 batch card 在 transform 变化时 `queue_redraw()`。

## 遇到的问题

- 用户实测缩小到 25% 后，batch 视觉仍保持完整缩略图网格，没有切到 overview 摘要。
- follow-up 后问题依旧存在，说明前一次“父级 transform 变化未触发 `_draw()` 重绘”的诊断不完整，或修复触发点不在真实运行路径上。
- 自动化测试只验证了 LOD 策略函数和局部节点状态，没有覆盖真实主窗口中“缩放控件/滚轮 → item layer transform → batch card 视觉重新绘制”的端到端画面结果。
- 由于初版实现把 LOD 决策放在 `canvas_batch_card.gd` 自身 `_draw()` 内，实际运行中很容易被 Godot `Node2D` 绘制缓存、父层缩放、视口缩放补偿或重绘时机影响。

## 潜在问题

- **LOD 责任位置可能放错**：语义 LOD 应由 `PFInfiniteCanvas` 或专门的 canvas LOD mediator 统一计算并主动广播，而不是让每个子项在 `_draw()` 时临时读取父 transform。
- **父 transform 通知不可靠**：`set_notify_transform(true)` 可能不足以覆盖 item layer 缩放、窗口缩放补偿或某些编辑器运行视图路径下的真实重绘触发。
- **测试覆盖缺口**：当前 headless 单元测试无法证明视觉真的从缩略图网格切成 overview，需要补主窗口 smoke 或截图/pixel check 类验证。
- **阈值语义未被实机校准**：25% 是否应该进入 overview、50% 是否应该保持 review，需要通过 UX 验收清单重新定义，而不是仅凭常量决定。
- **`infinite_canvas.gd` 已接近行数软上限**：后续若在画布层集中处理 LOD，可能需要先抽出 canvas item update/LOD coordinator，避免继续把逻辑塞进 999 行文件。
- **输入仲裁未定义**：overview 下是否允许缩略图点击、是否只允许选整卡，属于 UX-7 Hit-test 与输入仲裁问题，不能在 UX-4 中用临时规则抢先决定。

## 给审核 agent 的建议交接点

1. 先重新定义 UX-4 的最小验收：缩放到哪些档位必须出现哪些可见变化，并明确 25% 的 expected behavior。
2. 设计一个画布级 LOD 状态流：
   - `PFInfiniteCanvas` 在 zoom / viewport scale / item layer scale 变化后计算当前 LOD。
   - 子项通过显式 setter 接收 LOD，setter 内部负责 `queue_redraw()`。
   - 避免子项在 `_draw()` 内反查父 transform。
3. 补一条主窗口级验证：生成 mock batch 后缩放到 25%，检查 batch card 当前 LOD 或进行截图像素检查。
4. 把 overview 的输入行为交给 UX-7 统一设计，不在 LOD 卡里临时禁用或启用缩略图命中。

## 撤销后状态

- UX-4 LOD 相关代码、脚本、测试和 changelog 记录被撤销。
- `M3_G2_mock_generate_batch_completion_report.md` 中这两次 UX-4 追加记录随 revert 移除，本回执作为单独失败记录留存。
- 现有 UX-3 Focus View、UX-5/UX-6 批次审阅与对比能力不应被本次撤销影响。
