# CLEANUP-PRESETS.md — CleanupPreset v1 契约

> `cleanup_preset_version=1`。Preset 是一次完整填值 snapshot；节点 settings 才是
> 执行真相。不得保存 target_size、图片或凭据。

## 1. 完整 schema

```json
{
  "cleanup_preset_version":1,
  "id":"cleanup-16bit-db32",
  "name_key":"CLEANUP_PRESET_16BIT_DB32",
  "settings":{
    "detect_grid":{"enabled":true,"mode":"auto","scale":4.0,"offset":[0.0,0.0],"base_size":32},
    "resample":{"enabled":true,"mode":"mode","scale":4.0,"offset":[0.0,0.0]},
    "quantize":{"enabled":true,"mode":"fixed_palette","palette_id":"db32",
      "auto_k_strategy":"median_cut","k":16,"dither":"none",
      "dither_strength":0.0,"dither_contrast":0.0,"dither_chroma":0.0,
      "dither_density":1.0}
  }
}
```

内置 preset 只有 name_key；用户 preset 只有 name；同时有或同时无均失败。选择预设
把完整 settings 复制进节点并写 preset_id；用户修改任一可编辑值立即清 preset_id，
但保留 settings。执行时禁止重新读取 preset 覆盖节点。项目、模板、Clipboard 和
provenance 保存完整 settings，使 registry 资源后来不存在也可复现。

Preset registry 注册时必须调用唯一 SchemaTextResolver.validate_schema；name_key、
label_key/help_key/placeholder_key 在 English/简中必须存在且非空，UI 只经 resolver。

## 2. 校验与 UI 同一真相

- detect_grid.enabled 固定 true；mode 只允许 auto/manual；
- detect_grid/resample 的 scale 同值且为 1.0..64.0；offset 同值且每项 0.0..64.0；
- base_size 只允许 0/8/16/24/32/48/64/96/128，由 preset 提供并只读；
- resample.enabled 为 bool；mode 为 mode/center/median/edge_aware；
- quantize.enabled 为 bool；mode 为 auto_k/fixed_palette/none；
- palette_id 是内置或用户 palette id；auto_k_strategy 为 median_cut/kmeans；k 2..256；
- dither 为 none/bayer2/bayer4/bayer8/chromatic/error_diffusion；
- strength 和 contrast 均为 0..1 且必须同值；chroma 0..0.25；density 0..1。

卡片只显示一组 scale/offset 并同时写入两处；只显示一个 Strength 并同时写 strength/
contrast。不得新增第二套控件。target_size 由来源逐图派生，只注入 pipeline 执行副本，
不进入 preset/node/template/Clipboard。palette colors 也不进入 settings。

fixed_palette 执行前从 PaletteRegistry 解析至少 2、至多 256 个颜色。每项规范为
大写 `#RRGGBBAA`，保持原顺序，禁止排序或去重。`colors_rgba8` 数组使用无空白 UTF-8
JSON 编码，其完整字节的 SHA-256 写为小写 hex。运行 snapshot 固定为
`{palette_id,colors_rgba8,content_sha256}`；auto_k/none 为 null。palette 缺失、坏颜色、
hash 不一致均在 worker 前本地拒绝。

## 3. 六个内置完整资源

每个 JSON 必须重复 §1 的全部 settings；禁止 based_on、继承或运行时补字段。未列字段
与完整样例相同；所有 preset 的 auto_k_strategy=median_cut、dither_chroma=0.0、
dither_density=1.0。

| id | name_key | base | enabled/mode | palette | k | dither | strength=contrast |
|---|---|---:|---|---|---:|---|---:|
| cleanup-hibit | CLEANUP_PRESET_HIBIT | 48 | true/fixed_palette | endesga64 | 32 | none | 0.0 |
| cleanup-gb | CLEANUP_PRESET_GB | 16 | true/fixed_palette | gb_4 | 4 | bayer4 | 0.35 |
| cleanup-hd2d-prop | CLEANUP_PRESET_HD2D_PROP | 64 | false/none | custom | 64 | none | 0.0 |
| cleanup-1bit | CLEANUP_PRESET_1BIT | 32 | true/fixed_palette | bw_2 | 2 | bayer4 | 0.5 |
| cleanup-nes | CLEANUP_PRESET_NES | 16 | true/fixed_palette | nes_full | 4 | none | 0.0 |
| cleanup-16bit-db32 | CLEANUP_PRESET_16BIT_DB32 | 32 | true/fixed_palette | db32 | 16 | none | 0.0 |

HD-2D 的 custom 无颜色，因此明确禁用 quantize；不得当作有效固定 palette。旧 profile
的 outline/anti_alias 不进 pipeline，独立描边工具保留；perspective/tile_size/
provider_hints/prompt_template 不进入本契约。旧 JSON 不迁移。
