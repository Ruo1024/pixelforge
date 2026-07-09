# M3 UX-4 LOD 撤销回执

日期：2026-06-19（含同日源码复核更新）

> **复核更新说明**：撤销当时的初版回执把「缩到 25% 不切 overview、且 follow-up 后依旧」的持续失败，归因为「父级 transform 变化未触发 `_draw()` 重绘 / 重绘诊断不完整」。同日基于源码复核更正：**那次重绘修复实际有效、且走在真实路径上；真正的根因是 LOD 判档读取了错误的缩放量——读的是 `art_logical_scale`，而阈值是按 `camera_zoom` 定的**。原始初判保留在「撤销时的初判（已更正）」一节以备追溯，「根因（复核确认）」「修复方案」「验证方案」为复核结论。

## 撤销范围

本回执记录对下列两次 UX-4 LOD 相关提交的撤销：

- `6ef9915 Add M3 batch LOD profile`
- `0aa55ed Fix batch LOD redraw on zoom`

撤销方式采用 `git revert --no-commit 0aa55ed 6ef9915` 生成反向变更，再与本回执一起提交；没有使用 `git reset`，没有回滚用户已有本地改动。撤销提交为 `7f9481d`。

## 两次修改曾尝试实现的内容

1. 新增 `PFCanvasLODProfile`，按画布 art scale 分出 `overview / review / inspect` 三档。
2. 在 `PFCanvasBatchCard` 中根据 LOD 档位切换绘制：overview（摘要底板、状态分布条、可见数量）、review（保留 contact sheet / focus 缩略图审阅）、inspect（放大后叠棋盘底和像素网格）。
3. 新增 `verify_m3_ux4.sh` 与单元测试，覆盖 LOD 阈值、overview 几何命中、inspect 档位。
4. follow-up（`0aa55ed`）补了一次 redraw 修复：`_ready()` 里 `set_notify_transform(true)`，`_notification()` 收到 `NOTIFICATION_TRANSFORM_CHANGED` 时 `queue_redraw()`。

## 根因（复核确认）

**LOD 判档读的是错误的缩放量——阈值空间与读值空间不一致。**

- 阈值定义在 `canvas_lod_profile.gd`：`OVERVIEW_MAX_ART_SCALE = 0.25`、`INSPECT_MIN_ART_SCALE = 4.0`。这两个数恰好是 `infinite_canvas.gd` 中 `ZOOM_LEVELS` 的条目，说明阈值是按 **`camera_zoom`（用户看到的缩放百分比）** 定的。
- 但卡片判档走 `canvas_batch_card.gd::_current_art_scale()`，返回 `get_parent().scale.x`。卡片的父节点是 `item_layer`（`infinite_canvas.gd::_add_batch_direct()` 用 `item_layer.add_child(item)`），而 `_update_layer_transform()` 设的是 `item_layer.scale = art_logical_scale`（`infinite_canvas.gd:891`）。
- `art_logical_scale = camera_zoom × compute_canvas_compensation_scale(vsf)`，补偿 = `round(vsf) / vsf`（`canvas_scale_policy.gd`；`vsf` = 视口缩放因子 = `content_scale_factor × window stretch`）。

于是卡片实际比较的是 `camera_zoom × round(vsf)/vsf`，而阈值是纯 `camera_zoom`。**仅当 vsf 为整数（1.0、2.0…）时两者相等**；vsf 非整数时（mac 分数缩放/外接屏、Windows 125/150%、window-stretch 比例非 1），补偿 ≠ 1，比较值就偏离用户真实缩放百分比。

代入现象（缩到 25%，`camera_zoom = 0.25`）：

| vsf | device = round(vsf) | 补偿 = device/vsf | 实际比较值 | 结果 |
|-----|---------------------|-------------------|-----------|------|
| 1.0 | 1 | 1.000 | 0.250 | ✅ overview |
| 1.5 | 2 | 1.333 | 0.333 | ❌ 卡在 review |
| 1.75 | 2 | 1.143 | 0.286 | ❌ 卡在 review |
| 2.0 | 2 | 1.000 | 0.250 | ✅ overview |

危险区间约为 **vsf ∈ [1.5, 2.0)**（及 [2.5, 3.0) 等向上取整带）。0.333 > 0.25 永远满足不了 `<= 0.25`，故一直停在 review——与「缩到 25% 仍是完整缩略图网格」的报告完全吻合。一句话：**LOD 阈值活在 `camera_zoom` 空间，读到的值活在 `art_logical_scale` 空间，两者只在整数 DPI 下重合。**

**实机申报**：根因机制已由源码确认；用户机器的具体 vsf 值为**推断**（落在 [1.5, 2.0) 才解释得通该现象），尚未实测。修复时应在实机打印一次 `_resolve_viewport_scale_factor()` 的实际值以确认。

## 撤销时的初判（已更正）

初版回执「遇到的问题/潜在问题」中，以下两条经复核为**误判**，更正如下：

- ~~「父级 transform 变化未触发 `_draw()` 重绘，前一次修复触发点不在真实运行路径」~~ → Godot 中父节点 scale 变化确实不会自动重跑子项 `_draw()`（绘制命令被缓存，仅以新 transform 重新变换缓存）；但 `0aa55ed` 用的 `set_notify_transform(true)` + `NOTIFICATION_TRANSFORM_CHANGED → queue_redraw()` 正是官方标准做法，且此处 zoom 为直接赋值（非 Tween），通知会正常触发。**该重绘修复有效且在真实路径上**——它让 `_draw()` 重跑后又重算出同一个错误档位，从而把真正的「值错误」暴露出来。把账记在重绘上是一次误诊。
- ~~「`set_notify_transform(true)` 通知不可靠，可能不覆盖 item layer 缩放」~~ → 无依据。唯一已知不可靠场景是父节点用 Tween 动画（Godot issue #34740），本项目 zoom 非 Tween，不适用。

以下初判经复核**成立**，已并入后续章节：LOD 责任位置应上移到画布统一计算（见「修复方案」）；headless 单元测试无法证明真实切换（见「验证方案」——更准确的说法是当前测试绕开了真实集成路径，而非「必须靠截图」）。

补充一处测试盲点定位：三个测试全都绕开真实管线——`profile_for_art_scale` 喂理想值；overview 几何测试用 `_set_lod_profile_override_for_test()` 直接覆盖档位；`test_canvas_batch_card_tracks_parent_transform_for_lod_redraw` 是 `new Node2D()` 直接 `parent.scale = 0.125` 再读回的**自证恒真测试**，既没测重绘、也没经过 `camera_zoom → 分数 vsf → art_logical_scale` 这条真实链路。故套件全绿而真实路径是坏的。

## 修复方案（具体）

**核心：让 LOD 由 `camera_zoom` 驱动，画布统一计算并主动下发，子项不再反查父 transform。**

1. **卡片侧**（`canvas_batch_card.gd`）：新增 `set_lod_camera_zoom(zoom: float)`，存入 `_lod_camera_zoom`，值变化才 `queue_redraw()`；`_get_lod_profile()` 改为 `LODProfile.profile_for_art_scale(_lod_camera_zoom)`。删除 `_current_art_scale()`（读父 scale），以及 `_ready()`/`_notification()` 的 transform-notify 重绘 hack（画布主动推送后不再需要）。保留 `_lod_profile_override`（测试用）。
2. **画布侧**（`infinite_canvas.gd`）：在 `_update_layer_transform()` 设完 `item_layer.scale` 之后，遍历 batch 卡片调用 `set_lod_camera_zoom(camera_zoom)`。`_update_layer_transform()` 是所有 zoom 路径（`set_camera_zoom` / `zoom_by_steps` / `_ready` / resize）的唯一汇聚点，下发与重绘时机天然正确，且**不依赖 transform 通知**（顺带规避 Tween 边界）。pan 也会调用它，但 setter 对未变化的值 no-op，开销可忽略。
3. **口径一致性**：用 `camera_zoom` 与现有 `scale_audit.gd`（已读 `canvas.camera_zoom`）、`zoom_changed` 信号口径统一；阈值回到与 `ZOOM_LEVELS` 同一空间，用户「25% → overview」的预期成立，且与显示器 DPI 解耦（25% 在任何 DPI 下都应是 overview）。
4. **文件行数**：`infinite_canvas.gd` 已 999 行（软上限 1000）。本次下发逻辑很小，可就地加；若后续画布层 LOD 逻辑继续增长，再抽 `canvas_lod_coordinator`，不为压行数提前拆散内聚逻辑。

inspect 档的像素网格子判定 `should_draw_pixel_grid` 仍按 draw-rect 本地空间的 cell_size 守门，属另一关注点，本次不动。

## 验证方案

1. **Headless 集成测试（堵住真正缺口，无需截图）**：用真实 `PFInfiniteCanvas`，`_set_viewport_scale_factor_for_test(1.5)`（落在危险带）+ `set_camera_zoom(0.25)`，断言目标 batch 卡片 `_get_lod_profile() == OVERVIEW`；再在 `camera_zoom = 4.0` 断言 `INSPECT`、`1.0` 断言 `REVIEW`。该测试在旧实现下应为红、新实现下转绿——正好覆盖此前漏掉的「分数 vsf × 真实 zoom 管线」。
2. **撤掉/替换恒真测试**：删除或改写 `test_canvas_batch_card_tracks_parent_transform_for_lod_redraw`（自证测试），并入上面的集成测试。
3. **实机申报项**：在 mac（用户机）+ Windows 各跑一次，确认 25% 真的切到 overview；并打印一次实际 vsf 验证根因推断。
4. **门禁**：恢复 `verify_m3_ux4.sh` 时确保 `run_tests.sh` 含新集成测试；保留「禁止暂存图片」检查。

## 仍需后续处理的前瞻项（非本次根因）

- **阈值实机校准**：25%→overview、50%→review 的语义边界应由 UX 验收清单定义，而非仅凭常量；修复后在实机复核档位手感。
- **overview 下的输入仲裁**：overview 是否允许缩略图点击、还是只允许选整卡，属 UX-7 Hit-test 与输入仲裁范畴，不在 UX-4 用临时规则抢先决定。

## 撤销后状态

- UX-4 LOD 相关代码、脚本、测试和 changelog 记录已被撤销（`7f9481d`）。
- `M3_G2_mock_generate_batch_completion_report.md` 中两次 UX-4 追加记录随 revert 移除，本回执作为单独失败+复核记录留存。
- 现有 UX-3 Focus View、UX-5/UX-6 批次审阅与对比能力不受本次撤销影响。
