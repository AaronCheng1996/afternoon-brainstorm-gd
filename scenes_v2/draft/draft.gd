# P2-4 選秀 BP 場景（本機模式）。見 docs/rebuild/06 P2-4、01 §9。
# 一切行動經 DraftDispatcherV2.dispatch(DraftActionV2, DraftStateV2)（純邏輯核心）。
# 三階段 p1_first6 → p2_pick12 → p1_last6 → done；完成後帶雙方牌組進 battle.tscn。
# UI 全程程式建立（headless 可實例化並直接呼叫行動方法測試）。
extends Node2D

const BattleScene := preload("res://scenes_v2/battle/battle.tscn")

# 色碼 → 繁中名（沿用 02 對照表 / piece_gallery）。分頁順序。
const COLORS := [
	["W", "蒼白"], ["R", "緋紅"], ["G", "翠綠"], ["B", "蔚藍"], ["O", "橙橘"],
	["DKG", "蒼鬱"], ["C", "靛青"], ["F", "緋紫"], ["BR", "褐鏽"], ["P", "魅紫"],
]
const JOBS := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP"]
const PURPLE_JOBS := ["AP", "TANK", "HF", "ASS"]
const EXHIBIT_MAGIC := ["CUBES", "HEAL", "MOVE"]   # 魔法列（MOVEO 為臨時卡不入選秀）

const PHASE_TEXT := {
	"p1_first6": "階段 1／3：先手 P1 選前 6 張（≥6）",
	"p2_pick12": "階段 2／3：後手 P2 選滿 12 張",
	"p1_last6": "階段 3／3：先手 P1 補滿 12 張",
	"done": "完成",
}

var _state: DraftStateV2
var _dispatcher: DraftDispatcherV2
var _db: Object = null
var _seed: int = 0
var _selected_color: int = 0
var _message: String = ""
var _ready_to_start: bool = false

# UI
var _hud: CanvasLayer
var _ui_built: bool = false
var _phase_label: Label
var _msg_label: Label
var _exhibit_box: GridContainer
var _magic_box: HBoxContainer
var _p1_panel: VBoxContainer
var _p2_panel: VBoxContainer
var _advance_btn: Button
var _timer_btn: Button
var _file_btn: Button
var _color_tabs: Array = []


func _ready() -> void:
	if _state == null:
		boot(0)


# 對外啟動（供主選單之後呼叫，或 headless 測試直接呼叫）。
func boot(seed_value: int, db: Object = null) -> void:
	_db = db if db != null else Balance
	_seed = seed_value
	_state = DraftStateV2.new()
	_dispatcher = DraftDispatcherV2.new()
	_selected_color = 0
	_message = ""
	_ready_to_start = false
	_build_ui()
	_refresh()


# ---------------- 行動（唯一入口）----------------

func _dispatch(action_type: String, card_name: String = "") -> DraftResultV2:
	# 回合限定行動的 player 一律為當前可編輯玩家；切換類不受限（沿用同一 player 欄位）。
	var editor: String = _state.current_editor()
	var action := DraftActionV2.new(editor, action_type, card_name)
	var r: DraftResultV2 = _dispatcher.dispatch(action, _state)
	return r


func _on_exhibit_pressed(card_id: String) -> void:
	var r := _dispatch("add_card", card_id)
	_message = "" if r.success else _localize_msg(r.message)
	_refresh()


func _on_deck_card_pressed(owner: String, card_id: String) -> void:
	if owner != _state.current_editor():
		_message = "非當前選手的牌組，無法移除"
		_refresh()
		return
	var r := _dispatch("remove_card", card_id)
	_message = "" if r.success else _localize_msg(r.message)
	_refresh()


func _on_remove_last() -> void:
	var r := _dispatch("remove_last_card")
	_message = "" if r.success else _localize_msg(r.message)
	_refresh()


func _on_advance() -> void:
	var r := _dispatch("advance_phase")
	if r.ready_to_start:
		_ready_to_start = true
		_start_battle()
		return
	_message = "" if r.success else _localize_msg(r.message)
	_refresh()


func _on_toggle_timer() -> void:
	_dispatch("toggle_timer")
	_refresh()


func _on_toggle_file() -> void:
	_dispatch("toggle_file_save")
	_refresh()


func _select_color(i: int) -> void:
	_selected_color = i
	_refresh()


func _localize_msg(m: String) -> String:
	match m:
		"Deck is full": return "牌組已滿（12 張）"
		"Over limit": return "超過同名上限（單位 ≤2、魔法 ≤3）"
		"Phase not ready": return "本階段張數不足，尚不能進入下一步"
		"Not your turn": return "非當前選手的回合"
		_: return m


# ---------------- 進入對戰 ----------------

func _start_battle() -> void:
	var tree := get_tree()
	if tree == null:
		return   # headless：不做場景切換（測試只驗到 done）
	var battle: Node = BattleScene.instantiate()
	battle.boot(_state.player1_deck.duplicate(), _state.player2_deck.duplicate(), _seed if _seed != 0 else randi())
	tree.root.add_child(battle)
	tree.current_scene = battle
	queue_free()


# ---------------- UI 建構 ----------------

func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.size = Vector2(1024, 768)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_hud = CanvasLayer.new()
	add_child(_hud)

	var title := _mk_label(Vector2(24, 14), 22, 900)
	title.text = "午後激盪 — 選秀 BP（本機）"
	_hud.add_child(title)

	_phase_label = _mk_label(Vector2(24, 48), 17, 900)
	_hud.add_child(_phase_label)

	_msg_label = _mk_label(Vector2(24, 76), 15, 640)
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	_hud.add_child(_msg_label)

	# 色頁分頁鈕。
	var tx := 24.0
	for i in COLORS.size():
		var b := _mk_button(COLORS[i][1], Vector2(tx, 104), Vector2(66, 30))
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_select_color.bind(i))
		_hud.add_child(b)
		_color_tabs.append(b)
		tx += 70.0

	# 展示館（職業卡格）。
	_exhibit_box = GridContainer.new()
	_exhibit_box.columns = 4
	_exhibit_box.position = Vector2(24, 150)
	_exhibit_box.add_theme_constant_override("h_separation", 8)
	_exhibit_box.add_theme_constant_override("v_separation", 8)
	_hud.add_child(_exhibit_box)

	var magic_title := _mk_label(Vector2(24, 360), 14, 400)
	magic_title.text = "魔法卡（同名 ≤3）"
	_hud.add_child(magic_title)
	_magic_box = HBoxContainer.new()
	_magic_box.position = Vector2(24, 384)
	_magic_box.add_theme_constant_override("separation", 8)
	_hud.add_child(_magic_box)

	# 雙方牌組面板。
	var p1_title := _mk_label(Vector2(560, 104), 15, 200)
	p1_title.text = "先手 P1 牌組"
	p1_title.add_theme_color_override("font_color", Color(0.95, 0.5, 0.5))
	_hud.add_child(p1_title)
	_p1_panel = _mk_deck_panel(Vector2(560, 130))
	_hud.add_child(_p1_panel)

	var p2_title := _mk_label(Vector2(792, 104), 15, 200)
	p2_title.text = "後手 P2 牌組"
	p2_title.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0))
	_hud.add_child(p2_title)
	_p2_panel = _mk_deck_panel(Vector2(792, 130))
	_hud.add_child(_p2_panel)

	# 底部控制列。
	_advance_btn = _mk_button("下一階段", Vector2(24, 470), Vector2(220, 48))
	_advance_btn.pressed.connect(_on_advance)
	_hud.add_child(_advance_btn)

	var rm := _mk_button("移除最後一張 (C)", Vector2(256, 470), Vector2(190, 48))
	rm.pressed.connect(_on_remove_last)
	_hud.add_child(rm)

	_timer_btn = _mk_button("計時", Vector2(24, 528), Vector2(150, 34))
	_timer_btn.pressed.connect(_on_toggle_timer)
	_hud.add_child(_timer_btn)

	_file_btn = _mk_button("存檔", Vector2(184, 528), Vector2(180, 34))
	_file_btn.pressed.connect(_on_toggle_file)
	_hud.add_child(_file_btn)

	var hint := _mk_label(Vector2(24, 580), 13, 900)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	hint.text = "點展示館卡片＝加入當前選手牌組；點自己牌組的卡＝移除。單位同名 ≤2、魔法 ≤3、共 12 張。"
	_hud.add_child(hint)


func _refresh() -> void:
	if not _ui_built:
		return
	var editor: String = _state.current_editor()
	var editor_txt: String = "先手 P1" if editor == "player1" else ("後手 P2" if editor == "player2" else "—")
	_phase_label.text = "%s　｜　當前選手：%s　｜　P1 %d/12　P2 %d/12" % [
		PHASE_TEXT.get(_state.phase, _state.phase), editor_txt,
		_state.player1_deck.size(), _state.player2_deck.size()]
	_msg_label.text = _message

	# 色頁高亮。
	for i in _color_tabs.size():
		_color_tabs[i].modulate = Color(1, 1, 0.6) if i == _selected_color else Color(1, 1, 1)

	# 進度鈕文字：p1_last6 完成後為「開始對戰」。
	_advance_btn.text = "開始對戰" if _state.phase == "p1_last6" else "下一階段"
	_advance_btn.disabled = not _state.can_advance()
	_timer_btn.text = "計時：正計時" if _state.timer_mode == "timer" else "計時：倒數"
	_file_btn.text = "存檔：保留" if not _state.file_auto_delete else "存檔：自動刪除"

	_rebuild_exhibit()
	_rebuild_deck_panel(_p1_panel, "player1")
	_rebuild_deck_panel(_p2_panel, "player2")


func _rebuild_exhibit() -> void:
	for c in _exhibit_box.get_children():
		c.queue_free()
	for c in _magic_box.get_children():
		c.queue_free()
	var code: String = COLORS[_selected_color][0]
	var jobs: Array = PURPLE_JOBS if code == "P" else JOBS
	for job: String in jobs:
		var card_id: String = job + code
		_exhibit_box.add_child(_mk_card_button(card_id, job, code))
	for magic: String in EXHIBIT_MAGIC:
		_magic_box.add_child(_mk_card_button(magic, magic, ""))


func _rebuild_deck_panel(panel: VBoxContainer, owner: String) -> void:
	for c in panel.get_children():
		c.queue_free()
	var deck: Array = _state.get_deck(owner)
	for card_id: String in deck:
		var base: String = card_id
		var info: Dictionary = _db.text(base)
		var b := Button.new()
		b.text = String(info.get("name", base))
		b.custom_minimum_size = Vector2(160, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_deck_card_pressed.bind(owner, card_id))
		panel.add_child(b)


func _mk_card_button(card_id: String, glyph: String, color_code: String) -> Button:
	var info: Dictionary = _db.text(card_id)
	var b := Button.new()
	b.text = "%s\n%s" % [String(info.get("name", card_id)), glyph]
	b.custom_minimum_size = Vector2(122, 58)
	b.add_theme_font_size_override("font_size", 12)
	if color_code != "":
		# 以派別色淡染按鈕，便於辨識色頁。
		var fc: Color = _db.color_rgb(color_code)
		b.modulate = fc.lerp(Color.WHITE, 0.45)
	b.pressed.connect(_on_exhibit_pressed.bind(card_id))
	return b


# ---------------- 小工具 ----------------

func _mk_deck_panel(pos: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = pos
	v.add_theme_constant_override("separation", 3)
	return v


func _mk_label(pos: Vector2, font_size: int, width: float) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _mk_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_size_override("font_size", 15)
	return b
