# P2-2 演出示範場景：用真實 GameCore 讓一隻 ADC 大十字攻擊三個目標，
# 觀察「三目標依 0.32s 間隔逐一中彈」（箭矢投射物＋命中閃光＋飄字＋被擊閃爍＋最後一個死亡淡出）。
# 操作：空白鍵=重播；I=切換動畫開關（瞬時模式）。在編輯器對本場景按 F6 執行。
extends Node2D

const PieceViewScript := preload("res://scenes_v2/battle/piece_view.gd")
const SchedulerScript := preload("res://script_v2/view/combat_scheduler.gd")
const AnimSetScript := preload("res://script_v2/view/piece_animation_set.gd")

const CELL := 96.0
const STRIDE := 116.0
const ORIGIN := Vector2(180, 180)

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
var _views: Dictionary = {}       # Vector2i -> PieceViewV2
var _instant: bool = false
var _status_label: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.size = Vector2(1024, 768)
	add_child(bg)

	_add_grid()
	_add_text(Vector2(16, 12), 22, "午後激盪 — 攻擊演出示範（P2-2）", Color.WHITE)
	_add_text(Vector2(16, 44), 14, "空白鍵＝重播　　I＝切換動畫開關（瞬時）", Color(0.75, 0.8, 0.85))
	_status_label = _add_text(Vector2(16, 68), 14, "", Color(0.7, 0.9, 0.7))

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

	var db: Object = load("res://script_v2/data/balance_db.gd").new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	var core := GameCore.new()
	core.setup(deck, deck, 1, db)

	var attacker := _place(core, "ADCW", "player1", ATTACKER_POS)
	_make_view(ATTACKER_POS, "ADCW", 1, AnimSetScript.adc_ranged())
	for entry in TARGETS:
		var pos: Vector2i = entry[0]
		var cid: String = entry[1]
		_place(core, cid, "player2", pos)
		_make_view(pos, cid, 2, null)

	_scheduler.instant = _instant
	CombatV2.attack(core, attacker)
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
	var v: Node2D = PieceViewScript.new()
	v.position = ORIGIN + Vector2(pos) * STRIDE
	_board_layer.add_child(v)
	v.configure(card_id, owner, Balance)
	if aset != null:
		v.set_animation_set(aset)
	_views[pos] = v


func _view_at(pos: Vector2i) -> Node:
	return _views.get(pos, null)


func _cell_center(pos: Vector2i) -> Vector2:
	return ORIGIN + Vector2(pos) * STRIDE + Vector2(CELL, CELL) * 0.5


func _add_grid() -> void:
	for i in range(5):
		var h := Line2D.new()
		h.add_point(ORIGIN + Vector2(0, i * STRIDE))
		h.add_point(ORIGIN + Vector2(4 * STRIDE, i * STRIDE))
		h.width = 1.5
		h.default_color = Color(0.3, 0.32, 0.36)
		add_child(h)
		var vline := Line2D.new()
		vline.add_point(ORIGIN + Vector2(i * STRIDE, 0))
		vline.add_point(ORIGIN + Vector2(i * STRIDE, 4 * STRIDE))
		vline.width = 1.5
		vline.default_color = Color(0.3, 0.32, 0.36)
		add_child(vline)


func _add_text(pos: Vector2, font_size: int, text: String, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l
