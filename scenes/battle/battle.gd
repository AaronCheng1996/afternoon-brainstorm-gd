# P2-3 對戰場景（本機雙人 hot-seat）。見 docs/rebuild/06 P2-3/P7-4、04 §7、08 §3。
# 一切行動經 GameCore.dispatch；core 吐事件 → CombatScheduler 播動畫 → 動畫結束後
# 由 core 最終狀態「重建棋盤」重新同步（sim/view 分離，見 D1）。
#
# P7-4：UI 骨架（背景/格線/圖層/HUD/勝負面板）宣告於 battle.tscn（編輯器可視可編輯，美術可接手）；
# 本腳本只用場景唯一名稱（`%NodeName`）綁定既有節點、連接信號，不再程序建構。
# 動態集合生成到宣告好的容器：棋子視圖 → BoardLayer、投射物/飄字 → FxLayer、手牌鈕 → HandBox。
# 換美術：棋子視覺在 PieceView 的 SpriteSlot；本場景不含任何美術資源。
extends Node2D

const PieceViewScript := preload("res://scenes/battle/piece_view.gd")   # 常數（CELL_SIZE）用
const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")   # 實例化用
const SchedulerScript := preload("res://script/view/combat_scheduler.gd")
const AnimLibScript := preload("res://script/view/piece_animation_library.gd")   # P9-3：職業攻擊演出

const BOARD := 4

const COL_BG := Color(0.10, 0.11, 0.13)
const COL_GRID := Color(0.30, 0.32, 0.36)
const COL_HOVER := Color(1.0, 1.0, 1.0, 0.10)
const COL_RANGE := Color(0.95, 0.35, 0.30, 0.28)
const COL_SELECTED := Color(1.0, 0.9, 0.3, 0.30)
const COL_MOVING := Color(0.4, 0.9, 1.0, 0.22)
const COL_AI_FOCUS := Color(1.0, 0.85, 0.2, 0.95)   # P10-5：單人對戰 AI 目標圈（黃）
const P1_COL := Color(0.95, 0.4, 0.4)
const P2_COL := Color(0.45, 0.6, 1.0)

const MAGIC_CARDS := ["HEAL", "MOVE", "MOVEO", "CUBES"]


# --- 設定 / 狀態 ---
var _p1_deck: Array = []
var _p2_deck: Array = []
var _seed: int = 1
var _db: Object = null

var _core: GameCore = null
var _scheduler: Node = null
var _world_base := Vector2.ZERO      # 鏡頭震動（P9-2）的世界根基準位

var _mode: String = "attack"        # attack / move / heal / cube
var _placing_index: int = -1        # 手牌待放置的單位卡索引（-1=無）
var _busy: bool = false             # 動畫播放中：鎖輸入
var _instant: bool = false          # 動畫開關（true=瞬時）
var _hints_on: bool = true
var _hover_cell: Vector2i = Vector2i(-1, -1)

# P10-5：單人對戰。ai_stage=""＝本機雙人（無 AI）；非空＝該關卡 CPU 控制 player2。
var _ai_stage: String = ""
var _ai: AIController = null
var _ai_focus_key: String = ""      # AI 目標圈狀態指紋（變動才重繪 persist 層）

# P11-1：對戰回合計時（可選）。逾時自動結束當前（人類）玩家回合；AI 回合不計時、動畫忙碌時暫停。
var _turn_timer := CountdownTimer.new()
var _turn_for_timer: int = -1       # 已為哪個 turn_number 啟動過計時（偵測換手重啟）

# 座標換算器（P9-1）：正交/等距雙模式，統一 cell↔pixel。預設等距。
var _view := BoardView.new()

# 視圖層 / 節點（皆綁定自 battle.tscn 內宣告的 `%` 唯一名稱節點）
var _grid_layer: Node2D              # 格線容器（10 條 Line2D，依模式重排為方格/菱形）
var _persist_layer: BattleDrawLayer  # 選取/移動中高亮（隨棋盤重建）
var _board_layer: Node2D             # 棋子視圖容器
var _preview_layer: BattleDrawLayer  # 滑鼠懸停/攻擊範圍預覽
var _fx_layer: Node2D                # 投射物 / 飄字容器
var _views: Dictionary = {}         # Vector2i -> PieceView（真實棋子+neutral）
var _shadow_views: Array = []       # Fuchsia 鏡像視圖（僅顯示）

# HUD
var _hud: CanvasLayer
var _ui_built: bool = false         # 節點綁定完成旗標（沿用舊名，供測試斷言）
var _scoreboard: Scoreboard         # P8-5：分差 meter／門檻進度／回合／趨勢的獨立記分板
var _res_label: Label
var _counts_label: Label
var _hint_label: KeywordLabel   # P8-3：RichTextLabel 子類，機制詞高亮＋懸停備註
var _mode_buttons: Dictionary = {}  # mode -> Button
var _hand_box: HBoxContainer
var _toggle_hint_btn: Button
var _toggle_anim_btn: Button
var _view_toggle_btn: Button        # P9-1：俯視／45 度視角切換
var _upgrade_btn: Button
var _win_panel: Panel
var _win_label: Label
var _show_luck: bool = false
var _show_token: bool = false
var _show_totem: bool = false
var _show_coin: bool = false

# P9-3：資源事件飄字。行動前於 _do 快照、_resync 後比對正向變化並飄字（派別色＋標籤）。
var _res_snapshot: Dictionary = {}

# 資源類別 → 顯示標籤與取色用色碼（飄字染派別色）。
const RES_KINDS := {
	"luck": {"label": "運氣", "code": "G"},
	"token": {"label": "藍球", "code": "B"},
	"totem": {"label": "圖騰", "code": "DKG"},
	"coin": {"label": "金幣", "code": "C"},
}


func _ready() -> void:
	if _core == null:
		# 編輯器 F6 直接執行：用預設牌組開一局（含 B/G/C/DKG 以顯示四種資源列）。
		boot(_default_deck_a(), _default_deck_b(), 1)


# 對外啟動：設定牌組並開一局（供主選單/BP 之後呼叫，或 headless 測試直接呼叫）。
# ai_stage 非空（見 AIController.KNOWN_STAGES）＝單人對戰：CPU 以該關卡策略控制 player2。
func boot(p1_deck: Array, p2_deck: Array, seed_value: int, db: Object = null, ai_stage: String = "") -> void:
	_p1_deck = p1_deck
	_p2_deck = p2_deck
	_seed = seed_value
	_db = db if db != null else Balance
	_ai_stage = ai_stage
	_bind_nodes()
	_apply_settings()
	_new_game()


# 套用 user://settings.json（提示/動畫開關）。戰鬥中自身的切換為 session 內；
# 跨場次持久由主選單設定頁負責。
func _apply_settings() -> void:
	var s := SettingsStore.load_settings()
	_hints_on = bool(s.get("hints_on", true))
	if _toggle_hint_btn != null:
		_toggle_hint_btn.text = "提示：開" if _hints_on else "提示：關"
	set_animation_enabled(bool(s.get("animations_on", true)))
	_turn_timer.configure(bool(s.get("turn_timer_on", false)), float(s.get("turn_seconds", 60)))


func set_animation_enabled(on: bool) -> void:
	_instant = not on
	if _scheduler != null:
		_scheduler.instant = _instant
	if _toggle_anim_btn != null:
		_toggle_anim_btn.text = "動畫：開" if on else "動畫：關"


# ---------------- 開局 ----------------

func _new_game() -> void:
	_core = GameCore.new()
	_core.setup(_p1_deck, _p2_deck, _seed, _db)
	_placing_index = -1
	_mode = "attack"
	_busy = false
	_hover_cell = Vector2i(-1, -1)
	_compute_resource_visibility()
	_setup_ai()
	_hide_win()
	_resync()


# P10-5：單人對戰時建立控制 player2 的 AIController，並開啟 _process 逐幀驅動。
# 本機雙人（_ai_stage 空）則清空 AI、關閉 process。KEY_R 重開局亦沿用同一關卡。
func _setup_ai() -> void:
	_ai = null
	_ai_focus_key = ""
	if _ai_stage != "" and AIController.is_known_stage(_ai_stage):
		_ai = AIController.new(_ai_stage, _db, "player2")
	_turn_for_timer = -1
	# 有 AI 或有回合計時任一為真就開 _process。
	set_process(_ai != null or _turn_timer.enabled)


# 依雙方牌組決定要顯示哪些色資源列（G=運氣 / B=藍球 / DKG=圖騰 / C=金幣）。
func _compute_resource_visibility() -> void:
	_show_luck = false
	_show_token = false
	_show_totem = false
	_show_coin = false
	for cid in (_p1_deck + _p2_deck):
		match _db.color_code_of(cid):
			"G": _show_luck = true
			"B": _show_token = true
			"DKG": _show_totem = true
			"C": _show_coin = true


# ---------------- 行動分派（唯一入口）----------------

func _do(action_type: String, x: int, y: int, idx: int = -1) -> void:
	if _busy or _core == null or _core.is_over():
		return
	var a := GameAction.new(action_type, _core.current_player())
	a.board_x = x
	a.board_y = y
	a.hand_index = idx
	_res_snapshot = _snapshot_resources()   # P9-3：記錄行動前資源，_resync 時比對變化飄字
	_core.dispatch(a)
	_post_dispatch()


func _post_dispatch() -> void:
	var events: Array = _core.drain_events()
	if events.is_empty():
		_resync()
		return
	_prespawn(events)
	_busy = true
	_scheduler.instant = _instant
	_scheduler.finished.connect(_on_anim_finished, CONNECT_ONE_SHOT)
	_scheduler.play_events(events)


func _on_anim_finished() -> void:
	_busy = false
	_resync()


# ---------------- 單人對戰 AI 驅動（P10-5）----------------

# 只在 AI 回合且非動畫忙碌時，把 AIController 吐出的 GameAction（0/1 個）經既有 _do 分派。
# 節奏（回合開始停頓、行動間隔）與合法性由 AIController 負責（A §1，`is_busy`＝renderer_busy）。
# 本機雙人（_ai 為 null）時 set_process(false)，本函式不運作。
func _process(delta: float) -> void:
	if _core == null:
		return
	_tick_turn_timer(delta)
	# 單人對戰 AI 驅動（見上）。
	if _ai == null or _busy or _core.is_over():
		return
	if _core.current_player() != _ai.player_name:
		return
	var actions: Array = _ai.tick(_core, Time.get_ticks_msec(), _busy)
	for a: GameAction in actions:
		_do(a.action_type, a.board_x, a.board_y, a.hand_index)
	_refresh_ai_focus()


# P11-1：對戰回合計時。只在「人類回合、非動畫忙碌、未結束」時倒數；換手重啟；逾時自動 end_turn。
# AI 回合（單人對戰的 player2）不計時。瞬時模式仍計時（以真實時間倒數）。
func _tick_turn_timer(delta: float) -> void:
	if not _turn_timer.enabled or _core.is_over():
		return
	# AI 控制的回合不計時。
	if _ai != null and _core.current_player() == _ai.player_name:
		_turn_timer.stop()
		return
	if _busy:
		return   # 動畫播放中暫停倒數（不扣時、不逾時）
	if _turn_for_timer != _core.turn_number:
		_turn_for_timer = _core.turn_number
		_turn_timer.start()
	if _turn_timer.advance(delta):
		_do("end_turn", -1, -1)
	elif _counts_label != null:
		_counts_label.text = _counts_text(_core.current_player())   # 每幀更新剩餘秒


# AI 目標圈（focus_position）狀態變動時重繪 persist 層（黃圈畫在 _persist_draw）。
func _refresh_ai_focus() -> void:
	if _ai == null:
		return
	var key: String = "%s:%d,%d" % [_ai.has_focus, _ai.focus_position.x, _ai.focus_position.y]
	if key != _ai_focus_key:
		_ai_focus_key = key
		if _persist_layer != null:
			_persist_layer.queue_redraw()


# 為 SPAWN 事件先建立視圖（動畫連續性：deploy 引發的傷害可解析到新棋子/既有棋子）。
func _prespawn(events: Array) -> void:
	for e: GameEvent in events:
		if e.kind == GameEvent.Kind.SPAWN:
			var at: Vector2i = e.data["at"]
			if _views.has(at):
				continue
			var v: Node2D = _make_piece_view(e.data["card_id"], _owner_int(e.data["owner"]), at)
			v.instant = _instant
			_views[at] = v
			v.play_cast()


# ---------------- 同步（動畫結束後以 core 最終狀態重建）----------------

func _resync() -> void:
	_drain_logic()
	_rebuild_board()
	_refresh_hud()
	_flush_resource_feedback()   # P9-3：資源正向變化飄字
	if _core.is_over():
		_show_win()


# 消化 logic_step：回收死亡棋子 + 逐步抽牌（card_to_draw 可 >1，迴圈至清空）。
func _drain_logic() -> void:
	_core.logic_step()
	var guard: int = 0
	while (_core.card_to_draw["player1"] > 0 or _core.card_to_draw["player2"] > 0) and guard < 128:
		guard += 1
		_core.logic_step()


func _rebuild_board() -> void:
	for c in _board_layer.get_children():
		c.free()
	_views.clear()
	_shadow_views.clear()
	_persist_layer.queue_redraw()

	for piece: PieceState in _core.get_all_pieces():
		var v: Node2D = _make_piece_view(piece.card_id, _owner_int(piece.owner), piece.pos())
		v.update_stats(piece.health, piece.damage, piece.armor, piece.extra_damage)
		v.set_status("numbness", piece.is_numb())
		v.set_status("moving", piece.is_moving())
		v.set_status("anger", piece.is_angry())
		_views[piece.pos()] = v
		# Fuchsia 鏡像（僅顯示，不進 _views）。
		for sh: PieceState in piece.shadows:
			var linker: PieceState = sh.get_linker()
			var job: String = linker.job if linker != null else "ADC"
			var sv: Node2D = PieceViewScene.instantiate()
			sv.position = _cell_topleft(sh.pos())
			sv.z_index = _view.depth(sh.pos())
			sv.fx_layer = _fx_layer
			_board_layer.add_child(sv)
			sv.configure("SHADOW", _owner_int(sh.owner), _db, true, job)
			_shadow_views.append(sv)


func _make_piece_view(card_id: String, owner_int: int, cell: Vector2i) -> Node2D:
	var v: Node2D = PieceViewScene.instantiate()
	v.position = _cell_topleft(cell)
	v.z_index = _view.depth(cell)   # 等距遮擋：畫面越前（x+y 越大）越後畫、疊在上層（P9-1）
	v.fx_layer = _fx_layer          # P9-2：命中/死亡粒子與殘影掛 fx 層（本視圖釋放後仍存活）
	_board_layer.add_child(v)
	v.configure(card_id, owner_int, _db)
	v.set_animation_set(AnimLibScript.for_card(card_id, _db))   # P9-3：遠程投射物／近戰撲擊＋派別色特效
	return v


# ---------------- 輸入（棋盤點擊 / 懸停 / 鍵盤）----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = _cell_from_global(event.position)
		if cell.x >= 0:
			_board_click(cell)
	elif event is InputEventMouseMotion:
		_hover_cell = _cell_from_global(event.position)
		_update_preview()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)


func _board_click(cell: Vector2i) -> void:
	if _busy or _core.is_over():
		return
	if _placing_index >= 0:
		_do("play_card", cell.x, cell.y, _placing_index)
		_placing_index = -1
		return
	match _mode:
		"attack": _do("attack", cell.x, cell.y)
		"move": _do("move_to", cell.x, cell.y)
		"heal": _do("heal", cell.x, cell.y)
		"cube": _do("spawn_cube", cell.x, cell.y)


func _handle_key(keycode: int) -> void:
	match keycode:
		KEY_A: _set_mode("attack")
		KEY_M: _set_mode("move")
		KEY_H: _set_mode("heal")
		KEY_C: _set_mode("cube")
		KEY_SPACE, KEY_ENTER: _do("end_turn", -1, -1)
		KEY_I: set_animation_enabled(_instant)   # 切換
		KEY_T: _on_toggle_hints()
		KEY_V: _toggle_board_mode()              # 正交／等距視角切換（P9-1，供對照）
		KEY_R: _new_game()


# ---------------- HUD 回呼 ----------------

func _on_hand_pressed(index: int) -> void:
	if _busy or _core.is_over():
		return
	var hand: Array = _core.get_player(_core.current_player()).hand
	if index < 0 or index >= hand.size():
		return
	var card: String = hand[index]
	var base_name: String = card.trim_suffix(" (+)")
	if MAGIC_CARDS.has(base_name):
		_placing_index = -1
		_do("play_card", -1, -1, index)   # 魔法卡：即時打出（獲得次數），無需目標格
	else:
		_placing_index = -1 if _placing_index == index else index
		_refresh_hud()


func _on_toggle_upgrade() -> void:
	if _busy or _core.is_over() or _placing_index < 0:
		return
	_do("toggle_upgrade", -1, -1, _placing_index)   # 只改手牌名（無事件）→ _resync 重繪


func _set_mode(m: String) -> void:
	_mode = m
	_placing_index = -1
	_refresh_hud()
	_update_preview()


func _on_toggle_hints() -> void:
	_hints_on = not _hints_on
	if _toggle_hint_btn != null:
		_toggle_hint_btn.text = "提示：開" if _hints_on else "提示：關"
	_update_preview()


func _on_win_restart() -> void:
	_new_game()


func _on_win_menu() -> void:
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file("res://scenes/menu/main_menu.tscn")


# 轉到終局統計畫面（帶勝者/分數/每回合分數/主要統計前幾名）。
func _open_end_game() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var end_scene: Node = load("res://scenes/end_game/end_game.tscn").instantiate()
	# P8-6：傳完整統計 export（{stat_name: {owner_cardid: int}}）；摘要長條與表格由 end_game 派生。
	end_scene.configure(_core.winner(), _core.score, _core.config.win_threshold,
		_core.stats.score_history.duplicate(), _core.stats.export_for_charts())
	tree.root.add_child(end_scene)
	tree.current_scene = end_scene
	queue_free()


# ---------------- 座標換算（統一委派 BoardView，P9-1）----------------

func _cell_topleft(cell: Vector2i) -> Vector2:
	return _view.cell_topleft(cell)


func _cell_center(cell: Vector2i) -> Vector2:
	return _view.cell_center(cell)


# P9-2 擊殺鏡頭震動：對世界根（Node2D）做衰減隨機位移，震完歸位。
# HUD 為 CanvasLayer，不受父 Node2D 變換影響，故不跟著晃。瞬時模式（動畫關）不震。
# 用全域 randf（純表現），不動 RngService，不影響對局決定性。
func _camera_shake(strength: float = 6.0) -> void:
	if _instant:
		return
	var tw := create_tween()
	var steps := 5
	for i in steps:
		var damp := strength * (1.0 - float(i) / float(steps))
		var off := Vector2(randf_range(-damp, damp), randf_range(-damp, damp))
		tw.tween_property(self, "position", _world_base + off, 0.03)
	tw.tween_property(self, "position", _world_base, 0.04)


func _cell_from_global(p: Vector2) -> Vector2i:
	return _view.cell_from_pixel(p)


# 依當前模式把 10 條格線（.tscn 預置的 H0..H4 / V0..V4）重排為方格或菱形。
func _layout_grid() -> void:
	if _grid_layer == null:
		return
	for i in range(BOARD + 1):
		var h: Line2D = _grid_layer.get_node("H%d" % i)
		h.points = PackedVector2Array([_view.corner(0, i), _view.corner(BOARD, i)])
		var v: Line2D = _grid_layer.get_node("V%d" % i)
		v.points = PackedVector2Array([_view.corner(i, 0), _view.corner(i, BOARD)])


# 切換俯視（正交）／45 度（等距）視角（HUD「視角」鈕或 V 鍵；即時重排、不影響對局）。
func _toggle_board_mode() -> void:
	_view.mode = BoardView.Mode.ORTHO if _view.mode == BoardView.Mode.ISO else BoardView.Mode.ISO
	_layout_grid()
	if _core != null:
		_rebuild_board()
	_persist_layer.queue_redraw()
	_update_preview()
	_update_view_toggle_text()


# 視角鈕文字反映當前模式（沿用 提示/動畫 鈕的「當前狀態」慣例）。
func _update_view_toggle_text() -> void:
	if _view_toggle_btn != null:
		_view_toggle_btn.text = "視角：俯視" if _view.mode == BoardView.Mode.ORTHO else "視角：45度"


# 取該格棋子視圖；已被釋放（如死亡動畫中 queue_free 但 _views 尚未重建）回 null 並剔除，
# 避免懸停/排程器取用已釋放實例（_view_at 亦為 scheduler resolver）。
func _view_at(cell: Vector2i) -> Object:
	var v: Variant = _views.get(cell, null)
	if v == null:
		return null
	if not is_instance_valid(v):
		_views.erase(cell)
		return null
	return v


func _in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < BOARD and c.y >= 0 and c.y < BOARD


func _owner_int(owner: String) -> int:
	if owner == "player1":
		return 1
	if owner == "player2":
		return 2
	return 0


# ---------------- 攻擊範圍預覽（含鏡像）----------------

func _update_preview() -> void:
	if _preview_layer == null:
		return
	_preview_layer.queue_redraw()
	_update_hint_text()


func _preview_draw() -> void:
	# 懸停格外框（依模式為方形/菱形，走 BoardView 頂點）。
	if _in_board(_hover_cell):
		_fill_cell(_preview_layer, _hover_cell, COL_HOVER)
		_outline_cell(_preview_layer, _hover_cell, Color(1, 1, 1, 0.5), 2.0)
	# 攻擊模式：懸停在我方棋子上 → 顯示其攻擊範圍（含 Fuchsia 鏡像）。
	if _mode == "attack" and _in_board(_hover_cell):
		var piece: PieceState = _my_piece_at(_hover_cell)
		if piece != null:
			for cell: Vector2i in _footprint_cells(piece):
				_fill_cell(_preview_layer, cell, COL_RANGE)


func _persist_draw() -> void:
	# 選取中（selected）與移動中（moving）棋子的持續高亮。
	if _core == null:
		return
	for piece: PieceState in _core.get_both_player_pieces():
		if piece.has_status("selected"):
			_fill_cell(_persist_layer, piece.pos(), COL_SELECTED)
		elif piece.is_moving():
			_fill_cell(_persist_layer, piece.pos(), COL_MOVING)
	# P10-5：單人對戰時，AI 決策鎖定的格畫黃色目標圈。
	if _ai != null and _ai.has_focus and _in_board(_ai.focus_position):
		_outline_cell(_persist_layer, _ai.focus_position, COL_AI_FOCUS, 3.0)


# 格填色 / 格外框（統一走 BoardView.cell_polygon，正交＝方形、等距＝菱形）。
func _fill_cell(layer: BattleDrawLayer, cell: Vector2i, color: Color) -> void:
	layer.draw_colored_polygon(_view.cell_polygon(cell), color)


func _outline_cell(layer: BattleDrawLayer, cell: Vector2i, color: Color, width: float) -> void:
	var poly: PackedVector2Array = _view.cell_polygon(cell)
	poly.append(poly[0])   # 閉合
	layer.draw_polyline(poly, color, width)


func _my_piece_at(cell: Vector2i) -> PieceState:
	for piece: PieceState in _core.get_player(_core.current_player()).on_board:
		if piece.pos() == cell:
			return piece
	return null


# 計算攻擊命中格（本體 + 各鏡像；nearest/farthest 取同距候選，不消耗 rng）。
func _footprint_cells(piece: PieceState) -> Array:
	var cells: Array = []
	_add_pattern(piece.attack_types, piece.pos(), piece.owner, cells)
	for sh: PieceState in piece.shadows:
		_add_pattern(sh.get_shadow_attack_types(), sh.pos(), sh.owner, cells)
	return cells


func _add_pattern(attack_types: String, origin: Vector2i, owner: String, cells: Array) -> void:
	for at: String in attack_types.split(" ", false):
		match at:
			"small_cross":
				_push_cells(cells, origin, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
			"small_x":
				_push_cells(cells, origin, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
			"large_cross":
				for i in BOARD:
					_push_one(cells, Vector2i(origin.x, i), origin)
					_push_one(cells, Vector2i(i, origin.y), origin)
			"nearest", "farthest":
				_push_distance_cells(cells, origin, owner, at == "farthest")
			_:
				pass   # large_x / None：無命中


func _push_cells(cells: Array, origin: Vector2i, offsets: Array) -> void:
	for off: Vector2i in offsets:
		_push_one(cells, origin + off, origin)


func _push_one(cells: Array, cell: Vector2i, origin: Vector2i) -> void:
	if cell != origin and _in_board(cell) and not cells.has(cell):
		cells.append(cell)


func _push_distance_cells(cells: Array, origin: Vector2i, owner: String, farthest: bool) -> void:
	var enemies: Array = _core.get_enemies_of(owner).filter(func(c: PieceState) -> bool: return c.health > 0)
	if enemies.is_empty():
		return
	var best: int = -1
	for c: PieceState in enemies:
		var d: int = abs(c.board_x - origin.x) + abs(c.board_y - origin.y)
		if best < 0 or (farthest and d > best) or (not farthest and d < best):
			best = d
	for c: PieceState in enemies:
		var d2: int = abs(c.board_x - origin.x) + abs(c.board_y - origin.y)
		if d2 == best and not cells.has(c.pos()):
			cells.append(c.pos())


# ---------------- 提示文字 ----------------

func _update_hint_text() -> void:
	if _hint_label == null:
		return
	if not _hints_on:
		_hint_label.set_source("")
		return
	var txt: String = ""
	if _in_board(_hover_cell):
		var v: Object = _view_at(_hover_cell)
		if v != null:
			var cid: String = v.card_id
			var info: Dictionary = _db.text(cid)
			# 提示列高度有限：多行提示以全形空白併為單行；機制詞由 KeywordLabel 高亮＋懸停解釋。
			var hint: String = String(info.get("hint", "")).replace("\n", "　")
			txt = "[b]%s[/b]：%s" % [String(info.get("name", cid)), hint]
	_hint_label.set_source(txt)


# ---------------- HUD 建構與刷新 ----------------

# 綁定 battle.tscn 內宣告的節點（場景唯一名稱 `%`）並連接信號 + 建立排程器。
# idempotent：_ready 與 boot 皆呼叫，首次生效。`%` 於 instantiate 後即可解析（不需先進場景樹），
# 故 headless 亦適用（見 P7-3 進度日誌技術註記）。
func _bind_nodes() -> void:
	if _ui_built:
		return
	_ui_built = true

	# 世界層（Node2D）。
	_grid_layer = %GridLayer
	_layout_grid()   # 依 _view 模式把格線排成方格/菱形（P9-1）
	_persist_layer = %PersistLayer
	_persist_layer.cb = _persist_draw
	_preview_layer = %PreviewLayer
	_preview_layer.cb = _preview_draw
	_board_layer = %BoardLayer
	_fx_layer = %FxLayer

	# 排程器（非視覺、不在 .tscn；建為子節點以供動畫；瞬時模式無需進場景樹）。
	_scheduler = SchedulerScript.new()
	add_child(_scheduler)
	_scheduler.setup(Callable(self, "_view_at"), _fx_layer, Callable(self, "_cell_center"))
	_scheduler.instant = _instant
	_scheduler.on_kill = Callable(self, "_camera_shake")   # P9-2：擊殺時輕微鏡頭震動
	_world_base = position                                  # 鏡頭震動的基準位（震完歸位）

	# HUD 標籤。
	_hud = %HUD
	_scoreboard = %Scoreboard
	_res_label = %ResLabel
	_counts_label = %CountsLabel
	_hint_label = %HintLabel

	# 模式工具列。
	_mode_buttons = {
		"attack": %AttackBtn,
		"move": %MoveBtn,
		"heal": %HealBtn,
		"cube": %CubeBtn,
	}
	for m: String in _mode_buttons:
		_mode_buttons[m].pressed.connect(_set_mode.bind(m))

	_upgrade_btn = %UpgradeBtn
	_upgrade_btn.pressed.connect(_on_toggle_upgrade)
	_toggle_hint_btn = %HintToggle
	_toggle_hint_btn.pressed.connect(_on_toggle_hints)
	_toggle_anim_btn = %AnimToggle
	_toggle_anim_btn.pressed.connect(func() -> void: set_animation_enabled(_instant))
	_view_toggle_btn = %ViewToggle
	_view_toggle_btn.pressed.connect(_toggle_board_mode)
	_update_view_toggle_text()
	(%EndTurnBtn as Button).pressed.connect(_do.bind("end_turn", -1, -1, -1))

	# 手牌容器（動態手牌鈕生成於此）。
	_hand_box = %HandBox

	# 勝負面板。
	_win_panel = %WinPanel
	_win_label = %WinLabel
	(%RestartBtn as Button).pressed.connect(_on_win_restart)
	(%StatsBtn as Button).pressed.connect(_open_end_game)
	(%MenuBtn as Button).pressed.connect(_on_win_menu)


func _refresh_hud() -> void:
	if not _ui_built:
		return
	var cur: String = _core.current_player()
	_scoreboard.update_board(_core.score, _core.config.win_threshold, _core.turn_number,
		cur, _core.stats.score_history)

	_res_label.text = _resource_text()
	_counts_label.text = _counts_text(cur)

	# 模式按鈕高亮。
	for m: String in _mode_buttons:
		_mode_buttons[m].modulate = Color(1, 1, 0.6) if m == _mode else Color(1, 1, 1)

	_rebuild_hand(cur)
	_update_hint_text()


func _resource_text() -> String:
	var lines: Array = ["資源　　　P1　P2"]
	if _show_luck:
		lines.append("運氣　　　%d　%d" % [_core.players_luck["player1"], _core.players_luck["player2"]])
	if _show_token:
		lines.append("藍球　　　%d　%d" % [_core.players_token["player1"], _core.players_token["player2"]])
	if _show_totem:
		lines.append("圖騰　　　%d　%d" % [_core.players_totem["player1"], _core.players_totem["player2"]])
	if _show_coin:
		lines.append("金幣　　　%d　%d" % [_core.players_coin["player1"], _core.players_coin["player2"]])
	if lines.size() == 1:
		lines.append("（本局牌組無色資源）")
	return "\n".join(lines)


# --- P9-3 資源事件飄字（token/金幣/圖騰/運氣 獲得回饋）---

# 快照當前雙方各色資源計數（行動前於 _do 呼叫）。
func _snapshot_resources() -> Dictionary:
	return {
		"luck": _core.players_luck.duplicate(),
		"token": _core.players_token.duplicate(),
		"totem": _core.players_totem.duplicate(),
		"coin": _core.players_coin.duplicate(),
	}


# 計算資源正向變化（純函式，供 headless 測）。回傳 [{kind, owner, delta}]（僅 delta>0）。
static func resource_deltas(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for kind: String in ["luck", "token", "totem", "coin"]:
		var b: Dictionary = before.get(kind, {})
		var a: Dictionary = after.get(kind, {})
		for owner: String in ["player1", "player2"]:
			var d: int = int(a.get(owner, 0)) - int(b.get(owner, 0))
			if d > 0:
				out.append({"kind": kind, "owner": owner, "delta": d})
	return out


# 依 _do 前的快照比對，對正向資源變化飄字。瞬時模式或 HUD 未建時只清快照不演出。
func _flush_resource_feedback() -> void:
	if _res_snapshot.is_empty():
		return
	var deltas := resource_deltas(_res_snapshot, _snapshot_resources())
	_res_snapshot = {}
	if _instant or not _ui_built or _hud == null or _res_label == null:
		return
	var slot := 0
	for d: Dictionary in deltas:
		_float_resource(d["kind"], d["owner"], d["delta"], slot)
		slot += 1


func _float_resource(kind: String, owner: String, delta: int, slot: int) -> void:
	var info: Dictionary = RES_KINDS.get(kind, {})
	var code: String = info.get("code", "")
	var col: Color = _db.color_rgb(code) if code != "" else Color.WHITE
	var who := "P1" if owner == "player1" else "P2"
	var l := Label.new()
	l.text = "%s +%d %s" % [who, delta, String(info.get("label", kind))]
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 50
	_hud.add_child(l)
	var base: Vector2 = _res_label.global_position + Vector2(150, 4 + slot * 22)
	l.global_position = base
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", base + Vector2(0, -26), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)


func _counts_text(cur: String) -> String:
	var p: PlayerState = _core.get_player(cur)
	var lines: Array = [
		"── 當前玩家可用 ──",
		"攻擊次數：%d" % _core.number_of_attacks[cur],
		"移動次數：%d" % _core.number_of_movings[cur],
		"治療次數：%d" % _core.number_of_heals[cur],
		"方塊次數：%d" % _core.number_of_cubes[cur],
		"牌庫：%d　棄牌：%d　手牌：%d" % [p.draw_pile.size(), p.discard_pile.size(), p.hand.size()],
	]
	if _placing_index >= 0 and _placing_index < p.hand.size():
		lines.append("放置中：%s（點空格放置）" % p.hand[_placing_index])
	if _turn_timer.running:
		lines.append("⏳ 回合剩餘：%d 秒" % _turn_timer.remaining_seconds())
	return "\n".join(lines)


func _rebuild_hand(cur: String) -> void:
	# 用 queue_free（非 free）：手牌按鈕的 pressed 信號會觸發本重建，emit 期間該按鈕被鎖定，
	# 立即 free 會報「Object is locked」。queue_free 延到本幀 idle 釋放（繪製前已清，無殘影）。
	for c in _hand_box.get_children():
		c.queue_free()
	var hand: Array = _core.get_player(cur).hand
	for i in hand.size():
		var card: String = hand[i]
		var base_name: String = card.trim_suffix(" (+)")
		var info: Dictionary = _db.text(base_name)
		var label_text: String = String(info.get("name", base_name))
		if card.ends_with(" (+)"):
			label_text += "＋"
		var b := Button.new()
		b.text = "%s\n%s" % [label_text, card]
		b.custom_minimum_size = Vector2(96, 64)
		b.add_theme_font_size_override("font_size", 12)
		if i == _placing_index:
			b.modulate = Color(1, 1, 0.5)
		b.pressed.connect(_on_hand_pressed.bind(i))
		_hand_box.add_child(b)


# ---------------- 勝負畫面 ----------------

func _show_win() -> void:
	var w: int = _core.winner()
	var who: String = "先手 P1" if w == 0 else ("後手 P2" if w == 1 else "平手")
	_win_label.text = "%s 獲勝！\n最終分數 %d" % [who, _core.score]
	_win_panel.visible = true


func _hide_win() -> void:
	if _win_panel != null:
		_win_panel.visible = false


# ---------------- 小工具 ----------------

# 預設牌組（編輯器 F6 直接執行用；含 B/G/C/DKG 以顯示四種色資源列）。
func _default_deck_a() -> Array:
	return ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]


func _default_deck_b() -> Array:
	return ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]
