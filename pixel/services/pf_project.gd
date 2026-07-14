class_name PFProject
extends RefCounted

## 内存项目模型。
## contract: 02-contracts/PROJECT-FORMAT.md；manifest/canvas 保持 Dictionary，方便和 JSON 一一对应。

const AppInfo := preload("res://core/util/app_info.gd")
const IdUtil := preload("res://core/util/id_util.gd")

var project_path := ""
var manifest := {}
var canvas := {}
var graphs := {}
var boards := {}
var animations := {}
var dirty := false
var recovered_from_path := ""


func reset(name: String = "Untitled") -> void:
	var now: String = IdUtil.utc_now_iso()
	manifest = {
		"format_version": AppInfo.PROJECT_FORMAT_VERSION,
		"app_version": AppInfo.APP_VERSION,
		"id": IdUtil.uuid_v4(),
		"name": name,
		"created_at": now,
		"modified_at": now,
		"entries":
		{
			"canvases": ["canvas"],
			"graphs": [],
			"boards": [],
			"asset_count": 0,
		},
	}
	canvas = {
		"camera":
		{
			"center": [0, 0],
			"zoom": 1.0,
		},
		"items": [],
	}
	graphs = {}
	boards = {}
	animations = {}
	project_path = ""
	dirty = false
	recovered_from_path = ""


func get_id() -> String:
	return String(manifest.get("id", "untitled"))


func get_name() -> String:
	return String(manifest.get("name", "Untitled"))


func set_dirty(value: bool) -> void:
	dirty = value
