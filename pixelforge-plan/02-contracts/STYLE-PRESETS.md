# STYLE-PRESETS.md — 风格预设契约

> 产品一致性的核心数据对象。被生成端（Provider）、清洗端（pipeline）、编辑端（编辑器默认值）三方消费。

## 1. Schema（style_version = 1）

```json
{
  "style_version": 1,
  "id": "preset_16bit_db32",
  "name": "16-bit / DB32",
  "based_on": null,                      // 派生自哪个内置预设（用户自定义时）
  "resolution_tier": "16bit",           // 8bit | 16bit | hibit | hd2d | 1bit | gb
  "base_size": 32,                       // 角色/物体基准边长（px）
  "tile_size": 16,                       // 地块尺寸（M5 拼图用）
  "palette": {
    "ref": "db32",                       // 内置调色板 id；或 "custom"
    "colors": ["#000000", "..."]         // ref=custom 时的色表（hex 列表）
  },
  "max_colors_per_sprite": 16,           // 单素材色数上限（量化目标）
  "outline": "none",                     // none | black_1px | colored_1px | selective
  "dither": "none",                      // none | bayer2 | bayer4 | bayer8 | error_diffusion
  "dither_strength": 0.0,                // 0–1
  "perspective": "side",                 // side | topdown | three_quarter | isometric
  "anti_alias": false,                   // 允许手工 AA 像素（影响清洗的锐化策略）
  "prompt_template": {
    "positive": "{subject}, pixel art, 16-bit style, {size_hint}, limited palette, clean pixel grid",
    "negative": "blurry, anti-aliasing, gradient, photorealistic, 3d render",
    "style_tags": "retro game asset, DawnBringer palette"
  },
  "provider_hints": {                    // 各 provider 的专有映射（可空）
    "retrodiffusion": { "style": "rd_16bit" }
  }
}
```

## 2. 三端消费方式（实现卡必须对照）

| 消费方 | 读取字段 | 行为 |
|---|---|---|
| ai_generate 节点 | prompt_template, base_size, provider_hints | 组装提示词；选择 provider 参数 |
| pixel_cleanup 管线 | palette, max_colors, outline, dither*, base_size | 量化目标=palette；网格检测先验 scale≈源图边长/base_size；按 outline 配置后处理 |
| 像素编辑器 (M6) | palette, base_size, tile_size | 新建画布默认尺寸；调色板面板预载 |
| 地图拼接 (M5) | tile_size, palette | 网格吸附尺寸；新素材校验色板一致性（警告不阻断）|

## 3. 内置预设（assets/presets/，M1 任务卡随调色板一起落地）

| id | tier | base | palette | outline | 备注 |
|---|---|---|---|---|---|
| preset_gb | gb | 16 | gb_4 (4色绿) | none | GameBoy 复古 |
| preset_nes | 8bit | 16 | nes_full | black_1px | NES 风（按精灵 3+1 色约束做量化）|
| preset_16bit_db32 | 16bit | 32 | db32 | none | 默认预设 |
| preset_hibit | hibit | 48 | endesga64 | selective | 现代高清像素 |
| preset_1bit | 1bit | 32 | bw_2 | none | 1-bit 风 |
| preset_hd2d_prop | hd2d | 64 | custom(不限) | none | HD-2D 素材（弱量化）|

内置调色板数据（assets/palettes/*.json）：`{id, name, colors: [hex...], source: "lospec", license: "CC0"}`。首批内置：db16, db32, pico8, endesga32, endesga64, aap64, gb_4, nes_full, bw_2。来源 Lospec（CC0 可自由内置）。

## 4. 不变量

- `palette.colors` 长度 ≥ 2 且 ≤ 256；hex 大写无 alpha（透明用 RGBA 图层处理，不进色板）。
- `base_size ∈ {8,16,24,32,48,64,96,128}`；`tile_size` 整除或等于 base_size 不强制，但 UI 提示。
- 预设对象不可变（修改=创建新 id 的副本），素材 provenance 引用预设 id 才有意义。
