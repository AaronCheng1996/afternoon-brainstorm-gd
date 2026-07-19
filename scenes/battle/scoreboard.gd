# P8-5 記分板元件（見 docs/rebuild/06 P8-5）。從 battle HUD 拆出的獨立、可重用記分板：
#   一眼可讀的分差 diverging 記分條、±勝利門檻進度、回合數與當前玩家、近況趨勢迷你長條。
# 分數語義（同 core）：score 為單一分差整數，負＝先手 P1 領先、正＝後手 P2 領先；
#   |score| 達 win_threshold 即該方獲勝。
# 純表現層：不引用 GameCore，資料由 update_board() 以基本型別傳入（headless 可建可測，零 core 依賴）。
# 靜態骨架宣告於 scoreboard.tscn（`%` 唯一名稱綁定，D14/08 §2）；動態長條（記分條填色／趨勢柱）
#   生成到宣告好的容器（MeterFillRoot／TrendRoot）。尺寸用常數，不依賴 headless 未必更新的 Control.size。
class_name Scoreboard
extends Control

# P14-4：先手/後手代表色為跨場景語意色，單一來源＝theme 具名色（見 UIPalette）。
# 其餘記分板專用色改 @export（美術可在編輯器調；預設值＝P14-4 前的常數）。
@export_group("記分板配色")
## 平手時的文字色。
@export var tie_color: Color = Color(0.72, 0.74, 0.78)
## 記分條中線（0 分）。
@export var mid_color: Color = Color(0.85, 0.87, 0.9)
## 趨勢圖的中線。
@export var trend_mid_color: Color = Color(0.4, 0.42, 0.46)
@export_group("")
const TREND_MAX := 8                       # 趨勢顯示最近幾回合

# 記分條與趨勢區的尺寸「預設值」。**P14-4 起改為執行期讀 scoreboard.tscn 的容器實際尺寸**
# （`MeterFillRoot`／`TrendRoot`）——改版前這四個常數與 .tscn 內的 offset 各自為政，
# 美術在編輯器把容器拉寬，程式畫出來的條仍是 470 寬。容器尺寸取不到（<=0）時退回本預設。
const METER_W := 470.0
const METER_H := 18.0
const TREND_W := 470.0
const TREND_H := 24.0

# 執行期實際採用的尺寸（`_bind()` 由容器算出）。
var _meter_w: float = METER_W
var _meter_h: float = METER_H
var _trend_w: float = TREND_W
var _trend_h: float = TREND_H

# 當前資料（供測試與外部查詢）。
var score: int = 0
var win_threshold: int = 10
var turn_number: int = 0
var current_player: String = "player1"
var score_history: Array = []

var _turn_label: Label
var _lead_label: Label
var _threshold_label: Label
var _meter_fill_root: Control
var _trend_title: Label
var _trend_root: Control
var _bound: bool = false


func _ready() -> void:
	_bind()
	# 編輯器 F6/預覽：無資料時填示範值。
	if score_history.is_empty() and turn_number == 0:
		update_board(-3, 10, 5, "player1", [0, -1, 1, -2, -3])


func _bind() -> void:
	if _bound:
		return
	_bound = true
	_turn_label = %TurnLabel
	_lead_label = %LeadLabel
	_threshold_label = %ThresholdLabel
	_meter_fill_root = %MeterFillRoot
	_trend_title = %TrendTitle
	_trend_root = %TrendRoot
	_adopt_container_sizes()


# 記分條/趨勢區的繪製尺寸取自 .tscn 容器（美術拉寬容器即生效）；取不到才用常數預設。
func _adopt_container_sizes() -> void:
	_meter_w = _meter_fill_root.size.x if _meter_fill_root.size.x > 0.0 else METER_W
	_meter_h = _meter_fill_root.size.y if _meter_fill_root.size.y > 0.0 else METER_H
	_trend_w = _trend_root.size.x if _trend_root.size.x > 0.0 else TREND_W
	_trend_h = _trend_root.size.y if _trend_root.size.y > 0.0 else TREND_H


# 對外唯一更新入口。全部以基本型別傳入（view 不依賴 core）。
func update_board(p_score: int, p_win_threshold: int, p_turn: int, p_current: String, p_history: Array) -> void:
	_bind()
	score = p_score
	win_threshold = maxi(1, p_win_threshold)
	turn_number = p_turn
	current_player = p_current
	score_history = p_history
	_refresh()


# ---------------- 查詢（測試／外部用）----------------

# 領先方：-1 平手 / 0 先手 P1 / 1 後手 P2。
func leader() -> int:
	if score < 0:
		return 0
	if score > 0:
		return 1
	return -1


func lead_amount() -> int:
	return abs(score)


func at_threshold() -> bool:
	return abs(score) >= win_threshold


# ---------------- 刷新 ----------------

func _refresh() -> void:
	# 回合列（當前玩家以其派色標示）。
	var cur_txt: String = "先手 P1" if current_player == "player1" else "後手 P2"
	_turn_label.text = "回合 %d｜當前：%s" % [turn_number, cur_txt]
	_turn_label.add_theme_color_override("font_color", UIPalette.player_color(current_player))

	# 分差讀數。
	match leader():
		0:
			_lead_label.text = "P1 領先 %d" % lead_amount()
			_lead_label.add_theme_color_override("font_color", UIPalette.player_color("player1"))
		1:
			_lead_label.text = "P2 領先 %d" % lead_amount()
			_lead_label.add_theme_color_override("font_color", UIPalette.player_color("player2"))
		_:
			_lead_label.text = "平手"
			_lead_label.add_theme_color_override("font_color", tie_color)
	if at_threshold():
		_lead_label.text += "　達門檻！"

	_threshold_label.text = "P1 勝 −%d　｜　+%d P2 勝" % [win_threshold, win_threshold]

	_rebuild_meter()
	_rebuild_trend()


# diverging 記分條：中央＝0，向左紅（P1 負分）、向右藍（P2 正分）填色；端點＝±門檻。
func _rebuild_meter() -> void:
	# 動態子節點皆為無信號 ColorRect，即時 free 安全（且 headless 無 frame 時 queue_free 不會執行）。
	for c in _meter_fill_root.get_children():
		c.free()
	var half: float = _meter_w * 0.5
	var frac: float = clampf(float(abs(score)) / float(win_threshold), 0.0, 1.0)
	# score==0 時不建填色條——fill 僅於有領先時建立並掛入（否則 ColorRect.new() 未掛樹＝孤兒洩漏）。
	if score != 0:
		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if score < 0:
			fill.color = UIPalette.player_color("player1")
			fill.position = Vector2(half - frac * half, 0.0)
		else:
			fill.color = UIPalette.player_color("player2")
			fill.position = Vector2(half, 0.0)
		fill.size = Vector2(frac * half, _meter_h)
		_meter_fill_root.add_child(fill)
	# 中線（0 分基準）。
	var mid := ColorRect.new()
	mid.color = mid_color
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.position = Vector2(half - 1.0, -2.0)
	mid.size = Vector2(2.0, _meter_h + 4.0)
	_meter_fill_root.add_child(mid)


# 近況趨勢：最近 TREND_MAX 回合的分數，中線上下發散的迷你長條（下紅＝P1、上藍＝P2）；
# 高度以 win_threshold 為滿格（超過門檻夾住），一眼看出領先幅度與往哪邊走。
func _rebuild_trend() -> void:
	for c in _trend_root.get_children():
		c.free()
	var mid_y: float = _trend_h * 0.5
	var midline := ColorRect.new()
	midline.color = trend_mid_color
	midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	midline.position = Vector2(0.0, mid_y - 0.5)
	midline.size = Vector2(_trend_w, 1.0)
	_trend_root.add_child(midline)
	if score_history.is_empty():
		return
	var start: int = maxi(0, score_history.size() - TREND_MAX)
	var shown: Array = score_history.slice(start)
	var slot: float = _trend_w / float(TREND_MAX)
	var bar_w: float = slot * 0.6
	var half_h: float = mid_y - 1.0
	for i in shown.size():
		var v: int = int(shown[i])
		var frac: float = clampf(float(abs(v)) / float(win_threshold), 0.0, 1.0)
		var bh: float = frac * half_h
		var cx: float = slot * (float(i) + 0.5)
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if v < 0:
			bar.color = UIPalette.player_color("player1")
			bar.position = Vector2(cx - bar_w * 0.5, mid_y)
			bar.size = Vector2(bar_w, bh)
		elif v > 0:
			bar.color = UIPalette.player_color("player2")
			bar.position = Vector2(cx - bar_w * 0.5, mid_y - bh)
			bar.size = Vector2(bar_w, bh)
		else:
			bar.color = tie_color
			bar.position = Vector2(cx - bar_w * 0.5, mid_y - 1.0)
			bar.size = Vector2(bar_w, 2.0)
		_trend_root.add_child(bar)


# 動態長條數（供測試斷言：中線 + 填色/趨勢柱）。
func meter_child_count() -> int:
	_bind()
	return _meter_fill_root.get_child_count()


func trend_child_count() -> int:
	_bind()
	return _trend_root.get_child_count()
