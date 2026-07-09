# P0-4 產生 data/card_text.json 的一次性工具。
# 用法：godot --headless --path <專案根> -s tools/gen_card_text.gd
# 來源：
#   - data/balance/card_setting.json（決定 card_id 全集，與 BalanceDB 相同組合方式）
#   - data/balance/job_dictionary.json（色碼對照）
#   - data/balance/card_hints.json（提示文字 = 每卡 hint，並作為缺色的 description）
#   - setting/description.json（白/紅/綠/藍/橘 沿用 show_name 與 description；含尾逗號需清理）
# 缺色（DarkGreen/Cyan/Fuchsia/Brown/Purple）名稱依 02 §中文名對照表組合。
extends SceneTree

# description.json 派系鍵 → 色碼（僅白紅綠藍橘沿用其名稱/描述）。
const FACTION_BY_CODE := {"W": "white", "R": "red", "G": "green", "B": "blue", "O": "orange"}
# 缺色形容詞（02 §中文名對照表）。
const ADJ_BY_CODE := {"DKG": "蒼鬱", "C": "靛青", "F": "緋紫", "BR": "褐鏽", "P": "魅紫"}
# 職業 → 中文（02 §中文名對照表）。
const JOB_NAME := {
	"ADC": "射手", "AP": "法師", "TANK": "之盾", "HF": "重裝",
	"LF": "戰士", "ASS": "刺客", "APT": "守護者", "SP": "水晶",
}
# 職業碼 → description.json 內小寫鍵。
const JOB_KEY := {
	"ADC": "adc", "AP": "ap", "TANK": "tank", "HF": "hf",
	"LF": "lf", "ASS": "ass", "APT": "apt", "SP": "sp",
}
# token 卡的名稱與 card_hints 對應鍵。
const TOKEN_NAME := {"CUBE": "方塊", "LUCKYBLOCK": "幸運箱"}


func _initialize() -> void:
	var card_setting := _load("res://data/balance/card_setting.json")
	var job_dict := _load("res://data/balance/job_dictionary.json")
	var hints := _load("res://data/balance/card_hints.json")
	var desc := _load_lenient("res://setting/description.json")

	var colors: Dictionary = job_dict["colors_dict"]
	var name_to_code := {}
	for code in colors.keys():
		name_to_code[colors[code]] = code

	var out := {}
	for color_name in card_setting.keys():
		var code: String = name_to_code[color_name]
		var jobs: Dictionary = card_setting[color_name]
		for job in jobs.keys():
			var card_id: String = job + code
			out[card_id] = _make_entry(card_id, job, code, hints, desc)

	var text := JSON.stringify(out, "\t", true)
	var f := FileAccess.open("res://data/card_text.json", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("已產生 data/card_text.json，共 %d 張卡" % out.size())
	quit(0)


func _make_entry(card_id: String, job: String, code: String, hints: Dictionary, desc: Dictionary) -> Dictionary:
	var hint: String = _hint_for(card_id, job, hints)
	var name := ""
	var description := ""

	if TOKEN_NAME.has(job):
		# CUBE / LUCKYBLOCK 等 token 卡。
		name = TOKEN_NAME[job]
		description = hint
	elif FACTION_BY_CODE.has(code):
		# 白/紅/綠/藍/橘：沿用 description.json。
		var faction: String = FACTION_BY_CODE[code]
		var jkey: String = JOB_KEY.get(job, "")
		var block: Dictionary = desc.get("card", {}).get(faction, {}).get(jkey, {})
		name = block.get("show_name", "")
		description = block.get("description", "")
		if description.strip_edges() == "":
			description = hint  # 描述留空時退回提示文字
	else:
		# 缺色：名稱依對照表，描述用 card_hints。
		name = ADJ_BY_CODE.get(code, code) + JOB_NAME.get(job, job)
		description = hint

	return {"name": name, "description": description, "hint": hint}


# card_hints 以本體 job（去 token 後綴）查；CUBE/LUCKYBLOCK 用其原鍵。
func _hint_for(card_id: String, job: String, hints: Dictionary) -> String:
	if TOKEN_NAME.has(job) and hints.has(job):
		return hints[job]
	return hints.get(card_id, "")


func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text)


# 清掉尾逗號後再解析（description.json 非嚴格 JSON）。
func _load_lenient(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var re := RegEx.new()
	re.compile(",(\\s*[}\\]])")
	text = re.sub(text, "$1", true)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("無法解析 " + path)
		return {}
	return parsed
