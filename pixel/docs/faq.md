# PixelForge FAQ

## Why did cleanup make my AI image smaller?

Most AI “pixel art” is a large smooth image imitating pixels. Cleanup detects the repeated grid and collapses each fake block into one true pixel, then maps colors to the project palette. Use manual grid mode if detection confidence is low.

## Are plugins sandboxed?

No. GDScript plugins can execute code with your user permissions. Install only trusted plugins and review the permissions disclosure. PixelForge isolates load failures but does not claim a security sandbox.

## Why is ComfyUI output cleaned again?

Stable Diffusion/SDXL output remains raster art even with a pixel LoRA, so the Provider correctly reports `raw_pixel=false`. Cleanup creates the actual grid/palette constraints.

## Where are keys stored?

Cloud secrets are encrypted in local `credentials.cfg`; they are never written to `.pxproj` or logs. A machine identity change can make old local ciphertext unreadable, in which case re-enter the key.

## Why is inpaint disabled in the repair editor?

It activates only when an installed Provider/template declares inpaint capability. PixelForge keeps the action disabled instead of pretending an unsupported request can work.
