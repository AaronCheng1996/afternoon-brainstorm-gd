# P8-3 關鍵字資料庫與 BBCode 轉換（純資料/靜態，供 KeywordLabel 與 headless 測試共用）。
# 讀 data/keywords.json（機制詞 → 顯示色＋解釋＋別名），提供：
#   - markup(src)：把描述/提示字串中的機制詞包成 [url=<key>] 高亮，
#     保留既有 BBCode 標籤與 [img] 路徑不動；貪婪長詞優先（幸運方塊 > 方塊）；
#     文字若已在既有 [color] 內，只加 [url] 供懸停、不重複上色（保留作者色）。
#   - explain(key)：回傳 {name, color, text} 供懸停浮窗顯示。
# 見 docs/rebuild/06 P8-3。此檔在 scenes/ui 下，非 script/core，不受零 Node 靜態檢查約束，
# 但本身純 RefCounted／靜態，方便 headless 測試直接呼叫。
class_name KeywordDB
extends RefCounted

const PATH := "res://data/keywords.json"

static var _loaded: bool = false
static var _entries: Dictionary = {}          # key(正規詞) -> {color, text, aliases}
static var _surface_to_key: Dictionary = {}   # 書寫法(surface) -> 正規詞
static var _surfaces_sorted: Array = []        # 全部 surface，長到短（貪婪比對用）


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_entries = {}
	_surface_to_key = {}
	_surfaces_sorted = []
	var raw := FileAccess.get_file_as_string(PATH)
	if raw.is_empty():
		push_error("KeywordDB：找不到 " + PATH)
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("KeywordDB：keywords.json 格式錯誤")
		return
	var kw: Dictionary = parsed.get("keywords", {})
	for key: String in kw:
		var e: Dictionary = kw[key]
		_entries[key] = e
		_register_surface(key, key)
		for a in e.get("aliases", []):
			_register_surface(String(a), key)
	# 依長度由長到短排序，貪婪比對時長詞優先。
	_surfaces_sorted = _surface_to_key.keys()
	_surfaces_sorted.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())


static func _register_surface(surface: String, key: String) -> void:
	if not surface.is_empty():
		_surface_to_key[surface] = key


# 把原始描述/提示（可含既有 BBCode）轉成加了關鍵字高亮的 BBCode。
static func markup(src: String) -> String:
	_ensure()
	if src.is_empty():
		return src
	var out := ""
	var i := 0
	var n := src.length()
	var in_img := false        # 目前是否在 [img]...[/img] 路徑內
	var color_depth := 0        # 巢狀 [color] 深度
	while i < n:
		var ch := src[i]
		if ch == "[":
			var close := src.find("]", i)
			if close == -1:
				out += ch
				i += 1
				continue
			var tag := src.substr(i, close - i + 1)
			out += tag
			var low := tag.to_lower()
			if low == "[img]":
				in_img = true
			elif low == "[/img]":
				in_img = false
			elif low.begins_with("[color"):
				color_depth += 1
			elif low == "[/color]":
				color_depth = max(0, color_depth - 1)
			i = close + 1
			continue
		if in_img:
			out += ch
			i += 1
			continue
		var matched := _match_at(src, i)
		if matched.is_empty():
			out += ch
			i += 1
		else:
			var key: String = _surface_to_key[matched]
			if color_depth > 0:
				# 已在既有色內：只加懸停 meta，保留作者色。
				out += "[url=%s]%s[/url]" % [key, matched]
			else:
				var col: String = String(_entries[key].get("color", "#ffffff"))
				out += "[url=%s][color=%s]%s[/color][/url]" % [key, col, matched]
			i += matched.length()
	return out


# 在 src 的 i 位置嘗試比對最長的 surface；無則回空字串。
static func _match_at(src: String, i: int) -> String:
	for s: String in _surfaces_sorted:
		if src.substr(i, s.length()) == s:
			return s
	return ""


# 懸停浮窗用：回傳該詞的 {name, color, text}；未知詞回空字典。
static func explain(key: String) -> Dictionary:
	_ensure()
	if not _entries.has(key):
		return {}
	var e: Dictionary = _entries[key]
	return {
		"name": key,
		"color": String(e.get("color", "#ffffff")),
		"text": String(e.get("text", "")),
	}
