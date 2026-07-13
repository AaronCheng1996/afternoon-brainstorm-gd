# P0-3 BalanceDB 查詢驗收。
extends RefCounted

const JOBS := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP"]
# Purple 只有 4 張實卡（其餘資料為 0/0 佔位）。
const PURPLE_JOBS := ["AP", "TANK", "HF", "ASS"]


func run(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()

	# 指定值驗收。
	t.eq(db.stats("ADCW").get("health"), 5, "ADCW health")
	t.eq(db.stats("TANKBR").get("health"), 20, "TANKBR health")
	t.eq(db.param("SPW", "extra_score", 0), 1, "SPW extra_score")
	t.eq(db.attack_types("HF"), "small_cross small_x", "HF 攻擊模式")
	t.eq(db.ai("thresholds/attack_min_score"), 15.0, "ai thresholds/attack_min_score")

	# 色碼組合抽查。
	t.eq(db.stats("SPDKG").get("damage"), 5, "SPDKG damage（DKG 色碼組合）")
	t.eq(db.stats("APTW").get("health"), 8, "APTW health（APT 職業不誤判）")

	# 10 色 × 各職業全部可查（Purple 只查 4 張）。
	var codes := ["W", "R", "G", "B", "O", "DKG", "C", "F", "BR", "P"]
	for code in codes:
		var jobs: Array = PURPLE_JOBS if code == "P" else JOBS
		for job in jobs:
			var card_id: String = job + code
			t.ok(db.stats(card_id).has("health"), "可查 " + card_id)

	# data_version 字串。
	t.ok(db.data_version().begins_with("bal 4.3.0.0 @"), "data_version 前綴")

	# color_rgb 接受色名與色碼。
	t.ok(db.color_rgb("Red").is_equal_approx(db.color_rgb("R")), "color_rgb 色名/色碼一致")

	db.free()
