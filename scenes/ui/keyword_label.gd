# P8-3 關鍵字高亮標籤：RichTextLabel 子類。
# 用 set_source(原始描述/提示) 灌文字，自動把機制詞上色高亮（走 KeywordDB.markup），
# 滑鼠懸停高亮詞時彈出該詞的解釋浮窗；移開收起。
# battle 棋子提示、draft 卡牌說明皆改用本元件（見 docs/rebuild/06 P8-3）。
class_name KeywordLabel
extends RichTextLabel

# P14-3：浮窗（面板＋內文）抽成 item 模板場景——美術要調浮窗底色/寬度/內距只改該檔。
const KeywordTipScene := preload("res://scenes/ui/keyword_tip.tscn")

var _tip: PanelContainer = null
var _tip_label: RichTextLabel = null


func _ready() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	meta_underlined = true
	# PASS：自身可收到懸停 meta，但不吃掉底層點擊。
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not meta_hover_started.is_connected(_on_meta_hover_started):
		meta_hover_started.connect(_on_meta_hover_started)
		meta_hover_ended.connect(_on_meta_hover_ended)


# 設定原始文字（可含既有 BBCode）；自動套關鍵字高亮。
func set_source(src: String) -> void:
	if not bbcode_enabled:
		bbcode_enabled = true
	text = KeywordDB.markup(src)


func _on_meta_hover_started(meta: Variant) -> void:
	var info: Dictionary = KeywordDB.explain(String(meta))
	if info.is_empty():
		return
	_ensure_tip()
	_tip_label.text = "[b][color=%s]%s[/color][/b]\n%s" % [info["color"], info["name"], info["text"]]
	_tip.reset_size()
	_tip.visible = true
	_reposition_tip()


func _on_meta_hover_ended(_meta: Variant) -> void:
	if _tip != null:
		_tip.visible = false


func _process(_dt: float) -> void:
	if _tip != null and _tip.visible:
		_reposition_tip()


func _ensure_tip() -> void:
	if _tip != null:
		return
	# 樣式（top_level／z_index／寬度／自動換行／不吃滑鼠）全在 item 場景裡。
	_tip = KeywordTipScene.instantiate()
	_tip_label = _tip.get_node("TipLabel")
	add_child(_tip)


# 把浮窗貼在滑鼠右下，超出視窗邊界時翻向另一側。
func _reposition_tip() -> void:
	var mouse := get_global_mouse_position()
	var vp := get_viewport_rect().size
	var sz := _tip.size
	var pos := mouse + Vector2(14, 18)
	if pos.x + sz.x > vp.x:
		pos.x = maxf(6.0, vp.x - sz.x - 6.0)
	if pos.y + sz.y > vp.y:
		pos.y = maxf(6.0, mouse.y - sz.y - 8.0)
	_tip.global_position = pos
