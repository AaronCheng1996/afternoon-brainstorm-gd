# P0-3 平衡資料庫（autoload：Balance）。見 docs/rebuild/05_JSON平衡同步.md §2.2。
# 啟動時載入 data/balance/*.json，做最低限度 schema 驗證，並提供查詢 API。
# 於 _init() 載入，故亦可 `load(...).new()` 獨立使用（headless 測試）。
extends Node

const BALANCE_DIR := "res://data/balance/"
const CARD_TEXT_PATH := "res://data/card_text.json"

# 原始 JSON。
var _card_setting: Dictionary = {}
var _job_dict: Dictionary = {}
var _campaign: Dictionary = {}
var _setting: Dictionary = {}
var _meta: Dictionary = {}
var _card_text: Dictionary = {}   # card_id -> {name, description, hint}

# 衍生表。
var _cards: Dictionary = {}          # card_id -> 數值字典
var _name_to_code: Dictionary = {}   # "White" -> "W"
var _card_job: Dictionary = {}       # card_id -> 職業碼（如 "ADCW" -> "ADC"）
var _card_color: Dictionary = {}     # card_id -> 色碼（如 "ADCW" -> "W"）

var _loaded: bool = false


func _init() -> void:
	if not _loaded:
		_load_all()


# --- 載入與驗證 ---

func _load_all() -> void:
	_card_setting = _load_json("card_setting.json")
	_job_dict = _load_json("job_dictionary.json")
	_campaign = _load_json("campaign_setting.json")
	_setting = _load_json("setting.json")
	_meta = _load_json("_meta.json")
	_card_text = _load_card_text()
	_validate()
	_build_cards()
	_loaded = true


# 載入顯示文字（Godot 自管，不在 balance/ 目錄）。
func _load_card_text() -> Dictionary:
	if not FileAccess.file_exists(CARD_TEXT_PATH):
		push_error("BalanceDB：缺少 " + CARD_TEXT_PATH + "（請跑 tools/gen_card_text.gd）")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARD_TEXT_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _load_json(file_name: String) -> Dictionary:
	var path := BALANCE_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("BalanceDB：缺少平衡檔案 " + path + "（請跑 tools/sync_balance.ps1）")
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BalanceDB：解析失敗 " + path)
		return {}
	return parsed


func _validate() -> void:
	# job_dictionary 三鍵。
	for key in ["colors_dict", "RGB_colors", "attack_type_tags"]:
		if not _job_dict.has(key):
			push_error("BalanceDB：job_dictionary 缺鍵 " + key)
	# campaign_setting 必要鍵。
	for key in ["thresholds", "scoring", "threat_model", "heal", "panic", "ai_delay_ms", "strategy_bonuses"]:
		if not _campaign.has(key):
			push_error("BalanceDB：campaign_setting 缺鍵 " + key)
	# card_setting：每色每職業須有 health / damage 數值。
	for color_name in _card_setting.keys():
		var jobs: Dictionary = _card_setting[color_name]
		for job in jobs.keys():
			var entry: Dictionary = jobs[job]
			for stat in ["health", "damage"]:
				if not entry.has(stat):
					push_error("BalanceDB：%s/%s 缺 %s" % [color_name, job, stat])
				elif not (typeof(entry[stat]) in [TYPE_INT, TYPE_FLOAT]):
					push_error("BalanceDB：%s/%s 的 %s 非數值" % [color_name, job, stat])


func _build_cards() -> void:
	var colors: Dictionary = _job_dict.get("colors_dict", {})
	for code in colors.keys():
		_name_to_code[colors[code]] = code
	for color_name in _card_setting.keys():
		var code: String = _name_to_code.get(color_name, "")
		if code == "":
			push_error("BalanceDB：card_setting 顏色 %s 無對應色碼" % color_name)
			continue
		var jobs: Dictionary = _card_setting[color_name]
		for job in jobs.keys():
			var card_id: String = job + code
			_cards[card_id] = jobs[job]
			_card_job[card_id] = job
			_card_color[card_id] = code
	# 特殊中立卡（CUBE 等）沿用 White 的數值，但以無色 card_id 對外查詢（見 01 §4）。
	# job_of/color_code_of 對它們回傳空字串，PieceState.make 會以 card_id 當 job。
	if _card_setting.has("White") and _card_setting["White"].has("CUBE"):
		_cards["CUBE"] = _card_setting["White"]["CUBE"]
	# LUCKYBLOCK（Green 系衍生的中立方塊）同樣以無色 card_id 對外查詢（見 02 §Green、01 §4）。
	if _card_setting.has("Green") and _card_setting["Green"].has("LUCKYBLOCK"):
		_cards["LUCKYBLOCK"] = _card_setting["Green"]["LUCKYBLOCK"]


# --- 查詢 API ---

# 取整張卡的數值字典（card_id = 職業碼 + 色碼，如 ADCW / TANKBR / SPDKG）。
func stats(card_id: String) -> Dictionary:
	if not _cards.has(card_id):
		push_error("BalanceDB：未知 card_id " + card_id)
		return {}
	return _cards[card_id]


# 取單一參數，缺鍵回傳 default。
func param(card_id: String, key: String, default: Variant = null) -> Variant:
	return stats(card_id).get(key, default)


# 取所有已註冊 card_id（含 CUBE/LUCKYBLOCK 中立別名），供表現層列舉／展示館使用。
func all_card_ids() -> Array:
	return _cards.keys()


# 取 card_id 的職業碼（如 "SPDKG" -> "SP"）；未知或特殊卡回傳空字串。
func job_of(card_id: String) -> String:
	return _card_job.get(card_id, "")


# 取 card_id 的色碼（如 "SPDKG" -> "DKG"）；未知或特殊卡回傳空字串。
func color_code_of(card_id: String) -> String:
	return _card_color.get(card_id, "")


# 取職業攻擊模式標籤字串（來自 job_dictionary.attack_type_tags）。
func attack_types(job: String) -> String:
	var tags: Dictionary = _job_dict.get("attack_type_tags", {})
	return tags.get(job, "")


# 取顏色 RGB（接受色名 "White" 或色碼 "W"），回傳 Color。
func color_rgb(color: String) -> Color:
	var rgb: Dictionary = _job_dict.get("RGB_colors", {})
	var name := color
	if not rgb.has(name):
		var colors: Dictionary = _job_dict.get("colors_dict", {})
		if colors.has(color):
			name = colors[color]
	if not rgb.has(name):
		push_error("BalanceDB：未知顏色 " + color)
		return Color.WHITE
	var parts := String(rgb[name]).split(",")
	if parts.size() < 3:
		return Color.WHITE
	return Color(
		parts[0].strip_edges().to_int() / 255.0,
		parts[1].strip_edges().to_int() / 255.0,
		parts[2].strip_edges().to_int() / 255.0)


# 以點/斜線路徑取 campaign_setting 參數，如 ai("thresholds/attack_min_score")。
func ai(path: String) -> Variant:
	var node: Variant = _campaign
	for part in path.split("/", false):
		if typeof(node) == TYPE_DICTIONARY and node.has(part):
			node = node[part]
		else:
			push_error("BalanceDB：ai 路徑無效 " + path)
			return null
	return node


# 取 setting.json 的鍵（部分共用值，如 board_size）。
func setting(key: String, default: Variant = null) -> Variant:
	return _setting.get(key, default)


# 取卡牌顯示文字 {name, description, hint}；未知 id 回傳空字典。
func text(card_id: String) -> Dictionary:
	return _card_text.get(card_id, {})


# 顯示用資料版本字串，如 "bal 4.3.0.0 @6263139bb55e"。
func data_version() -> String:
	var v: String = _meta.get("source_version", "?")
	var h: String = _meta.get("hash", "?")
	return "bal %s @%s" % [v, h]
