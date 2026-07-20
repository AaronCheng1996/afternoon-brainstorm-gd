# P14-4 靜態檢查：場景腳本不得有「裸」`Color(...)` 字面量。見 docs/rebuild/06 P14-4、08 §5.4。
#
# 為什麼要守：色值散在程式各處時，美術改一個顏色要翻程式、且同一語意色會在多檔各寫一份
# （P14-1 盤查：P1 紅 3 處、P2 藍 4 處、選中黃 4 處各自硬編）。P14-4 後的規則是——
#   ① 跨場景語意色（先手/後手/頁籤選中）→ theme 具名色，經 `UIPalette` 取用（單一來源）。
#   ② 單一場景自用的色 → 該場景的 `@export`（美術在編輯器就能調）。
#   ③ 派別色 → 一律 `Balance.color_rgb` 資料驅動，任何情況不得硬編。
# 因此「宣告處」（`@export var x: Color = Color(...)`）是合法的——那正是參數的容身處；
# 被禁的是**邏輯中途**憑空冒出的字面量。
#
# 例外＝下表 `WHITELIST`（「檔案→允許筆數」；新增裸字面量會讓筆數對不上而轉紅，不是憑檔名放行）。
# **P14-6 完成後白名單已清空**：原先三個檔的特效暫態色（受擊白閃、火花、投射物、命中閃光、
# 施法環/殘影）皆已改為 @export 宣告，不再有邏輯中途的裸字面量。表保留為機制，日後真有
# 無法避免的例外再填；空表時本檔即「scenes/ 全面零硬編色」的守門員。
extends RefCounted

const SCAN_DIRS := ["res://scenes"]

# 檔案 → 允許的裸 Color( 筆數（＋原因）。目前為空＝零例外。
const WHITELIST := {}


func run(t: Object) -> void:
	var offenders: Dictionary = {}   # 檔案 → 裸字面量行號陣列
	for dir_path: String in SCAN_DIRS:
		_scan_dir(dir_path, offenders)

	# 逐檔比對：白名單內比對筆數，白名單外必須為 0。
	for path: String in offenders:
		var lines: Array = offenders[path]
		var allowed: int = int(WHITELIST.get(path, 0))
		t.eq(lines.size(), allowed,
			"色彩硬編：%s 有 %d 處裸 Color(（允許 %d）→ 行 %s" % [path, lines.size(), allowed, str(lines)])

	# 白名單內的檔案若已清乾淨，提醒把它從白名單移除（避免白名單長年失真）。
	for path: String in WHITELIST:
		if not offenders.has(path):
			t.fail("白名單過期：%s 已無裸 Color(，請從 WHITELIST 移除" % path)

	# 正向斷言：確實掃到東西（避免掃描路徑打錯導致「零違規」的假綠）。
	t.ok(_scanned_files > 0, "靜態檢查：確實掃到場景腳本（%d 個檔）" % _scanned_files)


var _scanned_files: int = 0


func _scan_dir(dir_path: String, offenders: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full, offenders)
		elif entry.ends_with(".gd"):
			_scan_file(full, offenders)
		entry = dir.get_next()
	dir.list_dir_end()


# 逐行掃描；`@export` 宣告（含跨行的 Dictionary/Array 預設值）不算違規。
func _scan_file(path: String, offenders: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_scanned_files += 1
	var line_no: int = 0
	var depth: int = 0        # @export 宣告中未閉合的括號層數（跨行預設值）
	var in_export: bool = false
	while not f.eof_reached():
		var line: String = f.get_line()
		line_no += 1
		var stripped: String = line.strip_edges()

		# 進入 @export 宣告；若該行括號未閉合，後續行仍屬宣告的一部分。
		if stripped.begins_with("@export"):
			in_export = true
			depth = 0
		if in_export:
			depth += line.count("{") + line.count("[") - line.count("}") - line.count("]")
			if depth <= 0:
				in_export = false
			continue

		if stripped.begins_with("#"):
			continue
		if not line.contains("Color("):
			continue
		# `Color.WHITE` 等具名常數、以及註解中的字樣不算；只抓真正的建構呼叫。
		var code: String = line.split("#")[0]
		if not code.contains("Color("):
			continue
		if not offenders.has(path):
			offenders[path] = []
		offenders[path].append(line_no)
	f.close()
