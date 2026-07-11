class_name PFAppInfo
extends RefCounted

## 应用元信息的唯一入口。
## UI 标题、项目 manifest 和报告都应从这里读取名称与版本，避免散落硬编码。

const APP_NAME := "PixelForge"
const APP_VERSION := "0.2.0-beta.1"
const PROJECT_FORMAT_VERSION := 1
