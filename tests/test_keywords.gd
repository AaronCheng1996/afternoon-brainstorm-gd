# P8-3 關鍵字系統驗收：
#  1) keywords.json 每筆 entry 格式正確（color 為 #RRGGBB、text 非空）。
#  2) KeywordDB.markup 轉換正確（保留既有 BBCode 與 [img] 路徑、機制詞包 [url]、
#     貪婪長詞優先、既有色內只加 url 不重複上色、空字串原樣）。
#  3) 覆蓋度：card_text 實際出現的機制詞，markup 皆能辨識（REQUIRED 表；且確實出現於 card_text）。
# 見 docs/rebuild/06 P8-3。KeywordDB 為全域 class_name，直接呼叫（跑前先 --import 重建 class cache）。
extends RefCounted

# card_text 中確實出現、且應被關鍵字系統辨識的機制詞（開發掃描 data/card_text.json 得出，出現次數 > 0）。
const REQUIRED := [
	"麻痺", "麻痹", "暈眩", "護盾", "斬殺", "圖騰", "刻印", "藍球",
	"運氣", "運氣值", "幸運值", "好運", "壞運", "金幣", "打劫",
	"影子", "本體", "方塊", "幸運方塊", "幸運箱", "幸運寶箱", "攻擊力", "移動",
]


func run(t: Object) -> void:
	_test_entries_wellformed(t)
	_test_markup(t)
	_test_coverage(t)
	_test_card_text_scan(t)


func _test_entries_wellformed(t: Object) -> void:
	var raw := FileAccess.get_file_as_string("res://data/keywords.json")
	t.ok(not raw.is_empty(), "keywords.json 存在")
	var parsed: Variant = JSON.parse_string(raw)
	t.ok(parsed is Dictionary, "keywords.json 為物件")
	var kw: Dictionary = (parsed as Dictionary).get("keywords", {})
	t.ok(kw.size() >= 15, "關鍵字數量足夠（>=15）")
	var hex := RegEx.new()
	hex.compile("^#[0-9A-Fa-f]{6}$")
	for key: String in kw:
		var e: Dictionary = kw[key]
		t.ok(hex.search(String(e.get("color", ""))) != null, "color 合法 " + key)
		t.ok(not String(e.get("text", "")).strip_edges().is_empty(), "text 非空 " + key)


func _test_markup(t: Object) -> void:
	# 純文字關鍵字 → 包 url + 關鍵字色。
	var m1 := KeywordDB.markup("護盾")
	t.ok(m1.contains("[url=護盾]") and m1.contains("[/url]"), "護盾 被標記為 url")
	t.ok(m1.contains("[color="), "未著色文字補上關鍵字色")

	# [img] 路徑原樣保留；色標籤內文字仍可懸停但不重複上色。
	var src := "[img]res://img/UI/buff/blue_charge.png[/img][color='orange']藍球[/color]"
	var m2 := KeywordDB.markup(src)
	t.ok(m2.contains("res://img/UI/buff/blue_charge.png"), "img 路徑保留不被拆")
	t.ok(m2.contains("[url=藍球]藍球[/url]"), "色內只加 url、不重上色")

	# 貪婪長詞優先：幸運方塊 整體標記，不先標短詞 方塊。
	var m3 := KeywordDB.markup("幸運方塊")
	t.ok(m3.contains("[url=幸運方塊]"), "貪婪長詞優先命中 幸運方塊")
	t.ok(not m3.contains("[url=方塊]"), "不拆成短詞 方塊")

	# 別名映射到正規詞：暈眩 → 麻痺、幸運箱 → 幸運方塊。
	t.ok(KeywordDB.markup("暈眩").contains("[url=麻痺]"), "別名 暈眩 映射 麻痺")
	t.ok(KeywordDB.markup("幸運箱").contains("[url=幸運方塊]"), "別名 幸運箱 映射 幸運方塊")

	# 既有 BBCode 標籤名不被當文字掃描。
	var m4 := KeywordDB.markup("[b]斬殺[/b]")
	t.ok(m4.begins_with("[b]") and m4.contains("[/b]"), "既有 BBCode 保留")
	t.ok(m4.contains("[url=斬殺]"), "斬殺 被標記")

	# 空字串原樣。
	t.eq(KeywordDB.markup(""), "", "空字串原樣")


func _test_coverage(t: Object) -> void:
	for w: String in REQUIRED:
		t.ok(KeywordDB.markup(w).contains("[url="), "機制詞可辨識：" + w)


func _test_card_text_scan(t: Object) -> void:
	var raw := FileAccess.get_file_as_string("res://data/card_text.json")
	var d: Dictionary = JSON.parse_string(raw)
	var blob := ""
	for cid: String in d:
		var e: Dictionary = d[cid]
		blob += String(e.get("description", "")) + "\n" + String(e.get("hint", "")) + "\n"
	for w: String in REQUIRED:
		t.ok(blob.contains(w), "REQUIRED 確實出現於 card_text：" + w)
