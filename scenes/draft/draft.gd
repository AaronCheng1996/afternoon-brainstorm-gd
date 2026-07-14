# P2-4 選秀 BP 場景（本機模式）。見 docs/rebuild/06 P2-4/P7-5、01 §9、08 §3。
# 一切行動經 DraftDispatcher.dispatch(DraftAction, DraftState)（純邏輯核心）。
# 三階段 p1_first6 → p2_pick12 → p1_last6 → done；完成後帶雙方牌組進 battle.tscn。
#
# P7-5：UI 骨架（背景/標題/色頁鈕/展示格/牌組面板/控制列）宣告於 draft.tscn（編輯器可視可編輯，
# 美術可接手）；本腳本只用場景唯一名稱（`%NodeName`）綁定既有節點、連接信號，不再程序建構。
# 動態集合生成到宣告好的容器：展示卡 → ExhibitGrid、魔法卡 → MagicBox、牌組列 → P1/P2DeckPanel。
extends Node2D

const BattleScene := preload("res://scenes/battle/battle.tscn")

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

var _state: DraftState
var _dispatcher: DraftDispatcher
var _db: Object = null
var _seed: int = 0
var _selected_color: int = 0
var _message: String = ""
var _ready_to_start: bool = false

# P11-1 每階段倒數計時：逾時自動補牌並進下一階段。開關/秒數讀 user://settings.json。
var _phase_timer := CountdownTimer.new()
var _pool: Array = []   # 自動補牌候選（全色 units＋魔法）

# UI（皆綁定自 draft.tscn 內宣告的 `%` 唯一名稱節點）
var _hud: CanvasLayer
var _ui_built: bool = false          # 節點綁定完成旗標（沿用舊名，供測試斷言）
var _phase_label: Label
var _msg_label: Label
var _exhibit_box: GridContainer
var _magic_box: HBoxContainer
var _p1_panel: VBoxContainer
var _p2_panel: VBoxContainer
var _advance_btn: Button
var _timer_btn: Button
var _file_btn: Button
var _card_detail: KeywordLabel   # P8-3：懸停卡片時顯示描述（機制詞高亮＋可再懸停解釋）
var _color_tabs: Array = []


func _ready() -> void:
	if _state == null:
		boot(0)


# 對外啟動（供主選單之後呼叫，或 headless 測試直接呼叫）。
func boot(seed_value: int, db: Object = null) -> void:
	_db = db if db != null else Balance
	_seed = seed_value
	_state = DraftState.new()
	_dispatcher = DraftDispatcher.new()
	_selected_color = 0
	_message = ""
	_ready_to_start = false
	_pool = _build_pool()
	var s := SettingsStore.load_settings()
	_phase_timer.configure(bool(s.get("draft_timer_on", false)), float(s.get("draft_seconds", 45)))
	_bind_nodes()
	_restart_phase_timer()
	set_process(_phase_timer.enabled)
	_refresh()


# 自動補牌候選＝各色 units（魅紫僅 4 職）＋魔法（對齊展示館可選項）。
func _build_pool() -> Array:
	var pool: Array = []
	for c: Array in COLORS:
		var code: String = c[0]
		var jobs: Array = PURPLE_JOBS if code == "P" else JOBS
		for job: String in jobs:
			pool.append(job + code)
	pool.append_array(EXHIBIT_MAGIC)
	return pool


# 依當前階段（有可編輯玩家）重啟倒數；計時關閉或已 done 則停。
func _restart_phase_timer() -> void:
	if _phase_timer.enabled and _state.current_editor() != "":
		_phase_timer.start()
	else:
		_phase_timer.stop()


# 每幀推進倒數；到點＝逾時自動補牌並進下一階段。只在計時開啟時運作（set_process 控管）。
func _process(delta: float) -> void:
	if not _phase_timer.running:
		return
	if _phase_timer.advance(delta):
		_on_phase_timeout()
	else:
		_update_phase_label()   # 只更新標籤剩餘秒數（不重建展示，省成本）


# 逾時：補牌到可進階最低張數並前進；若補到 done 則開戰，否則重啟下一階段倒數。
func _on_phase_timeout() -> void:
	var r: DraftResult = _dispatcher.auto_fill_and_advance(_state, _pool)
	if r.ready_to_start or _state.phase == "done":
		_ready_to_start = true
		_start_battle()
		return
	_restart_phase_timer()
	_message = "（逾時：自動補牌並進入下一階段）"
	_refresh()


# ---------------- 行動（唯一入口）----------------

func _dispatch(action_type: String, card_name: String = "") -> DraftResult:
	# 回合限定行動的 player 一律為當前可編輯玩家；切換類不受限（沿用同一 player 欄位）。
	var editor: String = _state.current_editor()
	var action := DraftAction.new(editor, action_type, card_name)
	var r: DraftResult = _dispatcher.dispatch(action, _state)
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
	if r.success:
		_restart_phase_timer()   # 進入下一階段 → 重啟該階段倒數
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


# ---------------- 節點綁定 ----------------

func _bind_nodes() -> void:
	if _ui_built:
		return
	_ui_built = true

	_hud = %HUD
	_phase_label = %PhaseLabel
	_msg_label = %MsgLabel
	_exhibit_box = %ExhibitGrid
	_magic_box = %MagicBox
	_p1_panel = %P1DeckPanel
	_p2_panel = %P2DeckPanel
	_card_detail = %CardDetail

	# 色頁分頁鈕（10 個預置於 ColorTabs，順序對齊 COLORS）。
	_color_tabs = %ColorTabs.get_children()
	for i in _color_tabs.size():
		(_color_tabs[i] as Button).pressed.connect(_select_color.bind(i))

	# 底部控制列。
	_advance_btn = %AdvanceBtn
	_advance_btn.pressed.connect(_on_advance)
	(%RemoveLastBtn as Button).pressed.connect(_on_remove_last)
	_timer_btn = %TimerBtn
	_timer_btn.pressed.connect(_on_toggle_timer)
	_file_btn = %FileBtn
	_file_btn.pressed.connect(_on_toggle_file)


func _refresh() -> void:
	if not _ui_built:
		return
	_update_phase_label()
	_msg_label.text = _message

	_refresh_body()


# 更新階段標籤（含倒數剩餘秒）。供 _refresh 與 _process 每幀輕量更新共用。
func _update_phase_label() -> void:
	if _phase_label == null:
		return
	var editor: String = _state.current_editor()
	var editor_txt: String = "先手 P1" if editor == "player1" else ("後手 P2" if editor == "player2" else "—")
	var base: String = "%s　｜　當前選手：%s　｜　P1 %d/12　P2 %d/12" % [
		PHASE_TEXT.get(_state.phase, _state.phase), editor_txt,
		_state.player1_deck.size(), _state.player2_deck.size()]
	if _phase_timer.running:
		base += "　｜　⏳ %d 秒" % _phase_timer.remaining_seconds()
	_phase_label.text = base


func _refresh_body() -> void:

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
		b.mouse_entered.connect(_show_card_detail.bind(card_id))
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
	b.mouse_entered.connect(_show_card_detail.bind(card_id))
	return b


# P8-3：懸停卡片 → 在下方說明區顯示名稱＋完整描述（機制詞自動高亮、可再懸停看解釋）。
func _show_card_detail(card_id: String) -> void:
	if _card_detail == null:
		return
	var info: Dictionary = _db.text(card_id)
	var card_name: String = String(info.get("name", card_id))
	var desc: String = String(info.get("description", ""))
	if desc.strip_edges().is_empty():
		desc = String(info.get("hint", ""))
	_card_detail.set_source("[b]%s[/b]（%s）\n%s" % [card_name, card_id, desc])
