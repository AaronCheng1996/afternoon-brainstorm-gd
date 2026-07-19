# P8-4 百科圖鑑（見 docs/rebuild/06 P8-4）。遊戲內全卡瀏覽：
#   - 左側：色系分頁（10 色）＋職業篩選（全部／8 職業）→ 卡片清單（GridContainer）。
#   - 右側：單卡詳情——名稱、生命/攻擊/費用、攻擊模式圖示（img/UI/attack_pattern/）、
#     能力描述（KeywordLabel 機制詞高亮，可再懸停看解釋）、PieceView 佔位圖預覽、
#     衍生物連結（描述含「影子/鏡像」→ SHADOW；含「幸運方塊」→ LUCKYBLOCK，可點切換）。
# 資料全走 autoload Balance（stats/text/attack_types/color_rgb/job_of/color_code_of/all_card_ids），
# 卡清單由 Balance 列舉（依色碼篩選）而非硬編碼職業表，故新增卡不用改本檔。
# D14/08 §2：靜態 UI 骨架宣告於 encyclopedia.tscn（`%` 唯一名稱綁定），動態集合生成到宣告好的容器。
extends Node2D

const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")

# P14-3：清單列/頁籤/圖示的樣式抽成 item 模板場景（美術可單開檔案調樣式；程式只填資料與信號）。
const CardRowScene := preload("res://scenes/encyclopedia/card_row_button.tscn")
const ColorTabScene := preload("res://scenes/encyclopedia/color_tab_button.tscn")
const JobTabScene := preload("res://scenes/encyclopedia/job_tab_button.tscn")
const DerivButtonScene := preload("res://scenes/encyclopedia/deriv_button.tscn")
const AttackIconScene := preload("res://scenes/encyclopedia/attack_icon.tscn")

# 色碼 → 繁中名（沿用 02 對照表 / piece_gallery / draft）。分頁順序。
const COLORS := [
	["W", "蒼白"], ["R", "緋紅"], ["G", "翠綠"], ["B", "蔚藍"], ["O", "橙橘"],
	["DKG", "蒼鬱"], ["C", "靛青"], ["F", "緋紫"], ["BR", "褐鏽"], ["P", "魅紫"],
]
# 職業排序／篩選按鈕（"" = 全部）。魅紫（Purple）只有 4 職業為實卡（沿用 gallery/draft 慣例；
# card_setting 內 Purple 另有 4 個佔位條目無描述，不列入瀏覽）。
const JOB_ORDER := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP"]
const PURPLE_JOBS := ["AP", "TANK", "HF", "ASS"]

# 攻擊模式標籤（來自 job_dictionary.attack_type_tags）→ img/UI/attack_pattern/ 圖示檔名。
# 純表現層對照（非卡牌平衡資料）；test_encyclopedia 會驗每個實際使用到的 tag 都有對應圖檔。
const ATTACK_ICON := {
	"large_cross": "large_cross", "large_x": "large_x",
	"small_cross": "cross", "small_x": "x",
	"nearest": "near", "farthest": "far",
	"nearby": "nearby", "all": "all", "None": "none",
}
const ATTACK_ICON_DIR := "res://img/UI/attack_pattern/"

# 衍生物偵測：描述含 surface 任一詞 → 顯示可點連結。
const DERIVATIVES := [
	{"id": "SHADOW", "label": "影子 SHADOW", "surfaces": ["影子", "鏡像"]},
	{"id": "LUCKYBLOCK", "label": "幸運方塊", "surfaces": ["幸運方塊"]},
]

# 只在詳情列顯示的通用數值（其餘機制參數留給描述，避免資訊噪音）。
const STAT_FIELDS := [["health", "生命"], ["damage", "攻擊"], ["cost", "費用"]]

var _db: Object = null
var _selected_color: int = 0
var _job_filter: String = ""        # "" = 全部
var _current_id: String = ""

var _ui_built: bool = false
var _color_tabs: HBoxContainer
var _job_tabs: HBoxContainer
var _card_grid: GridContainer
var _preview_root: Node2D
var _detail_name: Label
var _detail_stats: Label
var _attack_caption: Label
var _attack_icons: HBoxContainer
var _detail_desc: RichTextLabel      # KeywordLabel（keyword_label.gd）
var _deriv_caption: Label
var _deriv_row: HBoxContainer
var _color_tab_btns: Array = []
var _job_tab_btns: Array = []


func _ready() -> void:
	if not _ui_built:
		boot()


# 對外啟動（供主選單呼叫，或 headless 測試直接呼叫）。
func boot(db: Object = null) -> void:
	_db = db if db != null else Balance
	_selected_color = 0
	_job_filter = ""
	_current_id = ""
	_bind_nodes()
	_build_color_tabs()
	_build_job_tabs()
	_refresh()


# ---------------- 節點綁定 ----------------

func _bind_nodes() -> void:
	if _ui_built:
		return
	_ui_built = true
	_color_tabs = %ColorTabs
	_job_tabs = %JobTabs
	_card_grid = %CardGrid
	_preview_root = %PreviewRoot
	_detail_name = %DetailName
	_detail_stats = %DetailStats
	_attack_caption = %AttackCaption
	_attack_icons = %AttackIcons
	_detail_desc = %DetailDesc
	_deriv_caption = %DerivCaption
	_deriv_row = %DerivRow
	(%BackBtn as Button).pressed.connect(_on_back)


func _build_color_tabs() -> void:
	if not _color_tab_btns.is_empty():
		return
	for i in COLORS.size():
		var b: Button = ColorTabScene.instantiate()   # 樣式在 item 場景
		b.text = COLORS[i][1]
		var col: Color = _db.color_rgb(COLORS[i][0])
		b.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.35))
		b.pressed.connect(_select_color.bind(i))
		_color_tabs.add_child(b)
		_color_tab_btns.append(b)


func _build_job_tabs() -> void:
	if not _job_tab_btns.is_empty():
		return
	_add_job_btn("全部", "")
	for job: String in JOB_ORDER:
		_add_job_btn(job, job)


func _add_job_btn(label: String, job: String) -> void:
	var b: Button = JobTabScene.instantiate()   # 樣式在 item 場景
	b.text = label
	b.pressed.connect(_select_job.bind(job))
	_job_tabs.add_child(b)
	_job_tab_btns.append(b)


# ---------------- 回呼 ----------------

func _select_color(i: int) -> void:
	_selected_color = i
	_refresh()


func _select_job(job: String) -> void:
	_job_filter = job
	_refresh()


func _on_back() -> void:
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file("res://scenes/menu/main_menu.tscn")


# ---------------- 清單 ----------------

func _refresh() -> void:
	if not _ui_built:
		return
	for i in _color_tab_btns.size():
		_color_tab_btns[i].modulate = UIPalette.tab_tint(i == _selected_color)
	for i in _job_tab_btns.size():
		var job: String = "" if i == 0 else JOB_ORDER[i - 1]
		_job_tab_btns[i].modulate = UIPalette.tab_tint(job == _job_filter)
	_rebuild_grid()


# 依當前色系（＋職業篩選）列出實卡：職業 + 色碼組出 card_id（JOB_ORDER 順序）。
func _cards_for_color() -> Array:
	var code: String = COLORS[_selected_color][0]
	var jobs: Array = PURPLE_JOBS if code == "P" else JOB_ORDER
	var out: Array = []
	for job: String in jobs:
		if _job_filter != "" and job != _job_filter:
			continue
		out.append(job + code)
	return out


func _rebuild_grid() -> void:
	for c in _card_grid.get_children():
		c.queue_free()
	var ids: Array = _cards_for_color()
	for id: String in ids:
		_card_grid.add_child(_mk_card_button(id))
	# 保持有選中的詳情：目前選中不在清單時，改選第一張。
	if not ids.has(_current_id):
		if ids.size() > 0:
			_show_detail(ids[0])
		else:
			_clear_detail()


func _mk_card_button(id: String) -> Button:
	var info: Dictionary = _db.text(id)
	var b: Button = CardRowScene.instantiate()   # 樣式（尺寸/字級/靠左對齊）在 item 場景
	b.text = String(info.get("name", id))
	b.pressed.connect(_show_detail.bind(id))
	return b


# ---------------- 詳情 ----------------

func _show_detail(id: String) -> void:
	_current_id = id
	var info: Dictionary = _db.text(id)
	_detail_name.text = "%s　（%s）" % [String(info.get("name", id)), id]
	_detail_stats.text = _format_stats(_db.stats(id))
	_rebuild_attack_icons(_db.job_of(id))
	var desc: String = String(info.get("description", ""))
	if desc.strip_edges().is_empty():
		desc = String(info.get("hint", ""))
	_detail_desc.set_source(desc)
	_rebuild_preview(id, false, "")
	_rebuild_derivatives(desc + "\n" + String(info.get("hint", "")))


func _clear_detail() -> void:
	_current_id = ""
	_detail_name.text = "（此篩選無卡片）"
	_detail_stats.text = ""
	_detail_desc.set_source("")
	for c in _attack_icons.get_children():
		c.queue_free()
	for c in _preview_root.get_children():
		c.queue_free()
	_hide_derivatives()


func _format_stats(st: Dictionary) -> String:
	var parts: Array = []
	for field: Array in STAT_FIELDS:
		if st.has(field[0]):
			parts.append("%s %s" % [field[1], str(st[field[0]])])
	return "　".join(parts)


func _rebuild_attack_icons(job: String) -> void:
	for c in _attack_icons.get_children():
		c.queue_free()
	var tags: String = _db.attack_types(job) if job != "" else ""
	var tokens: PackedStringArray = tags.split(" ", false)
	if tokens.is_empty():
		_attack_caption.text = "攻擊範圍：—"
		return
	_attack_caption.text = "攻擊範圍"
	for tok: String in tokens:
		var file_name: String = ATTACK_ICON.get(tok, "")
		if file_name.is_empty():
			continue
		var path: String = ATTACK_ICON_DIR + file_name + ".png"
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			continue
		var tr: TextureRect = AttackIconScene.instantiate()   # 尺寸/縮放模式在 item 場景
		tr.texture = tex
		tr.tooltip_text = tok
		_attack_icons.add_child(tr)


func _rebuild_preview(id: String, shadow: bool, shadow_job: String) -> void:
	for c in _preview_root.get_children():
		c.queue_free()
	var pv: Node2D = PieceViewScene.instantiate()
	_preview_root.add_child(pv)
	pv.configure(id, 1, _db, shadow, shadow_job)


func _rebuild_derivatives(text: String) -> void:
	for c in _deriv_row.get_children():
		c.queue_free()
	var shown: bool = false
	for d: Dictionary in DERIVATIVES:
		var hit: bool = false
		for s: String in d["surfaces"]:
			if text.contains(s):
				hit = true
				break
		if not hit:
			continue
		shown = true
		var b: Button = DerivButtonScene.instantiate()   # 樣式在 item 場景
		b.text = d["label"]
		b.pressed.connect(_show_derivative.bind(String(d["id"])))
		_deriv_row.add_child(b)
	_deriv_caption.visible = shown
	_deriv_row.visible = shown


func _hide_derivatives() -> void:
	for c in _deriv_row.get_children():
		c.queue_free()
	_deriv_caption.visible = false
	_deriv_row.visible = false


# 點衍生物連結 → 顯示該衍生物的預覽與說明（衍生物無 card_text，用內建說明；
# SHADOW 以當前本體職業取形狀、半透明呈現）。source_id 為當前正在看的本體。
func _show_derivative(deriv_id: String) -> void:
	var source_id: String = _current_id
	match deriv_id:
		"SHADOW":
			_detail_name.text = "影子（SHADOW）"
			_detail_stats.text = "由本體代打的鏡像分身"
			_detail_desc.set_source("[color=#c9a0ff]鏡像[/color]：緋紫（Fuchsia）於對稱位生成的影子。"
				+ "\n攻擊由本體代打、移動與本體同步；不進入棋盤目標池。")
			_rebuild_attack_icons(_db.job_of(source_id))
			_rebuild_preview("SHADOW", true, _db.job_of(source_id))
		"LUCKYBLOCK":
			var st: Dictionary = _db.stats("LUCKYBLOCK") if _db.all_card_ids().has("LUCKYBLOCK") else {}
			_detail_name.text = "幸運方塊（LUCKYBLOCK）"
			_detail_stats.text = _format_stats(st)
			_detail_desc.set_source("[color=#33ff33]幸運方塊[/color]：翠綠（Green）生成的中立方塊，"
				+ "\n被擊殺時觸發好／壞運事件。")
			_rebuild_attack_icons("")
			_rebuild_preview("LUCKYBLOCK", false, "")
		_:
			return
