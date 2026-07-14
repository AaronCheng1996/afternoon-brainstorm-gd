# P2-5 設定持久化（見 docs/rebuild/06 P2-5）。存 user://settings.json。純靜態工具。
# 設定項：提示（card_hints）、動畫（逐格/瞬時）、P11-1 對戰回合計時／BP 選秀計時（開關＋秒數）。
class_name SettingsStore
extends RefCounted

const PATH := "user://settings.json"
const DEFAULTS := {
	"hints_on": true,
	"animations_on": true,
	"turn_timer_on": false,     # P11-1 對戰回合計時開關
	"turn_seconds": 60,         # 逾時自動結束回合
	"draft_timer_on": false,    # P11-1 BP 每階段計時開關
	"draft_seconds": 45,        # 逾時自動補牌並進下一階段
}


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
		out["turn_timer_on"] = bool(parsed.get("turn_timer_on", DEFAULTS["turn_timer_on"]))
		out["turn_seconds"] = int(parsed.get("turn_seconds", DEFAULTS["turn_seconds"]))
		out["draft_timer_on"] = bool(parsed.get("draft_timer_on", DEFAULTS["draft_timer_on"]))
		out["draft_seconds"] = int(parsed.get("draft_seconds", DEFAULTS["draft_seconds"]))
	return out


# 以 values 覆蓋預設後全量寫回（未提供的鍵沿用預設）。
static func save_settings(values: Dictionary) -> void:
	var merged: Dictionary = DEFAULTS.duplicate()
	for k: String in DEFAULTS:
		if values.has(k):
			merged[k] = values[k]
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("SettingsStore：無法寫入 " + PATH)
		return
	f.store_string(JSON.stringify(merged))
	f.close()
