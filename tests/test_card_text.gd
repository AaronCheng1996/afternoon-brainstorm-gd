# P0-4 card_text.json 驗收：全卡 name 非空；hint 與 Python card_hints 一致（抽查 5 張）。
extends RefCounted

const JOBS := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP"]
const PURPLE_JOBS := ["AP", "TANK", "HF", "ASS"]


func run(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()

	# 遍歷全部標準卡 id，name 皆非空。
	var codes := ["W", "R", "G", "B", "O", "DKG", "C", "F", "BR", "P"]
	for code in codes:
		var jobs: Array = PURPLE_JOBS if code == "P" else JOBS
		for job in jobs:
			var card_id: String = job + code
			var txt: Dictionary = db.text(card_id)
			t.ok(not String(txt.get("name", "")).strip_edges().is_empty(), "name 非空 " + card_id)

	# token 卡也要有 name。
	t.ok(not String(db.text("CUBEW").get("name", "")).is_empty(), "CUBEW name")
	t.ok(not String(db.text("LUCKYBLOCKG").get("name", "")).is_empty(), "LUCKYBLOCKG name")

	# hint 與 card_hints 一致（抽查 5 張）。
	var hints: Dictionary = _load_hints()
	for card_id in ["ADCW", "SPW", "TANKBR", "APG", "ASSF"]:
		t.eq(db.text(card_id).get("hint", ""), hints.get(card_id, "<缺>"), "hint 對齊 " + card_id)

	db.free()


func _load_hints() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/balance/card_hints.json")
	return JSON.parse_string(text)
