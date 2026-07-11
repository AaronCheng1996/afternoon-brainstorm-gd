# P2-5 終局統計畫面（見 docs/rebuild/06 P2-5/P7-6、08 §3）。
# 勝者 + 每回合分數折線（Line2D）+ 主要統計長條（ColorRect）。以節點繪製（headless 可建、可測）。
# 由 battle 於對局結束時 configure() 後轉場而來；「回主選單／重新選秀」串起流程閉環。
#
# P7-6：UI 骨架（背景/圖表框/圖層/HUD 標題/說明/長條容器/兩鈕）宣告於 end_game.tscn（編輯器可視可編輯）；
# 本腳本只用場景唯一名稱（`%NodeName`）綁定節點、連接信號；動態內容（折線→ChartLayer、長條→BarsRoot）
# 由程式生成到宣告好的容器。configure() 對外 API 不變。
extends Node2D

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const DRAFT_SCENE := "res://scenes/draft/draft.tscn"

const STAT_TITLES := {"KILLED": "擊殺", "DAMAGE_DEALT": "造成傷害", "SCORED": "得分"}
const STAT_COLORS := {
	"KILLED": Color(0.9, 0.4, 0.4),
	"DAMAGE_DEALT": Color(0.95, 0.7, 0.35),
	"SCORED": Color(0.5, 0.8, 0.6),
}

var _winner: int = -1
var _score: int = 0
var _win_threshold: int = 10
var _score_history: Array = []
var _stat_bars: Dictionary = {}   # name -> Array[[key:String, val:int]]

var _hud: CanvasLayer
var _chart_layer: Node2D
var _bars_root: Node2D
var _title_label: Label
var _caption_label: Label
var _bound: bool = false
var _built: bool = false

# 折線圖區域（世界＝螢幕座標，無 Camera）。與 .tscn 的 ChartFrame 對齊。
const CHART := Rect2(56, 150, 560, 300)


func _ready() -> void:
	if not _built:
		# 直接 F6 執行：用示範資料建畫面。
		configure(0, -10, 10, [0, -1, -3, -4, -7, -10], {
			"KILLED": [["player1_ADCW", 3], ["player2_TANKW", 1]],
			"DAMAGE_DEALT": [["player1_ADCW", 24], ["player1_HFW", 8]],
			"SCORED": [["player1_SPW", 6], ["player2_ADCW", 2]],
		})


# winner: -1 平 / 0 P1 / 1 P2。stat_bars：{stat_name: [[key,val], ...]}（已排序、取前幾名）。
func configure(winner: int, score: int, win_threshold: int, score_history: Array, stat_bars: Dictionary) -> void:
	_winner = winner
	_score = score
	_win_threshold = maxi(1, win_threshold)
	_score_history = score_history
	_stat_bars = stat_bars
	_bind_nodes()
	_rebuild()


func _bind_nodes() -> void:
	if _bound:
		return
	_bound = true
	_hud = %HUD
	_chart_layer = %ChartLayer
	_bars_root = %BarsRoot
	_title_label = %TitleLabel
	_caption_label = %ChartCaption
	(%AgainBtn as Button).pressed.connect(_change_scene.bind(DRAFT_SCENE))
	(%MenuBtn as Button).pressed.connect(_change_scene.bind(MENU_SCENE))


# 依 configure() 傳入的資料重繪動態內容（可重複呼叫）。
func _rebuild() -> void:
	_built = true
	for c in _chart_layer.get_children():
		c.queue_free()
	for c in _bars_root.get_children():
		c.queue_free()

	var who := "先手 P1" if _winner == 0 else ("後手 P2" if _winner == 1 else "平手")
	_title_label.text = "%s 獲勝！　最終分數 %d" % [who, _score]
	_caption_label.text = "每回合分數（負＝P1 領先，正＝P2 領先；門檻 ±%d）" % _win_threshold

	_draw_score_chart()
	_draw_stat_bars()


# ---------------- 折線圖（Line2D → ChartLayer）----------------

func _draw_score_chart() -> void:
	var max_abs: int = _win_threshold
	for s in _score_history:
		max_abs = maxi(max_abs, abs(int(s)))
	var mid_y: float = CHART.position.y + CHART.size.y * 0.5
	var half_h: float = CHART.size.y * 0.5 - 8.0

	# 0 線與 ±門檻線。
	_add_hline(mid_y, Color(0.5, 0.52, 0.56), 1.5)
	_add_hline(mid_y - float(_win_threshold) / float(max_abs) * half_h, Color(0.45, 0.6, 1.0, 0.7), 1.0)
	_add_hline(mid_y + float(_win_threshold) / float(max_abs) * half_h, Color(0.95, 0.45, 0.45, 0.7), 1.0)

	if _score_history.is_empty():
		return
	var n: int = _score_history.size()
	var line := Line2D.new()
	line.width = 2.5
	line.default_color = Color(0.95, 0.9, 0.55)
	for i in n:
		var x: float = CHART.position.x + (0.0 if n == 1 else float(i) / float(n - 1) * CHART.size.x)
		var y: float = mid_y - float(int(_score_history[i])) / float(max_abs) * half_h
		line.add_point(Vector2(x, y))
	_chart_layer.add_child(line)


func _add_hline(y: float, color: Color, w: float) -> void:
	var l := Line2D.new()
	l.add_point(Vector2(CHART.position.x, y))
	l.add_point(Vector2(CHART.position.x + CHART.size.x, y))
	l.width = w
	l.default_color = color
	_chart_layer.add_child(l)


# ---------------- 統計長條（ColorRect → BarsRoot）----------------

func _draw_stat_bars() -> void:
	var col_x: float = 660.0
	var y: float = 150.0
	for stat_name: String in ["KILLED", "DAMAGE_DEALT", "SCORED"]:
		var rows: Array = _stat_bars.get(stat_name, [])
		var title := _mk_label(Vector2(col_x, y), 16, 320, HORIZONTAL_ALIGNMENT_LEFT)
		title.text = STAT_TITLES.get(stat_name, stat_name)
		title.add_theme_color_override("font_color", STAT_COLORS.get(stat_name, Color.WHITE))
		_bars_root.add_child(title)
		y += 26.0
		var max_val: int = 1
		for entry: Array in rows:
			max_val = maxi(max_val, int(entry[1]))
		if rows.is_empty():
			var none := _mk_label(Vector2(col_x + 8, y), 13, 320, HORIZONTAL_ALIGNMENT_LEFT)
			none.text = "（無）"
			none.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
			_bars_root.add_child(none)
			y += 24.0
		for entry: Array in rows:
			var key: String = _short_key(String(entry[0]))
			var val: int = int(entry[1])
			var bar := ColorRect.new()
			bar.color = STAT_COLORS.get(stat_name, Color.WHITE)
			bar.position = Vector2(col_x + 4, y + 3)
			bar.size = Vector2(4.0 + float(val) / float(max_val) * 180.0, 14)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bars_root.add_child(bar)
			var lbl := _mk_label(Vector2(col_x + 200, y), 13, 160, HORIZONTAL_ALIGNMENT_LEFT)
			lbl.text = "%s  %d" % [key, val]
			_bars_root.add_child(lbl)
			y += 22.0
		y += 14.0


func _short_key(key: String) -> String:
	return key.replace("player1_", "P1 ").replace("player2_", "P2 ")


# ---------------- 導覽 ----------------

func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


# ---------------- 小工具（動態長條/標籤仍程式生成）----------------

func _mk_label(pos: Vector2, font_size: int, width: float, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.93, 0.94, 0.96))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l
