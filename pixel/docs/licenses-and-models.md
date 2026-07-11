# License and Model Audit

| Component | License / status | Distribution |
|---|---|---|
| Godot Engine | MIT | Runtime/export templates; retain Godot notice |
| GUT | MIT | Development/test add-on |
| PixelForge code | Project license | Application |
| Built-in palettes | CC0, source metadata in palette JSON | Application assets |
| Noto Sans CJK SC Regular 2.004 | SIL Open Font License 1.1 | English / Simplified Chinese product UI font |
| perfectPixel algorithm reference | MIT, integration note recorded | Ideas adapted in cleanup algorithms |
| PBKDF2 reference | RFC 8018 / standards reference | Independent implementation |
| ComfyUI | GPL-3.0 upstream; not bundled | Network bridge only |
| SDXL base 1.0 | CreativeML Open RAIL++-M | Not bundled; template requirement only |
| Pixel-art LoRA | User-selected; license varies | Never bundled; user must verify |

No checkpoint, LoRA, real artist fixture, or generated test image is included in a PixelForge package. The two ComfyUI JSON templates contain only workflow configuration.

## Product UI font provenance

`assets/fonts/NotoSansCJKsc-Regular.otf` is redistributed unmodified from the official `notofonts/noto-cjk` repository (`Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf`). The upstream file is <https://github.com/notofonts/noto-cjk/blob/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf>; its bundled SHA-256 is `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b`. The SIL OFL 1.1 license text is bundled at `assets/fonts/OFL.txt`.

The font is the shared UI font for ordinary controls and canvas-drawn text. It is not applied to canvas artwork or image resampling.
