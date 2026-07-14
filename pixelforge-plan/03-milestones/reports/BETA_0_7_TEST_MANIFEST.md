# Beta 0.7 逐条测试 Manifest

> 状态：B7-0 至 B7-4 工程证据已记录，B7-5 执行中。本文不跳过 executable test；
> B7-5 至 B7-8 必须先按
> 对应条目写出能因当前缺陷真实失败的最小测试，保存红灯证据，再实现并转绿。

## 1. 口径

- ID 格式：`B7-REQ-<批准计划章节>-<序号>`，每个独立可违反要求只有一个 owner。
- 验证类型：unit / integration / smoke / static / roundtrip / geometry / i18n。
- 本卡结束时，所有现有自动化仍由 `./pixel/scripts/run_tests.sh` 全量运行；当前 runner
  不转发筛选参数，B7-1 如增加筛选能力必须保持无参数行为不变。
- 表中命令是当前即可复制执行的 `./pixel/scripts/run_tests.sh`，它会启动本地 mock HTTP
  fixture 后运行全量。当前 runner 不转发筛选参数；每卡保存 red 证据时至少记录新增
  test 的具体失败名。若 B7-1 增加可安全启动同一 mock fixture 的定向入口，可把对应行
  补为该命令，但无参数全量行为不得改变；每卡提交前仍必须跑上述全量命令。
- 禁止 skip/xfail、降低断言、改基线数字来消除红灯。真实付费 API、Computer Use 和
  未许可图片不属于测试手段。

### 1.1 B7-DEC-OWNER-01：混合旧测试的 owner 拆分

项目所有者于 2026-07-14 裁定采用 owner 拆分，不改变批准的 Beta 0.7 执行书、卡片
顺序或产品含义：

- 执行书的 B7-2 hard cut 优先；本卡必须删除 `batch.params.asset_ids`、
  `review_states`、`review_filter`、`review_layout`、`focus_asset_id`、`compare_*` 和旧
  overwrite 语义，不保留 alias/兼容字段。旧 UI 与下游只允许读取 `result_slots` 中
  `succeeded && !detached` 的唯一可见投影。
- 本 manifest 的 owner 表示“独立可违反行为的最终主责”，不禁止前卡清除已被 hard
  cut 直接废止的 schema 断言。混合旧测试必须按断言职责拆分，不能整文件删除。
- B7-2 是 legacy schema retirement owner：移除上述旧字段断言，并补
  `result_slots`、`get_visible_asset_ids()`、无旧字段和无 alias 的最小 v2 等价断言。
- B7-4 仍独占最终 `GenerationRunCoordinator`、新 Output/history、禁止覆盖与 mock run
  行为；B7-5 仍独占最终 Output 卡、选择、滚动、拆出、预览以及旧 review/focus/compare
  符号移除守护。B7-2 的 schema 迁移不能提前勾销后两卡 red→green 或完成门。
- 下载/export、标题、尺寸、折叠、Undo、通用 LOD、编辑入口等未退役行为必须保留或
  迁移。下表将直接 hard cut 的旧 schema 条目改由 B7-2 主责；最终 UI/协调器条目仍
  保持原 owner。
- 台账 `B7-REQ-6-27/6-28` 的最终主责按批准执行书 §17.2 明列的 B7-3 测试清单修正为
  B7-3；B7-2 只建立其 schema/descriptor 消费基础，不提前完成模型切换 red→green。

## 2. §5 硬切与契约门

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-5-01 | §5 | B7-2 | integration | `test_contract_version_gates_v2.gd::test_project_v1_rejected` | 当前 project v1 可打开 | 返回 unsupported_project_version 且不部分打开 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-02 | §5 | B7-2 | unit | 同文件 `test_graph_v1_rejected` | Graph 常量仍 v1 | 返回 unsupported_graph_version，无 alias | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-03 | §5 | B7-2 | unit | 同文件 `test_provider_v1_isolated_before_registration` | Provider v1 可注册 | 返回 unsupported_provider_api_version，列表/UI 不可见 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-04 | §5 | B7-2 | integration | 同文件 `test_plugin_v1_isolated_before_entry` | manifest/API v1 可加载 | 返回 unsupported_plugin_api_version，入口未执行 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-05 | §5 | B7-2 | unit | 同文件 `test_template_v1_rejected` | 模板仍 v1 | unsupported_template_version，不猜字段 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-06 | §5 | B7-2 | unit | 同文件 `test_clipboard_v1_rejected` | payload v1 仍接受 | unsupported_clipboard_version | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-07 | §5 | B7-2 | static | `test_legacy_adapter_contract.gd::test_no_v1_alias_or_migration` | 旧兼容入口存在 | 无 migration/alias；仅一个明确临时 generation v2 adapter | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-08 | §5 | B7-2 | unit | `test_plugin_api_v2.gd::test_registration_surface` | 仍注册 StylePreset | 删除 style，新增 prompt/cleanup，其余 v1 能力原样保留 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-09 | §5 | B7-2 | static | 同文件 `test_signature_is_not_api_v2_gate` | 基线文档已修；B7-2 防实现伪签名回归 | 无验签实现/信任声明，警告仍存在 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-10 | §5 | B7-2 | integration | `test_builtin_v2_fixtures.gd::test_all_default_resources_are_v2` | 内置 fixture/template/plugin 尚 v1 | 所有默认旅程资源直接为 v2 | `./pixel/scripts/run_tests.sh` |

## 3. §6 Graph、输入、Preset 与清洗数据

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-6-01 | §6 | B7-2 | unit | `test_graph_v2_schema.gd::test_main_path_whitelist_and_ports` | 仍有旧节点/端口 | 八节点、四类型和固定端口逐项相等 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-02 | §6 | B7-2 | unit | 同文件 `test_object_list_rows_only` | items 兼容仍在 | rows 身份/trim/count/enabled 规则，items 拒绝 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-03 | §6 | B7-2 | static | 同文件 `test_size_spec_removed_from_production` | size_spec 仍在生产注册/菜单/运行器 | 生产注册、菜单、模板、默认 fixture、运行器无残留；仅 v1 reject 与历史台账可提及 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-04 | §6 | B7-2 | unit | `test_prompt_preset_v1.gd::test_schema_and_six_exact_builtins` | 无 PromptPreset registry | 六个完整 prefix/name_key 逐字相等，无继承 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-05 | §6 | B7-2 | unit | 同文件 `test_prefix_only_and_name_xor` | Style 多领域字段仍可进入 | 只允许 prefix，内置/user 名称 XOR | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-06 | §6 | B7-2 | integration | `test_style_retirement_v2.gd::test_all_consumers_replaced` | manifest/Graph/controller/cleanup/catalog 仍读 Style | 各读取点按批准替代且独立工具保留 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-07 | §6 | B7-2 | roundtrip | `test_graph_v2_schema.gd::test_generate_params_roundtrip` | width/height 仍在 size_spec | ai_generate 七参数唯一持久化 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-08 | §6 | B7-3 | unit | `test_generation_request_planner.gd::test_prompt_order_and_999_limit` | 旧 prompt template/数量优先级 | prefix→text→row；999 前置拒绝且无预算/Output/请求 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-09 | §6 | B7-3 | unit | 同文件 `test_native_and_non_native_output_size` | target 与远端尺寸混用 | native 相等；non-native 整数比例选择并追加精确后缀 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-10 | §6 | B7-3 | unit | 同文件 `test_seed_capability_and_wrap_splitting` | seed 分片会重置/跨 wrap | 42→46、2147483647→0 断片、不支持 seed 不发送 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-11 | §6 | B7-3 | unit | 同文件 `test_extra_exact_descriptor_shape` | extra 宽松透传 | 缺失/未知/错类型拒绝，visible_when 只控发送 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-12 | §6 | B7-2 | unit | `test_cleanup_preset_v1.gd::test_schema_and_six_full_snapshots` | 无 CleanupPreset registry | 六预设全字段，HD-2D quantize=false，无继承 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-13 | §6 | B7-2 | unit | 同文件 `test_cleanup_settings_validator` | Style/pipeline 默认掩盖坏值 | 值域、共享 scale/offset、strength=contrast、base只读 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-14 | §6 | B7-6 | integration | `test_pixel_cleanup_node.gd::test_manual_policy_and_valid_sources` | cleanup 是检查器动作 | manual；只收 batch/image/reference；generate 直连拒绝 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-15 | §6 | B7-6 | unit | 同文件 `test_effective_target_is_derived_per_asset` | target 可能写入节点 | generated/cleaned/other 分别 target/继承/[0,0] | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-16 | §6 | B7-6 | unit | `test_cleanup_palette_snapshot.gd::test_palette_hash_and_freeze` | 运行时重读 registry | 点击时冻结有序 RGBA/hash，删除 registry 仍复现 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-17 | §6 | B7-2 | smoke | `test_cleanup_v2_shell.gd::test_shell_only_saves_settings_and_never_executes` | v2 壳可能沿用检查器直接执行 | B7-2 壳只保存完整 settings/Undo，pipeline/Output/Timer 调用为 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-18 | §6 | B7-2 | integration | `test_style_retirement_v2.gd::test_independent_tools_keep_existing_behaviors` | 既有绿色守护；防 Style 删除波及独立工具 | 逐个调用 editor/map/matting/slice/outline/palette 既有行为测试 | `./pixel/scripts/run_tests.sh` |

## 4. §7 Output、项目、模板、Clipboard 与引用

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-7-01 | §7 | B7-2 | unit | `test_output_slots_v2.gd::test_visible_projection` | batch 仍以 asset_ids 为真相 | 唯一投影为 succeeded&&!detached，顺序稳定 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-02 | §7 | B7-2 | roundtrip | `test_project_v2_roundtrip.gd::test_output_domain_lives_only_in_graph` | canvas 保存 review/batch 状态 | role/run/snapshots/records/slots 只在 Graph | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-03 | §7 | B7-4 | integration | `test_generation_run_coordinator.gd::test_atomic_pending_output_creation` | 旧控制器只写终态 | 网络前原子新 Output+slots+edge；排队失败完整回滚 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-04 | §7 | B7-4 | integration | 同文件 `test_full_run_preserves_history_output` | 新运行覆盖旧 batch | 旧 current→history，新 current 唯一，旧下游保留 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-05 | §7 | B7-4 | integration | 同文件 `test_retry_reuses_slots_and_latest_run_scope` | retry 可能建新卡/误算旧槽 | 同 Output 新 run；进度看最新 run，内容聚合全部当前槽 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-06 | §7 | B7-4 | unit | `test_output_auto_placement.gd::test_right_side_scan_never_moves_existing` | 旧布局可能重排 | 80 间距、向下扫描、旧卡不动 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-07 | §7 | B7-5 | unit | `test_output_slot_grid.gd::test_stable_slots_all_statuses` | 旧 placeholder/asset 数组跳位 | queued/running/success/failed/canceled 均稳定占槽 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-08 | §7 | B7-2 | roundtrip | `test_project_v2_roundtrip.gd::test_manifest_identity_and_no_global_style` | manifest 无 id/有 style | New 新 UUID；Save/Save As 保持；无全局 preset | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-09 | §7 | B7-2 | roundtrip | 同文件 `test_generation_provenance_exact_nesting` | snapshot 字段混位/重读节点 | 安全输入+actual 完整往返，ref id/SHA 同序 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-10 | §7 | B7-6 | roundtrip | 同文件 `test_cleanup_provenance_and_report` | cleanup report 不完整 | 完整来源/settings/palette/report/parent 往返 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-11 | §7 | B7-2 | unit | `test_asset_reference_contract_v2.gd::test_generation_live_and_history_scanner` | generation history 可被当 orphan | sprite/input/reference/result slot/generation ref 的 live/history 均保留字节 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-12 | §7 | B7-4 | integration | `test_crash_recovery_v2.gd::test_all_stale_slots_and_records_converge` | queued/running 重开仍 busy | 原子 interrupted；不启动网络/worker/弹框 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-13 | §7 | B7-2 | unit | `test_workflow_template_v2.gd::test_exact_whitelist_and_empty_batch` | 模板 v1/含运行状态 | 八节点参数白名单；batch 强制 standalone 空状态 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-14 | §7 | B7-2 | unit | 同文件 `test_palette_requirements_save_and_insert` | 模板不校验 palette hash | 排序唯一；缺失/不符原子拒绝，不含 colors/fallback | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-15 | §7 | B7-2 | integration | 同文件 `test_four_builtin_templates_v2` | 旧模板含 size/style/output | 四模板准确连接；不预建 Output；cleanup 未连接 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-16 | §7 | B7-2 | roundtrip | `test_clipboard_v2.gd::test_origin_project_identity_gate` | v2 payload 无稳定项目身份 | origin_project_id 必填；只允许同 manifest.id，跨项目拒绝 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-17 | §7 | B7-5 | roundtrip | 同文件 `test_terminal_output_pastes_as_pure_assets` | 复制保留 retry 身份 | 只成功可见槽；新 standalone 清空所有运行字段 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-18 | §7 | B7-5 | integration | `test_detach_output_asset_command.gd::test_detach_undo_redo_same_ids` | 旧 split/export 非领域命令 | detached+sprite+三元组原子，Undo/Redo 不复制位图 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-19 | §7 | B7-5 | integration | `test_output_source_delete_command.gd::test_busy_and_terminal_delete_undo` | 删除来源会丢结果/双 current | busy 拒绝；终态变 standalone；Undo 恢复合法 role/edge | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-20 | §7 | B7-5 | integration | 同文件 `test_output_delete_undo_conflict` | 恢复可能产生第二 current | 来源已有 current 时仅恢复 history | `./pixel/scripts/run_tests.sh` |

## 5. §8 Provider API、安全、状态与费用

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-8-01 | §8 | B7-1 | unit | `test_generation_http_security_v2.gd::test_header_redaction_case_and_space` | X-RD-Token 变体可能泄漏 | token/secret/cookie/auth 任意大小写与空格均 REDACTED | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-02 | §8 | B7-1 | integration | 同文件 `test_generation_post_never_retries` | 共享 HTTP retry 会重发 POST | timeout/network/429/5xx 请求数均 1 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-03 | §8 | B7-1 | unit | 同文件 `test_safe_get_retry_scheduler` | Retry-After 用真实等待/错误 clamp | fake UTC/mono；整数/HTTP-date/0.25..30/0.5,1.0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-04 | §8 | B7-1 | integration | `test_sensitive_payload_guard_v2.gd::test_sentinel_only_reaches_transport` | 无统一敏感扫描 | transport 收到；log/task/error/持久面均找不到 sentinel | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-05 | §8 | B7-1 | integration | `test_provider_config_v2.gd::test_retro_save_is_offline` | Retro 用假生成验证 | 保存/打开请求数 0；首次网络仅用户生成 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-06 | §8 | B7-2 | unit | `test_provider_task_v2.gd::test_deferred_start_and_exactly_one_terminal` | 旧 PFTask 可同步发信号 | 返回后订阅；progress 后恰一终态；迟到忽略 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-07 | §8 | B7-3 | unit | `test_cancel_task_v2.gd::test_cancel_order_deadlines_and_dedupe` | cancel void 无证明 | 同 wrapper；5s settle/3s remote；固定信号顺序 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-08 | §8 | B7-3 | unit | `test_provider_progress_v2.gd::test_exact_shape_and_monotonicity` | 旧 progress 字段/伪百分比 | phase/ratio/items 精确；run 聚合不倒退 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-09 | §8 | B7-3 | unit | `test_provider_result_v2.gd::test_item_normalization_matrix` | 坏图会压缩/静默缩放 | 连续 index、少/多/坏尺寸/单项错准确归一化 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-10 | §8 | B7-3 | unit | `test_pf_error_v2.gd::test_exact_safe_shape` | error 有 message/detail/raw body | 固定键/码/stage/范围；额外键拒绝 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-11 | §8 | B7-3 | unit | `test_generation_request_planner.gd::test_retry_groups_only_compatible_slots` | retry 重发成功分片 | 只失败槽；row/snapshot/seed 连续才合并 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-12 | §8 | B7-3 | unit | `test_cost_service_v2.gd::test_decimal_and_record_once` | float/重复回调重复计费 | micro USD；0.1+0.2=0.3；charge/request 去重 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-13 | §8 | B7-3 | unit | 同文件 `test_estimate_actual_unknown_and_budget_matrix` | unknown 冒充 0/错误入 ledger | unknown/null、rd_pro 精确、blocked/confirm reason 完整 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-14 | §8 | B7-3 | integration | `test_provider_config_v2.gd::test_single_data_path_and_five_states` | 多套设置入口 | Dialog→Service→CredentialStore；删除凭据清内存/verified | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-15 | §8 | B7-3 | unit | 同文件 `test_exact_config_schema` | text/raw label/未知键可注册 | 只 string/password/bool/enum 精确 shape，password 不回填 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-16 | §8 | B7-3 | unit | `test_provider_descriptors_v2.gd::test_four_exact_models` | descriptor 不完整/多 default | 四 model capabilities/meta/dynamic params 逐项相等 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-17 | §8 | B7-3 | integration | `test_openai_provider_v2.gd::test_mock_transport_contract` | OpenAI 仍用旧 request/result | mock 覆盖 txt/img、尺寸、quality、无隐藏 prompt/重试 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-18 | §8 | B7-3 | integration | `test_retrodiffusion_provider_v2.gd::test_mock_transport_contract` | Retro 仍用旧 seed/style | mock 覆盖 seed/remove_bg/strength/费用/取消 | `./pixel/scripts/run_tests.sh` |

## 6. §9 生成与清洗结构卡

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-9-01 | §9 | B7-4 | smoke | `test_generation_card_v2.gd::test_exact_six_groups_and_fixed_regions` | 旧检查器/卡字段分散 | 六组顺序准确，Header/status/Footer 固定，只有正文滚动 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-02 | §9 | B7-4 | smoke | 同文件 `test_prompt_preview_rows_and_suffix` | 预览不等于实际发送 | 单 prompt/首行/展开列表精确，不复制 count 行 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-03 | §9 | B7-4 | smoke | 同文件 `test_footer_state_actions` | 点击到终态多套状态 | Queued/Running/Canceling/各终态按钮精确 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-04 | §9 | B7-6 | smoke | `test_cleanup_card_ui.gd::test_all_existing_controls_and_enablement` | 新卡可能漏检查器能力 | preset+全部值域/启用矩阵；base 只读 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-05 | §9 | B7-6 | smoke | 同文件 `test_footer_is_only_execution_entry` | 检查器/批次仍直接清洗 | 只有 Footer 调协调器；旧直接入口为 0 | `./pixel/scripts/run_tests.sh` |

## 7. §10 Output 最终 UI

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-10-01 | §10 | B7-5 | geometry | `test_output_layout_calculator.gd::test_width_count_matrix` | 旧卡无限增高/5列 | 0/1/2/4/5/12/13/50 × 360/600/960；≤4列≤3行 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-02 | §10 | B7-5 | geometry | 同文件 `test_single_slot_aspect_viewport` | 单图仍按固定 tile | 横/竖/方精确 176..420 视口 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-03 | §10 | B7-5 | unit | `test_output_slot_grid.gd::test_internal_scroll_and_hit_mapping` | 旧卡无滚动 | 13/50 滚动、第四行/末项命中真实 slot | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-04 | §10 | B7-5 | unit | 同文件 `test_refill_does_not_reset_scroll` | 回填会跳回顶部 | slot 更新后 scroll 保持，端口同帧更新 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-05 | §10 | B7-5 | unit | `test_output_selection_toolbar.gd::test_selection_and_pointer_cancel` | 旧 Review 状态持久化 | 临时选择、Esc/pointer cancel、浮动动作不写 Graph | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-06 | §10 | B7-5 | smoke | `test_output_card_controller.gd::test_state_tiles_and_empty_reason` | failed/canceled 被当空 | 全状态 tile；仅无 slots/全成功 detached 才空 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-07 | §10 | B7-5 | smoke | 同文件 `test_busy_action_gate_and_terminal_actions` | busy 仍可改变关系 | busy 只选/预览/下载成功；终态恢复动作 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-08 | §10 | B7-5 | integration | `test_detach_output_asset_command.gd::test_single_all_restore_and_locate` | 旧 split/export 语义冲突 | 单/全部/恢复/定位按 sprite 存在性唯一分支 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-09 | §10 | B7-5 | static | `test_output_legacy_removal.gd::test_review_filter_compare_exports_removed` | 旧 Review 代码测试残留 | §10.7 所列旧行为与字段全部为 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-10 | §10 | B7-5 | static | 同文件 `test_fixed_responsibility_files_exist` | canvas_batch_card 继续膨胀 | 五个固定职责文件存在且无跨层 writer | `./pixel/scripts/run_tests.sh` |

## 8. §11 连线状态机

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-11-01 | §11 | B7-4 | unit | `test_run_edge_state.gd::test_idle_queued_running_canceling_terminal` | 旧线动画与任务状态脱节 | 每种 run 状态映射准确，history 不进执行 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-02 | §11 | B7-4 | unit | 同文件 `test_concurrent_runs_are_isolated` | 全局动画串 run | 每 edge 只订阅所属 run/source | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-03 | §11 | B7-4 | unit | 同文件 `test_idle_stops_tick` | idle 仍每帧 tick | 终态/idle 停止动画更新与 Timer | `./pixel/scripts/run_tests.sh` |

## 9. §12 错误弹窗

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-12-01 | §12 | B7-4 | integration | `test_generation_error_dialog.gd::test_at_most_one_per_run` | 分片各弹一次 | 每 run 最多一个，对应失败集合和安全摘要 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-02 | §12 | B7-4 | unit | 同文件 `test_error_action_matrix` | error code 无确定动作 | §8.4/8.5 每码双语文案与按钮精确 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-03 | §12 | B7-4 | integration | 同文件 `test_dialog_never_contains_sensitive_payload` | detail 可能带 prompt/header | sentinel/prompt/body/image 均不可见 | `./pixel/scripts/run_tests.sh` |

## 10. §13 内置实例

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-13-01 | §13 | B7-7 | unit | `test_example_builder_v2.gd::test_default_graph_and_reserved_output_lane` | 示例拥挤且含 object list/旧节点 | text 默认；可选 preset/reference；无 Output；cleanup 未连接 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-02 | §13 | B7-7 | geometry | 同文件 `test_effective_bounds_spacing_and_routes` | 卡片/边重叠 | 有效 bounds 不交叠、80 间距、边路由清晰、Fit All | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-03 | §13 | B7-7 | integration | 同文件 `test_example_is_one_undo_and_does_not_touch_user_projects` | builder 逐项污染 Undo/现有项目 | 一次 Undo/Redo；仅新示例，不改已打开项目坐标 | `./pixel/scripts/run_tests.sh` |

## 11. §14 粘滞平移

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-14-01 | §14 | B7-7 | unit | `test_canvas_navigation_input.gd::test_middle_button_lifecycle` | 基线绿色矩阵守护；防统一状态机回归 | 中键 press/move/release 精确收敛 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-02 | §14 | B7-7 | unit | 同文件 `test_pan_records_originating_button_mask` | 只记录 Space 当前态 | gesture 保存发起按钮 mask，不靠 Timer/下一击 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-03 | §14 | B7-7 | unit | 同文件 `test_button_mask_zero_recovers` | 系统漏 release | button_mask=0 强制收敛 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-04 | §14 | B7-7 | unit | 同文件 `test_focus_loss_cancels_all_pointer_gestures` | 失焦保留按下态 | focus loss 复位，回到画布不移动 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-05 | §14 | B7-7 | unit | 同文件 `test_text_input_space_is_not_pan` | 文本 Space 被全局捕获 | 文本框正常输入空格且不平移 | `./pixel/scripts/run_tests.sh` |

## 12. §15 i18n 架构

| ID | 原文引用 | Owner | 类型 | 测试文件 / 测试名 | 真实红灯原因 | 绿色断言 | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-15-01 | §15 | B7-2 | unit | `test_schema_text_resolver.gd::test_schema_registration_requires_bilingual_keys` | schema 有 raw label/动态访问 | key 双语非空；所有注册经 resolver | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-02 | §15 | B7-8 | static | `test_i18n_source_guard_v2.gd::test_no_direct_catalog_or_production_literals` | 历史常量/白名单存在 | 直接访问为 0，只有 resolver 动态访问，无白名单 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-03 | §15 | B7-8 | integration | `test_runtime_language_switch_v2.gd::test_en_zh_en_all_surfaces` | 旧 UI 不刷新/新卡漏 key | 主窗/菜单/cards/settings/error/example/tooltip 两次刷新 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-04 | §15 | B7-8 | geometry | `test_i18n_geometry_matrix_v2.gd::test_eighteen_cases` | 中文/scale 下重叠裁切 | 2 locale×3 window×3 scale 无重叠/截断/越界/端口错位 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-05 | §15 | B7-8 | unit | `test_schema_text_resolver.gd::test_missing_or_empty_key_fails` | 缺 key 静默回退 raw code | 任一语言缺失/空值即注册失败 | `./pixel/scripts/run_tests.sh` |

## 13. 原文定位与原子要求补表

前述表的原文定位由其所在 `§5` 至 `§15` 小节标题和 green 断言中的字段/公式名共同
确定；下表继续拆开独立失败面，并显式列出批准计划的原文小节、表格行或公式。相同
参数化测试可以承担多个独立 case，但每个 ID 只对应一个可单独失败的规范。

| ID | 原文/表格行/公式引用 | Owner | 类型 | 测试文件 :: 测试名 | Red | Green | 命令 |
|---|---|---|---|---|---|---|---|
| B7-REQ-5-11 | §5.2 八份契约清单 | B7-2 | static | `test_contract_documents_align_v2::test_eight_contracts_exist_and_align` | 实现常量可能偏离契约 | 八文件、实现版本、字段和错误码交叉一致 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-12 | §5.1 “错误必须本地化…请新建项目” | B7-2 | i18n | `test_contract_version_gates_v2::test_unsupported_errors_are_bilingual_safe` | 只显示裸 code | 六类拒绝均双语、无崩溃/裸 code | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-13 | §5.1 Plugin v2 非签名版本 | B7-2 | smoke | `test_plugin_api_v2::test_unverified_plugin_warning_survives_v2` | v2 被误标可信 | 安装仍显示“可执行任意代码，只安装可信来源” | `./pixel/scripts/run_tests.sh` |
| B7-REQ-5-14 | §5.1 “其余 v1 注册能力原样保留” | B7-2 | unit | `test_plugin_api_v2::test_each_unrelated_registration_survives` | 无关注册被误删 | node/provider/pipeline/palette/menu/exporter 逐项存在 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-19 | §6.1 batch 显示名规则 | B7-2 | i18n | `test_graph_v2_schema::test_batch_display_name_and_no_output_alias` | 注册 output 同义类型/裸名 | 内部仅 batch；en Output、zh 结果 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-20 | §6.1 非主路径保留/延期列表 | B7-2 | static | `test_graph_v2_schema::test_non_main_nodes_are_classified` | 既有能力被删或延期节点被补做 | 已实现能力保留；七延期类型不注册 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-21 | §6.1 image/reference asset_list 解析段 | B7-3 | integration | `test_generation_request_planner::test_reference_assets_resolve_rgba8_ids_hashes_in_order` | 顺序/格式/SHA 漂移 | 1 与 0..max 条 RGBA8、id、SHA、ref_images 同序 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-22 | §6.1 “Provider 不能接触 Graph asset id” | B7-3 | static | `test_generation_request_planner::test_provider_only_receives_ref_images` | Provider 收到 Graph id | PFGenRequest 仅 ref_images，不含 asset ids | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-23 | §6.2 object_list 六条固定规则 | B7-2 | unit | `test_graph_v2_schema::test_object_row_validation_matrix` | rows 宽松/降成字符串 | id 唯一、trim、1..999、enabled、严格三字段逐 case | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-24 | §6.2 “不是默认演示入口” | B7-7 | integration | `test_example_builder_v2::test_object_list_only_menu_and_batch_template` | 默认示例含 object_list | 只添加菜单与批量模板包含 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-25 | §6.4 PromptPreset 禁止字段列表 | B7-2 | unit | `test_prompt_preset_v1::test_rejects_negative_template_and_multidomain_fields` | 旧 Style 字段可混入 | 禁止字段逐项拒绝；prefix 不解释占位符 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-26 | §6.4 名称/默认/2B 尺寸段 | B7-2 | i18n | `test_prompt_preset_v1::test_name_modes_default_and_canvas_contract` | 名称/默认/尺寸走旧逻辑 | name XOR、默认资源、320×280/280×220/1600×1200、Undo | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-27 | §6.5 descriptor 默认写入规则；批准执行书 §17.2 B7-3 测试清单 | B7-3 | unit | `test_graph_v2_schema::test_new_generate_writes_descriptor_defaults` | 新节点靠运行时 fallback | provider/default model/-1/全部 extra defaults 入 params | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-28 | §6.5 provider/model 切换段；批准执行书 §17.2 B7-3 测试清单 | B7-3 | unit | `test_graph_v2_schema::test_model_switch_one_undo_rebuilds_extra` | 旧 extra 串模型 | 单 Undo 整体重建，保留 target/batch/seed | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-29 | §6.5 本地预检与 MAX_RESULTS=999 | B7-3 | unit | `test_generation_request_planner::test_all_local_validation_precedes_side_effects` | 坏输入仍预算/建卡/请求 | 尺寸、prompt、refs、provider/model、999 均副作用 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-30 | §6.5 rows 数量与提示词预览段 | B7-4 | smoke | `test_generation_card_v2::test_rows_hide_batch_and_preview_first_expand` | batch 可编辑/预览复制 999 条 | 数量只读，N 行/M 张，有序逐行一条 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-31 | §6.5 provider_output_sizes 选择段 | B7-3 | unit | `test_generation_request_planner::test_output_size_tiebreak_and_no_resample` | tie/缩放行为错误 | 比率误差最小、tie 取前、生成不缩放 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-32 | §6.5 seed 快照/重试/actual 段 | B7-3 | roundtrip | `test_generation_request_planner::test_requested_actual_seed_per_slot` | requested 冒充 actual/重试换 seed | 原 seed retry；actual 仅 Provider/null；随机逐槽 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-33 | §6.6 三类合法来源字段 | B7-6 | unit | `test_pixel_cleanup_node::test_source_projection_and_conditional_fields` | 伪造 batch/slot 或含 detached | batch 只可见成功并写槽；image/reference 留空 batch/slot | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-34 | §6.6 输入数量 1..999 | B7-6 | unit | `test_pixel_cleanup_node::test_zero_and_thousand_rejected_before_output` | 空/1000 项仍建 Output | 两边界 Output/worker 均 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-35 | §6.6 严格顺序/单并发/失败继续 | B7-6 | integration | `test_cleanup_run_coordinator::test_order_single_concurrency_and_operation_records` | 并发/失败中断后续 | 有序单 worker；每项 record 无 partial；失败继续 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-36 | §6.7 选择/编辑 preset 规则 | B7-6 | unit | `test_cleanup_preset_v1::test_copy_then_edit_clears_id` | 执行时重读 preset | 选择复制全量；编辑清 id；默认 cleanup-16bit-db32 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-37 | §6.6 设置值域表 | B7-6 | unit | `test_cleanup_preset_v1::test_control_value_ranges_exact` | validator 接受边界外/两套值 | 每个 enum/range/共享不变量参数化通过/拒绝 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-38 | §6.6 “普通 Graph Run…Ready” | B7-6 | integration | `test_pixel_cleanup_node::test_graph_run_stops_ready_without_pipeline` | 自动执行 cleanup | 普通 Run pipeline/Output/Timer 计数 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-39 | §6.6 Footer 唯一执行入口 | B7-6 | smoke | `test_cleanup_card_ui::test_footer_is_only_execution_entry` | inspector/菜单仍直接调用 | 只有 Footer 调统一协调器 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-40 | §6.6 cleanup history scanner 扩展 | B7-6 | roundtrip | `test_asset_reference_contract_v2::test_cleanup_parent_palette_report_history` | parent/source 被 orphan | cleanup parent/source/snapshot 在保存清理中保留 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-21 | §7.1 result_slots JSON 与 record shape | B7-2 | unit | `test_output_slots_v2::test_slot_snapshot_record_exact_shapes` | 必填/状态/费用字段宽松 | exact keys、UUID、state、attempt/count/meta/cost 逐项校验 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-22 | §7.1 少/多返回规则 | B7-3 | unit | `test_provider_result_v2::test_expected_unexpected_slot_mapping` | 少槽消失/多失败建槽 | 少返回 failed；多成功 unexpected；多失败仅诊断 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-23 | §7.2 最新 run 与内容聚合优先级 | B7-4 | unit | `test_generation_run_coordinator::test_retry_run_terminal_priority` | 旧成功误算新进度/取消被覆盖 | cancel_failed>canceled>全槽聚合，进度只最新 run | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-24 | §7.3 batch 无输入语义 | B7-2 | unit | `test_output_slots_v2::test_batch_without_input_outputs_visible_slots` | history 断边后失效 | 无输入仍输出成功可见槽，history 有效 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-25 | §7.2 busy 动作表 | B7-4 | integration | `test_generation_run_coordinator::test_busy_domain_and_undo_gate` | UI gate 可绕过 domain | copy/delete/detach/edit/Undo 拒绝；预览下载允许 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-26 | §7.2 retry 身份规则 | B7-4 | unit | `test_generation_run_coordinator::test_retry_ids_and_non_targets` | retry 重建 Output/改成功槽 | 新 run/request；仅目标 queued；其他身份/detached 不变 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-27 | §7.4 canvas graph node 正向字段 | B7-2 | roundtrip | `test_project_v2_roundtrip::test_canvas_keeps_only_display_fields` | 布局漏存/运行域复制 | title/size/collapsed/position/z 往返且无运行域 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-28 | §7.4 sprite origin 三元组 | B7-5 | roundtrip | `test_detach_output_asset_command::test_origin_triple_survives_source_delete` | 来源删后清空/部分三元组 | 三项同时存在，standalone/保存/复制不改 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-29 | §7.4 generation provenance JSON | B7-2 | roundtrip | `test_project_v2_roundtrip::test_generation_provenance_exact_fields` | 尺寸/seed/ref/extra 范围宽松 | 每字段范围、嵌套、安全键、同序逐项校验 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-30 | §7.4 cleanup report JSON | B7-6 | roundtrip | `test_project_v2_roundtrip::test_cleanup_report_exact_fields` | 空 settings/report 被当成功 | 必填尺寸/grid/steps/count/elapsed 与 target 规则 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-31 | §7.4 恢复步骤 1 | B7-4 | unit | `test_crash_recovery_v2::test_every_busy_slot_gets_interrupted_stage` | 部分 busy 漏改 | 每槽 error/stage/provider/request/count 正确 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-32 | §7.4 恢复步骤 2–3 | B7-4 | unit | `test_crash_recovery_v2::test_stale_record_and_source_matrix` | record/卡状态信旧文字 | received/state/cancel priority 全矩阵重算 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-33 | §7.4 恢复步骤 4 | B7-4 | integration | `test_crash_recovery_v2::test_recovery_nonundo_idle_no_execution_popup` | 重开恢复任务/弹框 | 非 Undo；edge idle；HTTP/worker/dialog 均 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-34 | §7.5 extra template_safe | B7-2 | unit | `test_workflow_template_v2::test_extra_only_template_safe` | 敏感/非模板参数保存 | 只 descriptor template_safe=true keys | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-35 | §7.6 节点 Clipboard 规则 | B7-2 | unit | `test_clipboard_v2::test_config_only_node_payloads` | 复制 run/target 派生值 | prompt snapshot/generate config/cleanup settings only | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-36 | §7.6 纯素材 Output slot shape | B7-5 | unit | `test_clipboard_v2::test_pasted_output_exact_slot_shape` | 粘贴保留 retry/unexpected | 新 id、空运行字段、实际 planned、success/nonunexpected | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-37 | §7.6 payload 禁止字段 | B7-2 | static | `test_clipboard_v2::test_forbids_task_request_progress_raw_headers_response` | 敏感运行字段进入 payload | 禁止字段递归扫描为 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-38 | §7.6 sprite Clipboard | B7-5 | roundtrip | `test_clipboard_v2::test_sprite_keeps_complete_origin_triple` | 未复制来源时清三元组 | 同项目复制完整保留，即使来源未复制 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-39 | §7.7 删除 detached sprite | B7-5 | integration | `test_detach_output_asset_command::test_delete_sprite_does_not_restore_slot` | 删除 sprite 隐式还槽 | detached 保持；删除 Undo 只恢复 sprite | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-40 | §7.9 删除 current/history 与 Undo 引用 | B7-5 | integration | `test_output_source_delete_command::test_delete_edges_and_undo_refs` | 删除卡误删 source/assets | 对应关系删除；source 保留；Undo 出栈前保留审计 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-19 | §8.1/8.3 身份与基础分片 | B7-3 | unit | `test_generation_request_planner::test_run_request_attempt_and_row_chunks` | 跨 row 合并/attempt 错 | `[4,1]`、不跨 row、排队0启动1 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-20 | §8.1 PFGenRequest JSON | B7-2 | unit | `test_provider_request_v2::test_exact_shape_mode_and_removed_fields` | 旧 style/ref/width 存在 | exact keys，txt/img mode，旧字段全拒绝 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-21 | §8.2 PFProvider 六方法/所有权 | B7-2 | static | `test_provider_task_v2::test_method_surface_and_ownership_boundary` | Provider 写 Graph/UI/ledger | 六方法精确；禁止依赖/调用逐项为 0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-22 | §8.3 submitting/attempt 转换 | B7-3 | unit | `test_provider_progress_v2::test_queue_submitting_attempt_once` | 排队发 progress/重复加 attempt | 首网络前恰一 submitting，首 HTTP 失败仍 attempt=1 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-23 | §8.2 PFCancelResult JSON | B7-3 | unit | `test_cancel_task_v2::test_result_shape_billing_null_known` | billing 混入图片/error | 四字段精确；null/known 安全分支与 record_once | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-24 | §8.3 run 状态机 | B7-4 | unit | `test_generation_run_coordinator::test_generation_state_transition_matrix` | 非法倒退/预检改 busy | 每条允许/拒绝转换；preflight Ready；queue error Failed | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-25 | §8.3 cancel cutoff | B7-4 | unit | `test_generation_run_coordinator::test_cancel_cutoff_and_late_callbacks` | cutoff 后仍落图/计费 | cutoff 前保留，后业务回调全忽略且不倒退 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-26 | §8.3 PFRunProgress 聚合 | B7-4 | unit | `test_generation_run_coordinator::test_run_progress_aggregation_matrix` | 分母变化/伪比例 | 固定槽分母、phase、确定条件、ratio单调、fake elapsed | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-27 | §8.4 PFError code/stage/range 表 | B7-3 | unit | `test_pf_error_v2::test_all_codes_stages_and_ranges` | 未知码/attempt 范围通过 | 每个 code/stage/null/range 参数化精确 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-28 | §8.4 非执行错误分类 | B7-3 | unit | `test_pf_error_v2::test_nonexecution_errors_have_no_attempts_message` | validation/load/command 伪装 PFError | 只 code/field/args，不含 attempts/message | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-29 | §8.3 已接受/未接受坏响应 | B7-3 | integration | `test_provider_result_v2::test_ambiguous_vs_retryable_malformed` | 坏 shape 自动重发 | accepted→ambiguous不可重试；可证明未接受→malformed可重试 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-30 | §8.5 三条人工路径 preflight | B7-3 | unit | `test_cost_service_v2::test_all_manual_retry_paths_preflight` | retry 绕过预算 | 单槽/失败批/完整都 preflight；blocked/cancel 副作用0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-31 | §8.5 slot 动作表 | B7-4 | unit | `test_generation_error_dialog::test_slot_action_retry_matrix` | action 猜 last error | wait/retry/settings/prompt/card/re-generate 按固定优先级 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-32 | §8.7 actual/charge/meta/ledger | B7-3 | unit | `test_cost_service_v2::test_actual_charge_meta_and_unknown_ledger` | unknown/failed 入月账或 meta 宽松 | actual only、白名单、去重、unknown不入账 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-33 | §8.3 多 request cancel wrappers | B7-3 | unit | `test_cancel_task_v2::test_multi_request_wrappers_all_settle` | 一项完成就提前结束等待 | wrapper 集合只在全部 resolved/rejected 后发领域事件 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-34 | §8.2 queued/remote cancel 分支 | B7-3 | unit | `test_cancel_task_v2::test_queued_and_remote_timeout_branches` | queued 调 Provider/remote timeout reject | queued resolved true 无 Provider；已停 remote timeout resolved false | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-35 | §8 范围与 mock 要求 | B7-3 | integration | `test_provider_scope_v2::test_only_mock_openai_retro_no_paid_endpoint` | 测试触达真实/扩 Comfy | 仅 mock/录制 OpenAI+Retro，其他后端不注册 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-06 | §9.1 生成卡固定尺寸 | B7-4 | geometry | `test_generation_card_v2::test_fixed_bounds_and_scroll_regions` | 卡内全滚/尺寸漂移 | 400×520、min360×400、max1600×1200、header40/footer56，仅正文滚 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-07 | §9.1 输入摘要行为 | B7-4 | smoke | `test_generation_card_v2::test_input_summary_jumps_upstream_only` | 卡内复制上游编辑器 | 点击跳上游，不复制编辑文本 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-08 | §9.1 动态参数组 | B7-4 | smoke | `test_generation_card_v2::test_descriptor_params_advanced_and_seed_visibility` | 硬编码/不支持字段可见 | 只 schema 字段；Advanced 默认折叠；能力不支持即不显示 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-09 | §9.1 Footer 条件表/优先级 | B7-4 | unit | `test_generation_card_v2::test_footer_error_priority_and_preflight_routes` | 动作按 last error 猜 | cancel_failed>auth/quota>policy>invalid>ambiguous>internal，Retry/new Output 正确 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-10 | §9.2 清洗卡固定尺寸 | B7-6 | geometry | `test_cleanup_card_ui::test_fixed_bounds_and_scroll_regions` | 固定区随正文滚 | 420×680、min360×480、max800×1000、header40/status32/footer56 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-11 | §9.2 输入摘要组 | B7-6 | smoke | `test_cleanup_card_ui::test_input_summary_validation_and_jump` | 无效来源仍可开始 | 三类来源/数量/target；缺失/空/坏素材内联拒绝；可跳来源 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-12 | §9.2 网格/重采样/量化启用矩阵 | B7-6 | smoke | `test_cleanup_card_ui::test_control_enablement_matrices` | disabled 控件折叠/两份共享值 | 全矩阵参数化，可见不跳布局，共享 scale/strength 双写 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-13 | §9.2 上次报告组 | B7-6 | smoke | `test_cleanup_card_ui::test_report_collapsed_and_contains_no_action` | 报告组可再次执行 | 默认折叠、固定摘要字段、无按钮/不改 settings | `./pixel/scripts/run_tests.sh` |
| B7-REQ-9-14 | §9.2 点击快照规则 | B7-6 | integration | `test_cleanup_run_coordinator::test_click_freezes_inputs_settings_and_disables_edits` | 运行中读取可变控件 | 点击一次冻结，运行中编辑禁用 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-11 | §10.2 overlay scrollbar | B7-5 | geometry | `test_output_layout_calculator::test_scrollbar_4_visual_12_hit_no_reflow` | 滚动条占宽导致 tile 跳 | 4px 视觉/12px 命中，列和 tile 不变 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-12 | §10.2 2B 高度/自然尺寸段 | B7-5 | geometry | `test_output_layout_calculator::test_height_ranges_partial_row_natural_reset` | 缩放恢复第四行/旧 Review | n0/1/multi 范围、半行提示、双击自然、折叠三字段 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-13 | §10.3 顶轨六项顺序 | B7-5 | smoke | `test_output_card_controller::test_top_rail_exact_order_and_history` | 顶轨混入清洗/历史覆盖终态 | title→count→state/history→download→detach→port | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-14 | §10.4 滚轮传播 | B7-5 | unit | `test_output_slot_grid::test_wheel_boundary_and_zoom_modifier_priority` | 网格滚轮总劫持 canvas | 网格先滚，边界传播，zoom modifier 优先 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-15 | §10.5 pending 原位回填 | B7-5 | unit | `test_output_slot_grid::test_out_of_order_results_keep_slot_order` | 回调顺序重排 UI | 五状态原槽回填，混合不重排 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-16 | §10.6 工具条顺序/可见性 | B7-5 | smoke | `test_output_selection_toolbar::test_exact_order_only_succeeded` | 失败槽出现图片动作 | Preview/Edit/Detach/Download；仅 succeeded | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-17 | §10.6 拖出八步骤 | B7-5 | integration | `test_detach_output_asset_command::test_drag_threshold_identity_and_cancel_paths` | 复制 bitmap/取消未恢复 | 8px、同 asset、三元组、一 Undo、三种取消完整恢复 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-18 | §10.6 拆出全部规则 | B7-5 | integration | `test_detach_output_asset_command::test_all_layout_confirmation_and_last_slot` | 包含失败/顺序乱/删容器 | 仅成功可见、≤4列/24gap/保序/>12确认/最后一张保留 Output | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-19 | §10.5 Retry 五项前置 | B7-5 | unit | `test_output_card_controller::test_retry_visibility_all_preconditions` | standalone/坏来源仍 Retry | role/source id+type/snapshot/wait 全满足；三处一致隐藏 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-20 | §7.1/§10 下载拆出下游投影 | B7-5 | unit | `test_output_card_controller::test_all_consumers_use_succeeded_visible_projection` | detached/失败进入消费 | download/detach/downstream 同一唯一投影 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-21 | §10.2 空态定位/恢复 | B7-5 | integration | `test_detach_output_asset_command::test_empty_locate_vs_restore_undo` | 全删后仍定位/复制图 | 存在 sprite 只定位；全删只恢复 slots+focus，一 Undo；混合定位 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-10-22 | §10.7 逐项删除清单 | B7-5 | static | `test_output_legacy_removal::test_exact_legacy_symbols_fields_menus_are_absent` | 旧 Review/Compare/batch_card 复活 | 枚举的 symbol/JSON key/menu/test 均 absent，保留能力仍测 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-04 | §11 Clock 注入 | B7-4 | static | `test_run_edge_state::test_clock_injected_and_no_wall_clock` | renderer 直接读 wall time | 协调器/renderer 都注入 Clock；截图 fake phase 确定 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-05 | §11 终态保持时间表 | B7-4 | unit | `test_run_edge_state::test_terminal_hold_durations` | 终态永不/立即消失 | 800/1200/1200/400ms 后精确 idle | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-06 | §11 视觉固定值 | B7-4 | geometry+manual | `test_run_edge_state::test_exact_visual_tokens_and_speed` | 线宽/dash/速度不符 | 2、8/.28、2.5、14/10、90px/s 结构自动断言；最终手感留人工签收 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-07 | §11 Canceling/终态视觉序列 | B7-4 | unit | `test_run_edge_state::test_cancel_partial_failed_canceled_sequences` | 取消仍成功推进/双状态 | warning/单琥珀/单红/灰淡出，互斥 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-11-08 | §11 低 LOD/几何不变量 | B7-4 | geometry | `test_run_edge_state::test_low_lod_dot_and_no_geometry_mutation` | 动画改命中/bounds | 10/25% 单点；端点/命中/相机/bounds 不变 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-04 | §12.1 四类不弹框 | B7-4 | integration | `test_generation_error_dialog::test_no_dialog_preflight_retrying_cancel_or_recovery` | 本地错/取消/恢复打断用户 | 四分支 dialog count=0，内联/slot 反馈存在 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-05 | §12.2 终态五步顺序 | B7-4 | unit | `test_generation_error_dialog::test_update_order_before_dialog` | 先弹框再写安全状态 | edge停→保成功→fail槽→PFError→一次 dialog | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-06 | §12.2 弹框七部分 | B7-4 | smoke | `test_generation_error_dialog::test_exact_content_and_technical_allowlist` | 详情含 raw/provider 英文 | 七部分齐；详情只 code/provider/脱敏 request id | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-07 | §12.2 Partial 汇总/Retry | B7-4 | unit | `test_generation_error_dialog::test_partial_summary_and_retryable_rules` | 分片未终态就弹/重试不可重试槽 | 全 settle 一次；计数准确；只 retryable 目标 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-12-08 | §12 PFError 双语静态映射表 | B7-4 | i18n | `test_generation_error_dialog::test_every_pferror_code_has_static_en_zh` | code 显示裸 English | B7-4 当卡加入每个固定 code 两语 key/placeholder | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-04 | §13.1 普通运行语义 | B7-7 | integration | `test_example_builder_v2::test_mock_output_then_manual_cleanup_output` | 示例专用自动连/清洗 | Output 入预留带；用户手连/点击；cleaned 右侧；旧卡不动 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-05 | §13.2 精确布局公式 | B7-7 | geometry | `test_example_builder_v2::test_columns_center_gap_reservation_no_old_offsets` | 沿用150/280固定偏移 | effective bottom/right+80、垂直中心、600+80带精确 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-06 | §13.3 Fit All | B7-7 | smoke | `test_example_builder_v2::test_1280_fit_all_lod_at_least_25` | 首屏裁切/过低 LOD | 1280×720 完整可见且≥25% | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-07 | §13.3 i18n | B7-7 | i18n | `test_example_builder_v2::test_names_titles_descriptions_prompts_are_keys` | 示例裸 English | 全部集中 key 且双语刷新 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-13-08 | §13 “不得新增外部 PNG” | B7-7 | static | `test_example_builder_v2::test_uses_only_programmatic_placeholder` | 基线绿色守护；防回归 | 示例不引用/新增 PNG，只程序生成测试占位 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-06 | §14 鼠标离开窗口 | B7-7 | unit | `test_canvas_navigation_input::test_mouse_leave_cancels_all_gestures` | leave 后仍平移 | 全 pointer state 清零 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-07 | §14 场景退出 | B7-7 | unit | `test_canvas_navigation_input::test_scene_exit_cancels_all_gestures` | 新场景继承按下态 | exit 清全部 gesture | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-08 | §14 左键先释放序列 | B7-7 | unit | `test_canvas_navigation_input::test_space_left_then_left_release` | release 分支依赖 Space | 无条件结束左键 gesture | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-09 | §14 Space 先释放序列 | B7-7 | unit | `test_canvas_navigation_input::test_space_release_then_left_release` | 已知粘滞根因 | 后续 left release 清 `_is_panning` | `./pixel/scripts/run_tests.sh` |
| B7-REQ-14-10 | §14 模态弹出 | B7-7 | unit | `test_canvas_navigation_input::test_modal_open_cancels_all_pointer_gestures` | 模态后背景仍平移 | 弹出前全 gesture 清零 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-06 | §15 strings.gd 最终要求 | B7-8 | static | `test_i18n_source_guard_v2::test_strings_only_text_entry_no_visible_constants` | 约460行常量仍在 | 仅 text(key,args) 兼容入口 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-07 | §15 守护 1 | B7-8 | static | `test_i18n_source_guard_v2::test_no_uppercase_const_access` | 23+生产文件直接访问 | production 访问为0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-08 | §15 守护 2 | B7-8 | static | `test_i18n_source_guard_v2::test_no_ui_property_english_literal` | UI 属性裸 English | 结构规则拒绝 text/title/dialog/tooltip/placeholder literal | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-09 | §15 守护 3 | B7-8 | static | `test_i18n_source_guard_v2::test_no_raw_schema_label_help_description` | schema 仍有 raw 文案 | schema 只 `*_key` | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-10 | §15 守护 4 | B7-8 | static | `test_i18n_source_guard_v2::test_business_translation_keys_are_literals` | 动态 key 绕过 catalog | resolver 外 Strings/Localization 参数均字面量 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-11 | §15 守护 5 | B7-8 | static | `test_i18n_source_guard_v2::test_catalog_missing_empty_placeholder_order` | 现有仅部分绿色 guard | 任一缺失/空/placeholder 顺序差异失败 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-12 | §15 动态状态静态映射 | B7-8 | static | `test_i18n_source_guard_v2::test_dynamic_states_use_static_key_maps` | 业务拼 dynamic key | run/error 状态只显式 map | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-13 | §15 数据不存渲染语言 | B7-8 | roundtrip | `test_runtime_language_switch_v2::test_data_stores_code_args_only` | 语言切换后历史冻结旧语言 | error/state/project/provenance 只 code+args | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-14 | §15 resolver 唯一动态入口 | B7-8 | unit | `test_schema_text_resolver::test_only_dynamic_access_and_field_whitelist` | UI 自取 key/任意字段 | 仅 resolver 动态；字段只 label/help/placeholder | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-15 | §15 官方专名例外 | B7-8 | smoke | `test_runtime_language_switch_v2::test_official_names_surrounded_by_localized_copy` | 例外吞掉整句翻译 | 仅官方名原样，周围文案刷新 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-41 | §6.1 “ai_generate 必须先注册素材” | B7-4 | integration | `test_generation_run_coordinator::test_registers_asset_before_slot_output` | slot 先引用未注册 asset | AssetRegistry 成功后才写 slot/asset_list | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-41 | §16 B7-4 首步删除 adapter/旧入口 | B7-4 | static | `test_generation_run_coordinator::test_legacy_adapter_and_old_entries_are_absent` | B7-2 临时 adapter 仍存在 | 文件/符号/注册入口为0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-7-42 | §16 B7-4 唯一 writer | B7-4 | static+integration | `test_generation_run_coordinator::test_is_only_run_slot_output_writer` | controller/provider/renderer 可直接改状态 | 只有协调器可写 run/slot/Output，其他只订阅 typed events | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-36 | §8.6 sentinel 增量 B7-2 | B7-2 | integration | `test_sensitive_payload_guard_v2::test_v2_persistence_surfaces_exclude_sentinel` | v2 持久面可能保存密钥 | project/clipboard/generation+cleanup provenance 扫描为0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-37 | §8.6 sentinel 增量 B7-4 | B7-4 | integration | `test_sensitive_payload_guard_v2::test_coordinator_visible_state_excludes_sentinel` | 协调器 state/技术详情可能保留密钥 | coordinator/event/dialog technical surface 扫描为0 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-8-38 | §8.3 多 cancel 最终领域状态 | B7-4 | unit | `test_generation_run_coordinator::test_multi_cancel_terminal_priority_and_no_busy` | wrappers settle 后 records/slots 残留 busy | 全槽/record 终态，cancel_failed 优先 Failed，否则 Canceled | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-42 | §6.6 cleanup cancel 固定顺序 | B7-6 | integration | `test_cleanup_run_coordinator::test_cancel_order_worker_task_wrapper` | 直接以 PFTask.cancel void 推断成功 | worker stopped→operation canceled→PFCancel resolved | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-43 | §6.6 cleanup cancel 5s/去重 | B7-6 | unit | `test_cleanup_run_coordinator::test_cancel_fake_clock_deadline_and_dedupe` | 真实等待/重复 cancel 多 wrapper | 同 request 同 wrapper；fake 5s；失败 cancel_failed | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-44 | §6.6 cleanup 取消收敛 | B7-6 | integration | `test_cleanup_run_coordinator::test_cancel_keeps_success_and_cancels_remaining` | 取消后仍启动下一张/丢成功 | 不启动下一项；已有成功保留；其余 canceled；无 busy | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-45 | §6.6/§7.2 每次 cleanup 新 Output | B7-6 | integration | `test_cleanup_run_coordinator::test_every_click_new_output_and_partial_aggregation` | 新运行覆盖旧/单项失败终止 | 每次完整点击新 current、旧 history；单失败继续并聚合 Partial | `./pixel/scripts/run_tests.sh` |
| B7-REQ-6-46 | §6.6 interrupted Retry | B7-6 | integration | `test_cleanup_run_coordinator::test_retry_interrupted_same_output_original_snapshots_only` | Retry 读当前设置/重跑成功项 | 同 Output 只 interrupted slots，用原 snapshot；成功项不动 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-16 | §16 “新增 UI 当卡同时双语” B7-4 | B7-4 | i18n | `test_generation_card_v2::test_generation_progress_cost_error_provider_keys_refresh` | 生成/状态/费用/错误/设置出现临时 English | B7-4 keys 两语、placeholder 同序、en→zh→en 当前场景刷新 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-17 | §16 同规则 B7-5 | B7-5 | i18n | `test_output_card_controller::test_output_keys_placeholders_and_runtime_refresh` | Output 新 UI 延后到 B7-8 才翻译 | 状态/空态/滚动/拆出/下载/history 两语当卡完整刷新 | `./pixel/scripts/run_tests.sh` |
| B7-REQ-15-18 | §16 同规则 B7-6 | B7-6 | i18n | `test_cleanup_card_ui::test_cleanup_keys_placeholders_and_runtime_refresh` | cleanup 新 UI 临时 English | 分组/参数/报告/run/cancel/error 两语当卡完整刷新 | `./pixel/scripts/run_tests.sh` |

## 14. 旧测试失效与替换台账

每一项只有一个 owner；“删除”只删除被 §3/§10.7 明确退役的产品断言，测试文件中的
无关行为必须保留或迁移。下载/export 是保留能力，不得与 split/review 一起删除。

| 旧文件 :: 旧测试名 | 退役/保留条款 | Owner | 删除或改写 | 同卡替代测试名 |
|---|---|---|---|---|
| `test_canvas_batch_expansion.gd::test_all_filter_creates_fifty_real_slots_at_contract_geometry` | §10.7 删除 All 筛选/全部展开 | B7-5 | 改写 | `test_output_slot_grid::test_fifty_slots_scroll_with_three_visible_rows` |
| 同文件 `test_five_column_threshold_is_exact` | §10.2 max_columns=4 | B7-5 | 改写 | `test_output_layout_calculator::test_columns_never_exceed_four` |
| 同文件 `test_result_counts_and_widths_follow_one_growth_formula` | §10.7 删除无限增高 | B7-5 | 改写 | `test_output_layout_calculator::test_count_width_height_matrix` |
| 同文件 `test_auto_growth_retracts_and_placeholders_do_not_jump` | §10.5 stable slots；卡高不无限增长 | B7-5 | 改写 | `test_output_slot_grid::test_status_refill_keeps_slot_and_scroll` |
| 同文件 `test_focus_keeps_complete_grid_and_tail_hit_target` | §10.7 删除 Focus | B7-5 | 改写 | `test_output_slot_grid::test_scrolled_tail_hit_maps_slot_id` |
| 同文件 `test_expected_placeholders_reserve_the_same_fifty_slots` | §7.1 删除 expected_count | B7-5 | 改写 | `test_output_slot_grid::test_prebuilt_result_slots_are_stable` |
| 同文件 `test_last_of_fifty_uses_front_action_row_without_scroll_or_paging` | §10.4 改为内部滚动 | B7-5 | 改写 | `test_output_slot_grid::test_last_of_fifty_is_reachable_by_scroll` |
| `test_canvas_batch_card.gd::test_canvas_batch_card_exports_asset_queue_and_can_split_subset` | §10.7 保留下载、删除旧 split | B7-5 | 拆成下载保留+detach 改写 | `test_output_card_controller::test_download_visible_successes`；`test_detach_output_asset_command::test_detach_selected` |
| 同文件 `test_batch_card_header_collapse_is_persisted_and_undoable` | §10.2 保留标题/尺寸/折叠 | B7-5 | 迁移 | `test_output_card_controller::test_title_size_collapse_roundtrip` |
| 同文件 `test_canvas_batch_card_marks_review_state_and_splits_kept_subset` | §10.7 删除 Keep/Review/split | B7-5 | 删除旧断言并改写 | `test_output_selection_toolbar::test_selection_is_ephemeral_and_detach_selected` |
| 同文件 `test_canvas_batch_card_filters_visible_review_subset` | §10.7 删除筛选 | B7-5 | 删除 | `test_output_legacy_removal::test_no_review_filter_symbols` |
| 同文件 `test_canvas_batch_card_focuses_visible_review_thumbnails` | §10.7 删除 Focus | B7-5 | 改写 | `test_output_selection_toolbar::test_single_select_and_preview` |
| 同文件 `test_canvas_batch_card_switches_review_layout_for_focus_view` | §10.7 删除 Contact/Focus | B7-5 | 删除 | `test_output_legacy_removal::test_no_review_layout_symbols` |
| 同文件 `test_canvas_batch_card_switches_semantic_lod_profiles` | §10.7 保留通用 LOD | B7-5 | 迁移 | `test_output_card_controller::test_output_lod_does_not_change_geometry` |
| 同文件 `test_canvas_batch_card_keeps_previous_version_for_compare` | §10.7 删除 Previous/Compare | B7-5 | 删除 | `test_output_legacy_removal::test_no_compare_symbols` |
| 同文件 `test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement` 中 `asset_ids`/覆盖写入断言 | §7.1/§7.2 hard cut 旧真相与 overwrite | B7-2 | 拆除旧 schema 断言，保留下载/引用等未退役行为 | `test_output_slots_v2::test_visible_projection_and_no_legacy_aliases` |
| 同测试的新运行保留旧 Output/history 行为 | §7.2 新 Output/history；禁止覆盖 | B7-4 | 在协调器测试中最终替代 | `test_generation_run_coordinator::test_new_run_preserves_old_output` |
| 同文件 `test_graph_batch_card_persists_review_state_in_graph_params` | §7.1/§10.7 hard cut `review_states` | B7-2 | 改写为字段不存在与 slots 往返 | `test_output_slots_v2::test_graph_has_no_review_states_alias` |
| 同文件 `test_graph_batch_card_persists_review_filter_in_graph_params` | §7.1/§10.7 hard cut `review_filter` | B7-2 | 改写为字段不存在 | `test_output_slots_v2::test_graph_has_no_review_filter_alias` |
| 同文件 `test_graph_batch_card_persists_focus_asset_id_in_graph_params` | §7.1/§10.7 hard cut `focus_asset_id` | B7-2 | 改写为字段不存在 | `test_output_slots_v2::test_graph_has_no_focus_asset_id_alias` |
| 同文件 `test_graph_batch_card_persists_review_layout_in_canvas_data` | §7.1/§10.7 hard cut `review_layout` | B7-2 | 改写为 Graph/Canvas 均不持久化该字段 | `test_output_slots_v2::test_canvas_has_no_review_layout_alias` |
| 同文件 `test_graph_batch_card_persists_compare_state_in_graph_params` | §7.1/§10.7 hard cut `compare_*` | B7-2 | 改写为字段不存在 | `test_output_slots_v2::test_graph_has_no_compare_aliases` |
| 上述 review/focus/compare 的最终生产符号移除守护 | §10.7 Output UI 退役 | B7-5 | 最终静态守护，不由 B7-2 提前完成 | `test_output_legacy_removal::test_review_filter_compare_symbols_are_absent` |
| 同文件 `test_failed_batch_placeholder_keeps_expected_slots_and_routes_retry_remove` | §7.1 slots；§8.5 Retry 前置 | B7-5 | 改写 | `test_output_card_controller::test_failed_slot_actions_follow_safe_error` |
| `test_main_window_ui.gd::test_batch_review_shortcuts_mark_selected_mock_thumbnail` | §10.7 删除 review shortcut | B7-5 | 改写 | `test_output_selection_toolbar::test_selection_shortcuts_do_not_persist_review` |
| 同文件 `test_batch_review_focus_shortcuts_step_selected_mock_thumbnail` | §10.7 删除 Focus | B7-5 | 改写 | `test_output_selection_toolbar::test_keyboard_selection_tracks_visible_slot` |
| 同文件 `test_batch_processing_replaces_selected_asset_without_dropping_unselected_items` | §6.6/7.2 清洗不覆盖、每次新 Output | B7-6 | 改写 | `test_cleanup_run_coordinator::test_cleanup_preserves_source_and_creates_output` |
| 同文件 `test_cleanup_inspector_keeps_apply_actions_reachable_below_scroll` | §9.2 删除检查器执行入口 | B7-6 | 改写 | `test_cleanup_card_ui::test_footer_is_only_execution_entry` |
| `test_workspace_shell_ui.gd::test_blank_workspace_can_build_and_run_reference_to_result_chain` | §5–7 v2 主路径 | B7-4 | 改写 | `test_generation_run_coordinator::test_reference_generation_creates_visible_output` |
| 同文件 `test_offline_example_is_one_undoable_reference_to_batch_workspace` | §13 重做唯一示例 | B7-7 | 改写 | `test_example_builder_v2::test_example_is_one_undo` |
| 同文件 `test_context_inspector_reuses_cleanup_for_sprite_and_batch` | §9.2 删除检查器直接清洗 | B7-6 | 改写 | `test_cleanup_card_ui::test_image_and_batch_sources_use_cleanup_node` |
| `test_asset_reference_contract.gd::test_graph_batch_board_animation_and_transition_batch_are_live` | §7.4 删除 batch_card/asset_ids | B7-2 | 改写 | `test_asset_reference_contract_v2::test_output_slots_board_animation_are_live` |
| 同文件 `test_live_references_block_delete_but_history_only_allows_it` | §7.4 history 也阻止 orphan 字节清理 | B7-2 | 改写 | `test_asset_reference_contract_v2::test_live_and_history_both_preserve_bytes` |
| `test_graph_mock_runner.gd::test_mock_generate_chain_can_replace_existing_batch_assets` 中 `asset_ids` 替换断言 | §7.1/§7.2 hard cut 旧真相与 overwrite | B7-2 | 删除旧字段/覆盖断言并补 slots 无 alias 断言 | `test_output_slots_v2::test_mock_path_uses_result_slots_projection_only` |
| 同测试的第二次运行建立 history/current 行为 | §7.2 最终协调器运行语义 | B7-4 | 在新协调器中最终替代 | `test_generation_run_coordinator::test_second_run_creates_history_and_current` |
| 同文件 `test_mock_generate_chain_rejects_missing_required_spec_input` | §6.3 删除 size_spec | B7-2 | 改写 | `test_graph_v2_schema::test_generate_requires_local_target_params` |
| `test_pixel_editor_ui.gd::test_canvas_editor_entry_save_as_updates_batch_and_provenance` | §10.6 打开编辑器保留；Output slot 真相 | B7-5 | 改写 | `test_output_card_controller::test_open_editor_updates_asset_without_replacing_slot_identity` |
| `test_canvas_card_editing.gd::test_graph_card_defaults_are_contract_values_and_survive_lod` 的 batch_card 分支 | §10.7 删除 batch_card，保留 graph Output | B7-5 | 删除 legacy case、保留通用 case | `test_output_card_controller::test_output_defaults_and_lod` |
| `test_result_branch_builder.gd::test_multiple_results_build_runnable_independent_continue_branch` | §6.3/6.4 删除 size/style | B7-2 | 改写 | `test_result_branch_builder_v2::test_branch_uses_target_prompt_preset_and_asset_list` |
| `test_graph_mock_generate.gd::test_size_spec_outputs_dimensions_and_per_subject_count` | §6.3 删除 size_spec/per_subject | B7-2 | 删除并替代 | `test_graph_v2_schema::test_generate_target_and_subject_counts_are_unique_truth` |
| `test_content_input_nodes.gd::test_style_preset_outputs_detached_validated_embedded_data` | §6.4 PromptPreset 替代 | B7-2 | 改写 | `test_prompt_preset_v1::test_prefix_snapshot_output` |
| `test_cleanup_pipeline.gd::test_style_preset_base_size_flows_into_detect_params` | §6.6/6.7 CleanupPreset snapshot | B7-6 | 改写 | `test_cleanup_palette_snapshot::test_full_settings_and_palette_are_frozen_at_click` |
| `test_pixel_editor_ui.gd::test_canvas_editor_entry_save_as_updates_batch_and_provenance` 中 manifest.style_preset setup | §6.4 editor 模块默认 32/db32 | B7-2 | 拆除全局 Style setup，保留编辑/保存断言 | `test_pixel_editor_ui::test_default_size_and_palette_are_module_owned` |
| `test_board_editor_ui.gd::test_board_editor_entry_creates_style_sized_board_and_places_asset` | §6.4 board 模块默认 16/db32 | B7-2 | 改写模块默认并保留放置素材 | `test_board_editor_ui::test_default_tile_and_palette_are_module_owned` |
| `test_project_resource_catalog.gd::test_styles_searches_built_in_name_and_resolution_tier` | §6.4 catalog 拆 preset kind | B7-2 | 改写 | `test_project_resource_catalog::test_prompt_and_cleanup_presets_are_independent_resources` |
| `test_project_roundtrip.gd::test_project_save_open_roundtrip_matches_manifest_canvas_and_assets` | §5 Project v2 | B7-2 | fixture/断言重建 v2 | `test_project_v2_roundtrip::test_manifest_canvas_assets_v2` |
| `test_graph_model.gd::test_known_graph_node_and_edge_unknown_fields_survive_roundtrip` | §5/§6 known node fail closed | B7-2 | 改写为 v2 已知字段拒绝与 ghost 往返分支 | `test_graph_v2_schema::test_known_fields_fail_closed_unknown_type_ghosts` |
| `test_openai_provider_contract.gd::test_ui_provider_catalog_declares_reference_support_without_network_request` | §5/§8 Provider v2 | B7-2 | descriptor fixture 重建 v2 | `test_provider_descriptors_v2::test_openai_exact_descriptor` |
| `test_retrodiffusion_provider_contract.gd::test_capabilities_and_schema_match_provider_contract` | §5/§8 Provider v2 | B7-2 | descriptor/config fixture 重建 v2 | `test_provider_descriptors_v2::test_retro_exact_descriptors` |
| `test_plugin_service.gd::test_directory_plugin_unload_ghost_and_reload_restore` | §5 Plugin API v2 | B7-2 | manifest/fixture 重建 v2 | `test_plugin_api_v2::test_v2_directory_unload_reload` |
| `test_workflow_template_service.gd::test_builtins_validate_and_instantiate_remaps_all_ids_and_positions` | §5/§7 Template v2 | B7-2 | 四个 builtin fixture 重建 v2 | `test_workflow_template_v2::test_four_builtins_remap` |
| `test_canvas_graph_clipboard.gd::test_capture_keeps_relative_layout_internal_edges_and_safe_asset_references` | §5/§7 Clipboard v2 | B7-2 | payload/identity/安全字段重建 v2 | `test_clipboard_v2::test_capture_v2_layout_edges_and_safe_refs` |

## 15. 每卡证据与禁止项

每张 B7-1 至 B7-8 的提交记录必须包含：新增测试名、红灯命令与失败原因、实现后
定向绿色、相关 integration/static guard、FULL 绿色计数、`git diff --check`、staged
raster guard 无输出和范围检查。B7-0 只建立本 manifest，不伪造未来红灯。

B7-8 后停止。本 manifest 不包含 B7-9 的 screenshot harness、候选、版本改写、构建
或发布测试；没有项目所有者新的明确授权不得创建这些产物。

## 16. B7-0 基线证据

- main 集成基线：`26a60708233f75cad7673cb9f80d9532f00c9d25`；批准计划 SHA-256：
  `655597660e21acdf7a4d5e2bab388bdf54586875ee59921211cdc1dad2f073f4`。
- 2026-07-14 从控制工作区 ignored 目录临时恢复且仅恢复三张批准 fixture；复制后 SHA：
  `0b0a83f933683dad5461934eb710745e77e0d35490ac4e36df5a8f42c7051fd0`、
  `2fc1ae9af927d169984e8ec0b5df4bb00abaeea0d2898a460baf8d60610007b9`、
  `b37fe2ed13b8ba181c77239a04945b4c45df96dc3b28f53b50b0e48aab1b9d69`。
- `./pixel/scripts/run_tests.sh`：76 scripts、396/396 tests、7718 assertions、1 个既有
  orphan，exit 0；Godot 退出仍报告既有 resource/ObjectDB 提示，不是测试失败。
- 测试命令退出时三张临时副本立即删除；目标目录只剩 `.gdignore` 与
  `REAL_AI_REVIEW.md`，没有 `.import`；未 add/force-add，staged raster guard 无输出。
- B7-0 没有修改 `pixel/`、没有新增可执行 test、skip 或 xfail，也没有产品实现。

## 17. B7-1 工程证据

- 提交：`9fcac09`。新增敏感 header/URL/error sentinel、可注入 retry policy
  和 RetroDiffusion 无哑元生成验证，测试先对基线的泄漏、错误重试与旧验证
  路径真实失败，实现后定向转绿。
- `./pixel/scripts/run_tests.sh`：406/406 tests、7805 assertions、1 个既有 orphan，exit 0。
  受保护 fixture 按固定 hash 临时恢复并在测试后删除；i18n、v1 security、
  `git diff --check` 与 staged raster guard 全部绿色。

## 18. B7-2 工程证据

- owner 按项目所有者正式裁定 `B7-DEC-OWNER-01` 拆分：B7-2 清除 hard cut 直接
  失效的 legacy schema 断言；B7-4 的最终协调器/history 和 B7-5 的最终 Output UI/
  legacy 符号移除仍各自保留完整 red→green 与完成门，本卡未提前勾销。
- 新建 v2 contract/schema/provider/project/clipboard/template/output/provenance 测试在
  基线上因 v1 仍被接受、旧字段与 alias 仍存在而真实失败。第一次全量收口
  为 481/493，12 个失败都定位到旧 schema fixture、JSON 边界、provenance 嵌套、
  内部 mock 与旧 batch UI 读取路径；没有删除或弱化保留行为断言。
- 实现提交串：`f9c6c27`、`dc56e0a`、`6d92fb6`、`aaf3ae2`；前置的测试/
  分层切片保留在同一 main 历史中。最终达成 v2 hard cut、无 v1 alias、唯一
  `result_slots` 可见投影，Provider 生产目录只有 OpenAI Image/RetroDiffusion，
  automation mock 不向产品暴露。
- 定向绿色包括 v2 73/73（1392 assertions）以及 provider contract、asset
  reference、project roundtrip、canvas batch、frame planner、graph mock、reference set 和
  workspace inspector。全量：98 scripts、493/493 tests、9391 assertions、1 个既有
  orphan，exit 0；全量 lint 274 文件无问题。
- 全量前只临时恢复三张批准 fixture，三个 SHA-256 与 B7-0 记录相同；
  测试后立即删除副本和 `.import` 名称，路径无残留、未 add/force-add。日志只有
  故障注入 `syntax_error` 的预期解析错误和既有 1 orphan/7-resource 退出提示。
- 批准计划 SHA-256 仍为
  `655597660e21acdf7a4d5e2bab388bdf54586875ee59921211cdc1dad2f073f4`；
  `git diff --check` 通过，staged raster guard 无输出。

## 19. B7-3 工程证据

- 真实红灯提交：`d8be104`。新增测试先证明旧路径会在规划前触碰凭据/状态、Provider
  结果与失败归一化不完整、费用仍可走 float/重复记录、取消与进度缺少固定语义、
  retry 可能重发成功槽；后续真实红灯还捕获了 timeout 注入边界、整任务失败映射和
  Provider 目录职责守护，均未通过修改或弱化测试规避。
- 实现提交：`ca2e740`。Planner 统一完成 prompt、999 上限、原生尺寸、seed 分片与
  wrap、reference RGBA8/id/SHA、严格 extra 和请求身份快照；本地验证在凭据、预算、
  Output 与 HTTP 前完成。OpenAI Image/RetroDiffusion mock transport 覆盖成功、Partial、
  timeout、auth failure、cancel 和显式 manual retry，Provider 不做隐藏生成重试。
- 失败槽 retry 与完整重新生成共用纯后端 `plan -> CostService.preflight -> authorize`
  边界；只有 `failed`、合法且 `retryable=true` 的槽可进入请求。mock POST 计数证明成功
  槽非法 retry 与预算确认取消都增加 0 次请求，授权失败槽只增加 1 次且 batch=1。
  B7-4 最终协调器/新 Output/history 与 B7-5 最终 Output UI owner 未提前勾销。
- Provider 与 CostService 共用纯整数 micro USD 转换；费用按 charge/request 去重，
  unknown 保持 null，取消先结算 billing 再进入终态。独立只读审查确认无剩余 B7-3
  blocker、无 B7-4 UI/协调器越界、无真实付费端点调用。
- `./pixel/scripts/run_tests.sh`：542/542 tests、9995 assertions、1 个既有 orphan，
  exit 0；全量 lint 292 文件无问题。全量前按固定流程临时恢复三张批准 fixture 并核对
  B7-0 所列三个 SHA-256，测试后立即删除；没有 `.import` 或图片残留，未 add/force-add。
- 批准计划 SHA-256 仍为
  `655597660e21acdf7a4d5e2bab388bdf54586875ee59921211cdc1dad2f073f4`；
  `git diff --check`、敏感特征扫描和 staged raster guard 均无输出。

## 20. B7-4 工程证据

- 红灯分别固定了协调器/Output 原子创建、运行态进度与取消、启动恢复、生成卡、运行边、
  错误框、真实控制器接线、自动摆放、预算归属、回滚和失败项 retry 缺口；随后删除
  legacy adapter 与旧 generation controller，`GenerationRunCoordinator` 成为 run、record、
  slot 与 Output 的唯一 writer。
- 产品路径已连通：每次完整运行创建新 current Output 并保留 history；失败项 retry 在同一
  Output 使用原输入快照与新 run/request；固定槽分母进度、cancel cutoff、多请求收口、迟到
  回调忽略、打开项目前 interrupted 恢复、80px 右侧摆放、六组生成卡、typed run edge 和
  每 run 最多一次的脱敏错误框均进入真实控制器。生产 Provider 仍只有 OpenAI Image 与
  RetroDiffusion，没有真实付费请求。
- 相关定向证据包括生成卡 9/9、错误框接线 6/6、运行边 6/6、edge state 8/8、运行态 7/7、
  coordinator 8/8、Provider contract 23/23、主窗口 22/22；i18n 与 UI scaling 守护绿色。
- 最终 `./pixel/scripts/run_tests.sh`：114 scripts、594/594 tests、10493 assertions、1 个既有
  orphan，exit 0。前三轮全量暴露并修正旧生成卡断言、协调器 preflight 归属和已保存
  Provider 在目录变化时被静默改写的问题；没有通过 skip/xfail 或弱化产品门消红。
- 每次全量前只临时恢复 B7-0 记录的三张批准 fixture 并核对相同 SHA-256，测试后立即删除；
  无 `.import` 或图片残留，未 add/force-add。批准计划 SHA-256 仍为
  `655597660e21acdf7a4d5e2bab388bdf54586875ee59921211cdc1dad2f073f4`。
