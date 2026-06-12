class_name PFCanvasItemFrame
extends Node2D

## M0 只实现 sprite 元素；frame 在 M3/M5 扩展。
## 保留脚本是为了让目录和未来项目格式中的 frame_id 有稳定落点。
## 当前脚本不承担运行时行为；后续加入地图构图或节点锚点时再扩展字段和绘制逻辑。

var frame_id := ""
