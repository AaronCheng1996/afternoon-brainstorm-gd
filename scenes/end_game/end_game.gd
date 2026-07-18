# P2-5／P8-6 終局統計畫面（見 docs/rebuild/06 P2-5/P7-6/P8-6、08 §3）。
# 勝者 + 每回合分數折線（Line2D）+ 統計摘要長條 + per 玩家 per 卡的統計表格，圖／表可切換。
# 以節點繪製（headless 可建、可測）。由 battle 於對局結束時 configure() 後轉場而來。
#
# P7-6：UI 骨架宣告於 end_game.tscn（`%` 綁定），動態內容（折線→ChartLayer、長條→BarsRoot、
# 表格→TableRoot）由程式生成到宣告好的容器。
# P8-6 修正：ChartFrame 由 HUD(CanvasLayer) 移到基礎場景（Background 之後、ChartLayer 之前），
# 依樹序渲染於折線之下，解決「折線被框遮住」的 P7-6 既有問題（見 06 行為疑義登記表）。
# P8-6 資料：configure() 改收 core 的完整統計 export（`Statistics.export_for_charts()`，
# 格式 {stat_name: {owner_cardid: int}}）；摘要長條與表格皆由它派生（單一資料源）。
extends Node2D

# P12-15 連線終局：本場景亦可作為線上大廳的子場景（net 模式）。此時「再來一局／回房間」不 change_scene
# （會拆掉常駐 NetClient，§11.2-2）而改 emit 信號，由 online_lobby 主導（釋放本子場景、回房內面板）。
signal net_rematch()        # net 模式「再來一局」（→ lobby 送 rematch、回房）
signal net_back_to_room()   # net 模式「回房間」（→ lobby 釋放本子場景、回房內面板）

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const DRAFT_SCENE := "res://scenes/draft/draft.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

# 卡牌層級（key＝owner_cardid）且已被 core 追蹤的統計欄位。治療（HEALING）未被 core 追蹤
# （只有 per-player 的 HEAL_USE），故不列入 per-卡表格，見進度日誌 P8-6 說明。
const CARD_STATS := ["KILLED", "DAMAGE_DEALT", "SCORED"]
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
var _stats: Dictionary = {}       # {stat_name: {owner_cardid: int}}（export_for_charts 格式）
var _show_table: bool = false
var _replay_path: String = ""     # P11-2：本局紀錄路徑（非空才顯示「回放本局」）
var _replay_btn: Button
# P12-15 連線終局旗標：net 模式改 emit 信號（不 change_scene）；旁觀者無「再來一局」。
var _is_net: bool = false
var _net_spectator: bool = false

var _hud: CanvasLayer
var _chart_frame: ColorRect
var _chart_layer: Node2D
var _bars_root: Node2D
var _table_root: VBoxContainer
var _view_toggle: Button
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
			"KILLED": {"player1_ADCW": 3, "player2_TANKW": 1},
			"DAMAGE_DEALT": {"player1_ADCW": 24, "player1_HFW": 8, "player2_TANKW": 6},
			"SCORED": {"player1_SPW": 6, "player2_ADCW": 2},
		})


# winner: -1 平 / 0 P1 / 1 P2。stats：Statistics.export_for_charts() 格式 {stat_name: {key: int}}。
func configure(winner: int, score: int, win_threshold: int, score_history: Array, stats: Dictionary,
		replay_path: String = "") -> void:
	_winner = winner
	_score = score
	_win_threshold = maxi(1, win_threshold)
	_score_history = score_history
	_stats = stats
	_replay_path = replay_path
	_bind_nodes()
	if _replay_btn != null:
		_replay_btn.visible = _replay_path != ""
	_rebuild()


# P12-15 連線終局：以終局公開快照的統計 export 建終局統計畫面（online_lobby 嵌入為子場景）。
# 資料源＝終局快照（stats/score_history/winner/score，見 GameSnapshot）。spectator＝旁觀者（無再來一局）；
# reason＝終局原因（opponent_forfeit 時於標題加註）。按鈕改 emit net_rematch/net_back_to_room（不 change_scene）。
func boot_net(winner: int, score: int, win_threshold: int, score_history: Array,
		stats: Dictionary, spectator: bool = false, reason: String = "") -> void:
	_is_net = true
	_net_spectator = spectator
	configure(winner, score, win_threshold, score_history, stats, "")
	(%AgainBtn as Button).text = "再來一局"
	(%AgainBtn as Button).visible = not spectator   # 旁觀者無「再來一局」（唯讀）
	(%MenuBtn as Button).text = "回房間"
	if _replay_btn != null:
		_replay_btn.visible = false                 # 伺服器端回放下載＝P12-18（選做），此處不提供
	if reason == NetMessage.REASON_OPPONENT_FORFEIT and _title_label != null:
		_title_label.text += "（對手離線，判定勝出）"


func _bind_nodes() -> void:
	if _bound:
		return
	_bound = true
	_hud = %HUD
	_chart_frame = %ChartFrame
	_chart_layer = %ChartLayer
	_bars_root = %BarsRoot
	_table_root = %TableRoot
	_view_toggle = %ViewToggle
	_title_label = %TitleLabel
	_caption_label = %ChartCaption
	_view_toggle.pressed.connect(toggle_view)
	# 「再來一局／回主選單」在 net 模式改走信號（見 _on_again/_on_menu），本機模式 change_scene。
	(%AgainBtn as Button).pressed.connect(_on_again)
	(%MenuBtn as Button).pressed.connect(_on_menu)
	_replay_btn = %ReplayBtn
	_replay_btn.pressed.connect(_on_replay)


# 依 configure() 傳入的資料重繪動態內容（可重複呼叫）。
func _rebuild() -> void:
	_built = true
	for c in _chart_layer.get_children():
		c.queue_free()
	for c in _bars_root.get_children():
		c.queue_free()
	for c in _table_root.get_children():
		c.queue_free()

	var who := "先手 P1" if _winner == 0 else ("後手 P2" if _winner == 1 else "平手")
	_title_label.text = "%s 獲勝！　最終分數 %d" % [who, _score]
	_caption_label.text = "每回合分數（負＝P1 領先，正＝P2 領先；門檻 ±%d）" % _win_threshold

	_draw_score_chart()
	_draw_stat_bars()
	_build_table()
	_apply_view()


# ---------------- 圖／表切換 ----------------

func toggle_view() -> void:
	_show_table = not _show_table
	_apply_view()


func _apply_view() -> void:
	# 圖表群：折線框/折線層/摘要長條/圖說；表格群：TableRoot。
	_chart_frame.visible = not _show_table
	_chart_layer.visible = not _show_table
	_bars_root.visible = not _show_table
	_caption_label.visible = not _show_table
	_table_root.visible = _show_table
	_view_toggle.text = "切換：圖表" if _show_table else "切換：表格"


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


# ---------------- 統計摘要長條（ColorRect → BarsRoot）----------------
# 由完整 _stats 派生每類前 5 名（取代舊 battle._build_stat_bars，改為單一資料源）。

func _bars_for(stat_name: String) -> Array:
	var bucket: Dictionary = _stats.get(stat_name, {})
	var rows: Array = []
	for key: String in bucket:
		rows.append([key, int(bucket[key])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows.slice(0, 5)


func _draw_stat_bars() -> void:
	var col_x: float = 660.0
	var y: float = 170.0
	for stat_name: String in CARD_STATS:
		var rows: Array = _bars_for(stat_name)
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


# ---------------- 統計表格（GridContainer → TableRoot）----------------

# {owner_cardid: {stat_name: int}}——供表格與測試（與 Statistics 一致性斷言）。
func table_data() -> Dictionary:
	var out: Dictionary = {}
	for stat_name: String in CARD_STATS:
		var bucket: Dictionary = _stats.get(stat_name, {})
		for key: String in bucket:
			if not out.has(key):
				var row: Dictionary = {}
				for s: String in CARD_STATS:
					row[s] = 0
				out[key] = row
			out[key][stat_name] = int(bucket[key])
	return out


func _build_table() -> void:
	var data: Dictionary = table_data()
	# 依玩家分組、卡 ID 排序。
	for owner: String in ["player1", "player2"]:
		var keys: Array = []
		for key: String in data:
			if key.begins_with(owner + "_"):
				keys.append(key)
		keys.sort()
		var who := "先手 P1" if owner == "player1" else "後手 P2"
		var header := _mk_label(Vector2.ZERO, 18, 0, HORIZONTAL_ALIGNMENT_LEFT)
		header.text = "%s（%d 張出場）" % [who, keys.size()]
		header.add_theme_color_override("font_color",
			Color(0.95, 0.4, 0.4) if owner == "player1" else Color(0.45, 0.6, 1.0))
		_table_root.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 1 + CARD_STATS.size()
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 4)
		# 表頭列。
		_add_cell(grid, "卡牌", 14, Color(0.8, 0.82, 0.86), 180)
		for stat_name: String in CARD_STATS:
			_add_cell(grid, STAT_TITLES[stat_name], 14, STAT_COLORS[stat_name], 90)
		# 資料列。
		if keys.is_empty():
			_add_cell(grid, "（無出場紀錄）", 13, Color(0.6, 0.62, 0.66), 180)
			for _i in CARD_STATS.size():
				_add_cell(grid, "", 13, Color.WHITE, 90)
		for key: String in keys:
			_add_cell(grid, _short_key(key), 13, Color(0.93, 0.94, 0.96), 180)
			for stat_name: String in CARD_STATS:
				_add_cell(grid, str(data[key][stat_name]), 13, Color(0.93, 0.94, 0.96), 90)
		_table_root.add_child(grid)


func _add_cell(grid: GridContainer, txt: String, font_size: int, color: Color, min_w: float) -> void:
	var l := Label.new()
	l.text = txt
	l.custom_minimum_size = Vector2(min_w, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	grid.add_child(l)


func _short_key(key: String) -> String:
	return key.replace("player1_", "P1 ").replace("player2_", "P2 ")


# ---------------- 導覽 ----------------

# 「再來一局」：net 模式 emit 信號（lobby 送 rematch＋回房）；本機模式回選秀開新局。
func _on_again() -> void:
	if _is_net:
		net_rematch.emit()
	else:
		_change_scene(DRAFT_SCENE)


# 「回房間／回主選單」：net 模式 emit 信號（lobby 釋放子場景回房內面板）；本機模式回主選單。
func _on_menu() -> void:
	if _is_net:
		net_back_to_room.emit()
	else:
		_change_scene(MENU_SCENE)


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


# P11-2：回放本局——載入紀錄檔並以回放模式開 battle。
func _on_replay() -> void:
	var tree := get_tree()
	if tree == null or _replay_path == "":
		return
	var log: ReplayLog = ReplayLog.load_from_file(_replay_path)
	if log == null:
		return
	var battle: Node = load(BATTLE_SCENE).instantiate()
	battle.boot_replay(log, Balance)
	tree.root.add_child(battle)
	tree.current_scene = battle
	queue_free()


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
