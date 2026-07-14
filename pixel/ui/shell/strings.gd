class_name PFStrings
extends RefCounted

## UI 文案兼容入口。生产 UI 通过稳定 catalog key 取文案。


static func text(key: StringName, fallback_or_args: Variant = "") -> String:
	return LocalizationService.text(key, fallback_or_args)
