# PixelForge v1 User Manual

## Quick start

On first launch choose a style preset. Cloud keys are optional: mock generation always works and ComfyUI is the local/free route. Import reference images onto the infinite canvas, create or run a light graph, review results in a batch, then use batch actions for cleanup/matting/outline.

Double-click a sprite or batch thumbnail for pixel repair. Save as New preserves the original and updates the source batch. Open Board Editor to assemble tile/free layers, terrain, and animation; export flat PNG plus layer files.

## Core node reference

- **Object List**: one subject per line.
- **Size Spec**: target true-pixel width/height and per-subject count.
- **AI Generate**: mock or a verified cloud Provider.
- **ComfyUI Workflow**: one selected API workflow template, max concurrency 1.
- **Batch**: first-class review/materialization container.

Use nodes for reproducible generation; use batch menus for immediate repeated processing.

## ComfyUI

Start a trusted local server, normally at `http://127.0.0.1:8188`. In Provider Settings save the endpoint and validate. ComfyUI's official local server routes use `/prompt`, `/ws`, `/history/{prompt_id}`, `/view`, `/upload/image`, and `/interrupt`.

Export a workflow in API format, then use **File > ComfyUI Templates**. PixelForge detects KSampler seed, text encoders, latent dimensions, batch, LoadImage, and LoRA slots. Review bindings before save. Missing model/node errors are shown from ComfyUI. SDXL output is marked `raw_pixel=false`, so Pixel Cleanup remains part of the production path.

The bundled SDXL template points to Stability AI's SDXL base model (CreativeML Open RAIL++-M). The pixel-art LoRA is deliberately user-supplied because third-party licenses differ; verify the chosen model's commercial terms yourself.
