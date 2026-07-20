# P2-1 棋子一覽（美術預覽場景）。在 Godot 編輯器直接跑本場景（scenes/battle/piece_gallery.tscn，F6）
# 即可肉眼驗收全部棋子外觀。純展示，不依賴 GameCore；資料取自 autoload Balance。
#
# P14-5：本場景升格為**美術預覽工具**——
#   ①骨架（Background/TitleLabel/CaptionLabel/GridRoot/Camera2D）宣告於 .tscn，編輯器可視可編輯；
#   ②排版參數（左緣/上緣/欄距/列距）改 @export，美術在編輯器就能調；
#   ③**S 鍵一鍵切換「美術貼圖／幾何佔位」**，用來比對 `img/piece/card/<card_id>.png` 放圖後的效果
#     與無圖 fallback；副標題即時顯示「有貼圖 n / 全部 m」，一眼看出哪些卡還沒圖。
#
# 註（與 06 P14-5④ 原文的偏離）：原文寫「全卡×**兩視角**」，但視角（俯視/45 度）差異全在
# **BoardView 的座標換算**，PieceView 本身的外觀與視角無關（同一張圖/同一個多邊形）——
# 在本場景擺兩份會是一模一樣的兩排。故改為對美術真正有意義的「貼圖／佔位 一鍵切換」。
extends Node2D

const PieceViewScript := preload("res://scenes/battle/piece_view.gd")   # 常數（CELL_SIZE）用
const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")   # 實例化用

# 色碼 → 繁中名（沿用 02 對照表）。順序＝展示館列序。
const COLORS := [
	["W", "蒼白"], ["R", "緋紅"], ["G", "翠綠"], ["B", "蔚藍"], ["O", "橙橘"],
	["DKG", "蒼鬱"], ["C", "靛青"], ["F", "緋紫"], ["BR", "褐鏽"], ["P", "魅紫"],
]
const JOBS := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP"]
const PURPLE_JOBS := ["AP", "TANK", "HF", "ASS"]

# P14-4：展示館配色改 @export（美術可在編輯器調；預設值＝P14-4 前的常數）。
# 棋子本身的派別色一律走 Balance.color_rgb（資料驅動，不硬編）。
# 背景與標題/副標題已是 .tscn 節點（P14-5），直接在編輯器改，不再需要 @export。
@export_group("展示館配色")
## 職業欄標題文字色。
@export var job_header_color: Color = Color(0.85, 0.9, 1.0)
## 色系列標題文字色。
@export var row_label_color: Color = Color(0.9, 0.9, 0.9)
## 特殊/衍生棋子的小標題文字色。
@export var special_label_color: Color = Color(0.8, 0.8, 0.8)
@export_group("")

# P14-5：排版參數出程式（原為 LEFT/TOP/COL_STRIDE/ROW_STRIDE 四個常數）。預設值＝改版前的常數。
@export_group("排版")
## 第一欄棋子的左緣（左側留給色系名稱）。
@export var left_margin: float = 150.0
## 第一列棋子的上緣（上方留給標題與職業欄名）。
@export var top_margin: float = 96.0
## 欄距（職業之間）。
@export var col_stride: float = 120.0
## 列距（色系之間）。
@export var row_stride: float = 132.0
@export_group("")

var _background: ColorRect
var _title_label: Label
var _caption_label: Label
var _grid_root: Node2D
var _camera: Camera2D

# S 鍵切到 true 時強制使用幾何佔位形（即使有貼圖），供美術對照 fallback 外觀。
var _force_fallback: bool = false
var _sprite_count: int = 0
var _piece_count: int = 0


var _bound: bool = false


func _ready() -> void:
	_build()


# 綁定 .tscn 宣告的節點（`%` 唯一名稱；instantiate 後即可解析，不需先進場景樹 → headless 亦適用）。
func _bind() -> void:
	if _bound:
		return
	_bound = true
	_background = %Background
	_title_label = %TitleLabel
	_caption_label = %CaptionLabel
	_grid_root = %GridRoot
	_camera = %Camera2D


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		_force_fallback = not _force_fallback
		_build()


func _build() -> void:
	_bind()
	for c in _grid_root.get_children():
		c.free()
	_sprite_count = 0
	_piece_count = 0

	var content_w := left_margin + float(JOBS.size() - 1) * col_stride + PieceViewScript.CELL_SIZE + 48.0
	var special_top := top_margin + float(COLORS.size()) * row_stride + 24.0
	var content_h := special_top + row_stride + 40.0

	# 背景（.tscn 節點；尺寸依內容量動態撐開，色值在編輯器調）。
	_background.position = Vector2(-40, -40)
	_background.size = Vector2(content_w + 80, content_h + 80)

	# 職業欄位標題。
	for c in range(JOBS.size()):
		_add_text(Vector2(left_margin + float(c) * col_stride, top_margin - 26), 15,
			JOBS[c], job_header_color)

	# 逐色（列）× 逐職業（欄）。
	for r in range(COLORS.size()):
		var code: String = COLORS[r][0]
		var color_name: String = COLORS[r][1]
		var jobs: Array = PURPLE_JOBS if code == "P" else JOBS
		var row_y := top_margin + float(r) * row_stride
		_add_text(Vector2(6, row_y + 40), 15, color_name, row_label_color)
		for c in range(JOBS.size()):
			var job: String = JOBS[c]
			if not jobs.has(job):
				continue
			var owner := 1 if (c % 2 == 0) else 2   # 交錯先/後手（外框由地格呈現，此處僅資料差異）
			_add_piece(job + code, owner, Vector2(left_margin + float(c) * col_stride, row_y))

	# 特殊卡 / 衍生物列。
	_add_text(Vector2(6, special_top + 40), 15, "特殊/衍生", row_label_color)
	_add_piece("CUBE", 0, Vector2(left_margin, special_top))
	_add_text(Vector2(left_margin, special_top - 26), 13, "CUBE 方塊", special_label_color)
	_add_piece("LUCKYBLOCK", 0, Vector2(left_margin + col_stride, special_top))
	_add_text(Vector2(left_margin + col_stride, special_top - 26), 13, "LUCKYBLOCK", special_label_color)
	_add_shadow("ADC", Vector2(left_margin + col_stride * 2.0, special_top))
	_add_text(Vector2(left_margin + col_stride * 2.0, special_top - 26), 13, "SHADOW(ADC)", special_label_color)

	_caption_label.text = caption_text()
	_fit_camera(content_w, content_h)


# 副標題文字（資料版本＋貼圖統計＋操作提示）。純函式化以便 headless 斷言。
func caption_text() -> String:
	var mode := "幾何佔位（S 切回貼圖）" if _force_fallback else "美術貼圖優先（S 切幾何佔位）"
	return "%s　｜　貼圖 %d / %d　｜　來源 %s　｜　模式：%s　｜　半透明＝鏡像 SHADOW" % [
		Balance.data_version(), _sprite_count, _piece_count, ArtSlots.PIECE_DIR, mode]


func sprite_count() -> int:
	return _sprite_count


func piece_count() -> int:
	return _piece_count


func _add_piece(card_id: String, owner: int, pos: Vector2) -> void:
	var pv: Node2D = PieceViewScene.instantiate()
	pv.position = pos
	_grid_root.add_child(pv)
	pv.configure(card_id, owner, Balance)
	_after_configure(pv)


func _add_shadow(shadow_job: String, pos: Vector2) -> void:
	var pv: Node2D = PieceViewScene.instantiate()
	pv.position = pos
	_grid_root.add_child(pv)
	pv.configure("SHADOW", 1, Balance, true, shadow_job)
	_after_configure(pv)


# 統計是否吃到美術貼圖；`_force_fallback` 時強制退回幾何佔位（對照用）。
func _after_configure(pv: Node2D) -> void:
	_piece_count += 1
	if pv.has_sprite():
		_sprite_count += 1
		if _force_fallback:
			pv.apply_sprite(null)


func _add_text(pos: Vector2, font_size: int, text: String, color: Color) -> void:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_grid_root.add_child(l)


# 相機縮放至內容剛好入畫。未進場景樹（headless 測試）時無 viewport，直接略過。
func _fit_camera(content_w: float, content_h: float) -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var z: float = minf(view.x / content_w, view.y / content_h)
	_camera.zoom = Vector2(z, z)
	_camera.position = Vector2(content_w * 0.5, content_h * 0.5)
	_camera.make_current()
