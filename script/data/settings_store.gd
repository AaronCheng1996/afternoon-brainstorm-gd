# P2-5 設定持久化（見 docs/rebuild/06 P2-5）。存 user://settings.json。
# 目前只有兩個開關：提示（card_hints）、動畫（逐格/瞬時）。純靜態工具。
class_name SettingsStore
extends RefCounted

const PATH := "user://settings.json"
const DEFAULTS := {"hints_on": true, "animations_on": true}


static func load_settings() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):
		return out
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		out["hints_on"] = bool(parsed.get("hints_on", DEFAULTS["hints_on"]))
		out["animations_on"] = bool(parsed.get("animations_on", DEFAULTS["animations_on"]))
	return out


static func save_settings(hints_on: bool, animations_on: bool) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("SettingsStore：無法寫入 " + PATH)
		return
	f.store_string(JSON.stringify({"hints_on": hints_on, "animations_on": animations_on}))
	f.close()
