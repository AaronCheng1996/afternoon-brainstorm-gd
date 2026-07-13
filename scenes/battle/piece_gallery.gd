# P2-1 佔位美術展示館：擺出 10 色 × 8 職業 + CUBE/LUCKYBLOCK/SHADOW 一覽。
# 在 Godot 編輯器直接跑本場景（scenes/battle/piece_gallery.tscn，F6）即可肉眼驗收。
# 純展示，不依賴 GameCore；資料取自 autoload Balance。
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

const LEFT := 150.0
const TOP := 96.0
const COL_STRIDE := 120.0
const ROW_STRIDE := 132.0


func _ready() -> void:
	_build()


func _build() -> void:
	var content_w := LEFT + float(JOBS.size() - 1) * COL_STRIDE + PieceViewScript.CELL_SIZE + 48.0
	var special_top := TOP + float(COLORS.size()) * ROW_STRIDE + 24.0
	var content_h := special_top + ROW_STRIDE + 40.0

	# 背景（深色，讓幾何色塊清楚）。
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.position = Vector2(-40, -40)
	bg.size = Vector2(content_w + 80, content_h + 80)
	add_child(bg)

	# 標題 + 平衡版本 + 圖例。
	_add_text(Vector2(-8, 8), 24, HORIZONTAL_ALIGNMENT_LEFT,
		"午後激盪 — 棋子佔位美術一覽（P2-1）", Color.WHITE)
	_add_text(Vector2(-8, 40), 13, HORIZONTAL_ALIGNMENT_LEFT,
		Balance.data_version() + "　｜　外框：紅=先手 藍=後手　｜　半透明=鏡像 SHADOW", Color(0.75, 0.78, 0.82))

	# 職業欄位標題。
	for c in range(JOBS.size()):
		_add_text(Vector2(LEFT + float(c) * COL_STRIDE, TOP - 26), 15, HORIZONTAL_ALIGNMENT_LEFT,
			JOBS[c], Color(0.85, 0.9, 1.0))

	# 逐色（列）× 逐職業（欄）。
	for r in range(COLORS.size()):
		var code: String = COLORS[r][0]
		var color_name: String = COLORS[r][1]
		var jobs: Array = PURPLE_JOBS if code == "P" else JOBS
		var row_y := TOP + float(r) * ROW_STRIDE
		_add_text(Vector2(6, row_y + 40), 15, HORIZONTAL_ALIGNMENT_LEFT, color_name, Color(0.9, 0.9, 0.9))
		for c in range(JOBS.size()):
			var job: String = JOBS[c]
			if not jobs.has(job):
				continue
			var owner := 1 if (c % 2 == 0) else 2   # 交錯先/後手以展示兩種外框
			_add_piece(job + code, owner, Vector2(LEFT + float(c) * COL_STRIDE, row_y))

	# 特殊卡 / 衍生物列。
	_add_text(Vector2(6, special_top + 40), 15, HORIZONTAL_ALIGNMENT_LEFT, "特殊/衍生", Color(0.9, 0.9, 0.9))
	_add_piece("CUBE", 0, Vector2(LEFT, special_top))
	_add_text(Vector2(LEFT, special_top - 26), 13, HORIZONTAL_ALIGNMENT_LEFT, "CUBE 方塊", Color(0.8, 0.8, 0.8))
	_add_piece("LUCKYBLOCK", 0, Vector2(LEFT + COL_STRIDE, special_top))
	_add_text(Vector2(LEFT + COL_STRIDE, special_top - 26), 13, HORIZONTAL_ALIGNMENT_LEFT, "LUCKYBLOCK", Color(0.8, 0.8, 0.8))
	_add_shadow("ADC", Vector2(LEFT + COL_STRIDE * 2.0, special_top))
	_add_text(Vector2(LEFT + COL_STRIDE * 2.0, special_top - 26), 13, HORIZONTAL_ALIGNMENT_LEFT, "SHADOW(ADC)", Color(0.8, 0.8, 0.8))

	_fit_camera(content_w, content_h)


func _add_piece(card_id: String, owner: int, pos: Vector2) -> void:
	var pv: Node2D = PieceViewScene.instantiate()
	pv.position = pos
	add_child(pv)
	pv.configure(card_id, owner, Balance)


func _add_shadow(shadow_job: String, pos: Vector2) -> void:
	var pv: Node2D = PieceViewScene.instantiate()
	pv.position = pos
	add_child(pv)
	pv.configure("SHADOW", 1, Balance, true, shadow_job)


func _add_text(pos: Vector2, font_size: int, align: int, text: String, color: Color) -> void:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)


func _fit_camera(content_w: float, content_h: float) -> void:
	var view := get_viewport_rect().size
	var z: float = minf(view.x / content_w, view.y / content_h)
	var cam := Camera2D.new()
	cam.zoom = Vector2(z, z)
	cam.position = Vector2(content_w * 0.5, content_h * 0.5)
	add_child(cam)
	cam.make_current()
