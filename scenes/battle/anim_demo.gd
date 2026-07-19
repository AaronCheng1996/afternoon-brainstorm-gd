# P2-2 演出示範場景：用真實 GameCore 讓一隻 ADC 大十字攻擊三個目標，
# 觀察「三目標依 0.32s 間隔逐一中彈」（箭矢投射物＋命中閃光＋飄字＋被擊閃爍＋最後一個死亡淡出）。
# 操作：空白鍵=重播；I=切換動畫開關（瞬時模式）。在編輯器對本場景按 F6 執行。
extends Node2D

const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")
const SchedulerScript := preload("res://script/view/combat_scheduler.gd")
const AnimSetScript := preload("res://script/view/piece_animation_set.gd")
const AnimLibScript := preload("res://script/view/piece_animation_library.gd")   # P9-3

# P14-2：本示範場景自帶一套棋盤幾何（與對戰場景的 BoardView 各自為政——這裡是固定正交小盤，
# 不切視角）。改為 @export 讓美術在編輯器調整；預設值＝改版前的常數。
@export_group("配色")
## 背景底色。
@export var bg_color: Color = Color(0.10, 0.11, 0.13)
## 格線顏色。
@export var grid_color: Color = Color(0.3, 0.32, 0.36)
## 操作說明文字色。
@export var help_text_color: Color = Color(0.75, 0.8, 0.85)
## 狀態列文字色。
@export var status_text_color: Color = Color(0.7, 0.9, 0.7)
@export_group("")
@export_group("棋盤幾何")
## 棋子佔位方形的邊長（應與 `PieceView.CELL_SIZE` 一致）。
@export var cell_size: float = 96.0
## 格距（像素）。
@export var stride: float = 116.0
## 棋盤左上角原點。
@export var origin: Vector2 = Vector2(180, 180)
@export_group("")

# 攻擊者與三個目標（同一直行 → 大十字命中）。第三個低血量以示範死亡淡出。
const ATTACKER_POS := Vector2i(1, 1)
const TARGETS := [
	[Vector2i(1, 0), "TANKW"],   # 15HP 存活
	[Vector2i(1, 2), "TANKW"],   # 15HP 存活
	[Vector2i(1, 3), "ASSW"],    # 2HP 被擊殺
]

var _scheduler: Node
var _board_layer: Node2D
var _fx_layer: Node2D
var _views: Dictionary = {}       # Vector2i -> PieceView
var _instant: bool = false
var _status_label: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = bg_color
	bg.size = Vector2(1024, 768)
	add_child(bg)

	_add_grid()
	_add_text(Vector2(16, 12), 22, "午後激盪 — 攻擊演出示範（P2-2）", Color.WHITE)
	_add_text(Vector2(16, 44), 14, "空白鍵＝重播　　I＝切換動畫開關（瞬時）", help_text_color)
	_status_label = _add_text(Vector2(16, 68), 14, "", status_text_color)

	_board_layer = Node2D.new()
	_board_layer.name = "BoardLayer"
	add_child(_board_layer)
	_fx_layer = Node2D.new()
	_fx_layer.name = "FxLayer"
	add_child(_fx_layer)

	_scheduler = SchedulerScript.new()
	_scheduler.name = "CombatScheduler"
	add_child(_scheduler)
	_scheduler.setup(Callable(self, "_view_at"), _fx_layer, Callable(self, "_cell_center"))
	_scheduler.on_kill = Callable(self, "_shake")   # P9-2：擊殺鏡頭震動

	_run()


func _process(_delta: float) -> void:
	if _status_label != null:
		var mode := "瞬時（動畫關）" if _instant else "逐格（動畫開）"
		_status_label.text = "模式：%s　｜　排程忙碌：%s" % [mode, str(_scheduler.is_busy())]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_run()
		elif event.keycode == KEY_I:
			_instant = not _instant
			_run()


func _run() -> void:
	# 清場重建（重播用）。
	for c in _board_layer.get_children():
		c.free()
	for c in _fx_layer.get_children():
		c.free()
	_views.clear()

	var db: Object = load("res://script/data/balance_db.gd").new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	var core := GameCore.new()
	core.setup(deck, deck, 1, db)

	var attacker := _place(core, "ADCW", "player1", ATTACKER_POS)
	_make_view(ATTACKER_POS, "ADCW", 1, null)   # P9-3：改由 AnimLibrary 依攻擊模式決定（ADC=遠程）
	for entry in TARGETS:
		var pos: Vector2i = entry[0]
		var cid: String = entry[1]
		_place(core, cid, "player2", pos)
		_make_view(pos, cid, 2, null)

	_scheduler.instant = _instant
	Combat.attack(core, attacker)
	var events: Array = core.drain_events()
	_scheduler.play_events(events)
	db.free()


func _place(core: GameCore, card_id: String, owner: String, pos: Vector2i) -> PieceState:
	var p := PieceState.make(card_id, owner, pos.x, pos.y, core.balance)
	p.set_numb(false)
	core.get_player(owner).on_board.append(p)
	core.board.set_occupied(pos, true)
	return p


func _make_view(pos: Vector2i, card_id: String, owner: int, aset: Resource) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	v.position = origin + Vector2(pos) * stride
	_board_layer.add_child(v)
	v.fx_layer = _fx_layer   # P9-2：命中/死亡粒子與殘影掛 fx 層
	v.configure(card_id, owner, Balance)
	# P9-3：未指定則由 AnimLibrary 依攻擊模式（遠程/近戰）＋派別色決定佔位演出。
	v.set_animation_set(aset if aset != null else AnimLibScript.for_card(card_id, Balance))
	_views[pos] = v


func _view_at(pos: Vector2i) -> Node:
	return _views.get(pos, null)


# P9-2：擊殺鏡頭震動示範（震棋盤與特效層，衰減歸位）。
func _shake() -> void:
	if _instant:
		return
	for layer: Node2D in [_board_layer, _fx_layer]:
		var tw: Tween = layer.create_tween()
		for i in 5:
			var damp := 6.0 * (1.0 - float(i) / 5.0)
			tw.tween_property(layer, "position",
				Vector2(randf_range(-damp, damp), randf_range(-damp, damp)), 0.03)
		tw.tween_property(layer, "position", Vector2.ZERO, 0.04)


func _cell_center(pos: Vector2i) -> Vector2:
	return origin + Vector2(pos) * stride + Vector2(cell_size, cell_size) * 0.5


func _add_grid() -> void:
	for i in range(5):
		var h := Line2D.new()
		h.add_point(origin + Vector2(0, i * stride))
		h.add_point(origin + Vector2(4 * stride, i * stride))
		h.width = 1.5
		h.default_color = grid_color
		add_child(h)
		var vline := Line2D.new()
		vline.add_point(origin + Vector2(i * stride, 0))
		vline.add_point(origin + Vector2(i * stride, 4 * stride))
		vline.width = 1.5
		vline.default_color = grid_color
		add_child(vline)


func _add_text(pos: Vector2, font_size: int, text: String, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l
