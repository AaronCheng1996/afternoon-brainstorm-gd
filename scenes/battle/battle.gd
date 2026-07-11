# P2-3 對戰場景（本機雙人 hot-seat）。見 docs/rebuild/06 P2-3、04 §7。
# 一切行動經 GameCore.dispatch；core 吐事件 → CombatSchedulerV2 播動畫 → 動畫結束後
# 由 core 最終狀態「重建棋盤」重新同步（sim/view 分離，見 D1）。
#
# UI 全程以程式建立（headless 可實例化並直接呼叫行動方法測試；不依賴輸入事件）。
# 換美術：棋子視覺在 PieceViewV2 的 SpriteSlot；本場景不含任何美術資源。
extends Node2D

const PieceViewScript := preload("res://scenes/battle/piece_view.gd")
const SchedulerScript := preload("res://script/view/combat_scheduler.gd")

const BOARD := 4
const STRIDE := 118.0
const INSET := (STRIDE - PieceViewScript.CELL_SIZE) * 0.5   # 96 形狀置中於 118 格
const ORIGIN := Vector2(40.0, 150.0)

const COL_BG := Color(0.10, 0.11, 0.13)
const COL_GRID := Color(0.30, 0.32, 0.36)
const COL_HOVER := Color(1.0, 1.0, 1.0, 0.10)
const COL_RANGE := Color(0.95, 0.35, 0.30, 0.28)
const COL_SELECTED := Color(1.0, 0.9, 0.3, 0.30)
const COL_MOVING := Color(0.4, 0.9, 1.0, 0.22)
const P1_COL := Color(0.95, 0.4, 0.4)
const P2_COL := Color(0.45, 0.6, 1.0)

const MAGIC_CARDS := ["HEAL", "MOVE", "MOVEO", "CUBES"]


# 以 draw 回呼繪製的 Node2D（queue_redraw() → _draw() → 呼叫 cb）。用於高亮/預覽層。
class DrawLayer extends Node2D:
	var cb: Callable = Callable()
	func _draw() -> void:
		if cb.is_valid():
			cb.call()

# --- 設定 / 狀態 ---
var _p1_deck: Array = []
var _p2_deck: Array = []
var _seed: int = 1
var _db: Object = null

var _core: GameCore = null
var _scheduler: Node = null

var _mode: String = "attack"        # attack / move / heal / cube
var _placing_index: int = -1        # 手牌待放置的單位卡索引（-1=無）
var _busy: bool = false             # 動畫播放中：鎖輸入
var _instant: bool = false          # 動畫開關（true=瞬時）
var _hints_on: bool = true
var _hover_cell: Vector2i = Vector2i(-1, -1)

# 視圖層 / 節點
var _bg_layer: Node2D
var _grid_layer: Node2D
var _persist_layer: Node2D          # 選取/移動中高亮（隨棋盤重建）
var _board_layer: Node2D            # 棋子視圖
var _preview_layer: Node2D          # 滑鼠懸停/攻擊範圍預覽
var _fx_layer: Node2D               # 投射物 / 飄字
var _views: Dictionary = {}         # Vector2i -> PieceViewV2（真實棋子+neutral）
var _shadow_views: Array = []       # Fuchsia 鏡像視圖（僅顯示）

# HUD
var _hud: CanvasLayer
var _ui_built: bool = false
var _score_label: Label
var _turn_label: Label
var _res_label: Label
var _counts_label: Label
var _hint_label: Label
var _mode_buttons: Dictionary = {}  # mode -> Button
var _hand_box: HBoxContainer
var _toggle_hint_btn: Button
var _toggle_anim_btn: Button
var _upgrade_btn: Button
var _win_panel: Panel
var _win_label: Label
var _show_luck: bool = false
var _show_token: bool = false
var _show_totem: bool = false
var _show_coin: bool = false


func _ready() -> void:
	if _core == null:
		# 編輯器 F6 直接執行：用預設牌組開一局（含 B/G/C/DKG 以顯示四種資源列）。
		boot(_default_deck_a(), _default_deck_b(), 1)


# 對外啟動：設定牌組並開一局（供主選單/BP 之後呼叫，或 headless 測試直接呼叫）。
func boot(p1_deck: Array, p2_deck: Array, seed_value: int, db: Object = null) -> void:
	_p1_deck = p1_deck
	_p2_deck = p2_deck
	_seed = seed_value
	_db = db if db != null else Balance
	_build_ui()
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
	_hide_win()
	_resync()


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


# 為 SPAWN 事件先建立視圖（動畫連續性：deploy 引發的傷害可解析到新棋子/既有棋子）。
func _prespawn(events: Array) -> void:
	for e: GameEventV2 in events:
		if e.kind == GameEventV2.Kind.SPAWN:
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
			var sv: Node2D = PieceViewScript.new()
			sv.position = _cell_topleft(sh.pos())
			_board_layer.add_child(sv)
			sv.configure("SHADOW", _owner_int(sh.owner), _db, true, job)
			_shadow_views.append(sv)


func _make_piece_view(card_id: String, owner_int: int, cell: Vector2i) -> Node2D:
	var v: Node2D = PieceViewScript.new()
	v.position = _cell_topleft(cell)
	_board_layer.add_child(v)
	v.configure(card_id, owner_int, _db)
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
	end_scene.configure(_core.winner(), _core.score, _core.config.win_threshold,
		_core.stats.score_history.duplicate(), _build_stat_bars())
	tree.root.add_child(end_scene)
	tree.current_scene = end_scene
	queue_free()


# 主要統計前幾名（KILLED/DAMAGE_DEALT/SCORED）：{name: [[key, val], ...]}（降冪，取前 5）。
func _build_stat_bars() -> Dictionary:
	var out: Dictionary = {}
	var types := {
		"KILLED": Statistics.StatType.KILLED,
		"DAMAGE_DEALT": Statistics.StatType.DAMAGE_DEALT,
		"SCORED": Statistics.StatType.SCORED,
	}
	for name: String in types:
		var all: Dictionary = _core.stats.get_all(types[name])
		var rows: Array = []
		for key: String in all:
			rows.append([key, int(all[key])])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		out[name] = rows.slice(0, 5)
	return out


# ---------------- 座標換算 ----------------

func _cell_topleft(cell: Vector2i) -> Vector2:
	return ORIGIN + Vector2(cell) * STRIDE + Vector2(INSET, INSET)


func _cell_center(cell: Vector2i) -> Vector2:
	return ORIGIN + Vector2(cell) * STRIDE + Vector2(STRIDE, STRIDE) * 0.5


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(cell) * STRIDE, Vector2(STRIDE, STRIDE))


func _cell_from_global(p: Vector2) -> Vector2i:
	var local: Vector2 = p - ORIGIN
	if local.x < 0.0 or local.y < 0.0:
		return Vector2i(-1, -1)
	var cx: int = int(local.x / STRIDE)
	var cy: int = int(local.y / STRIDE)
	if cx >= 0 and cx < BOARD and cy >= 0 and cy < BOARD:
		return Vector2i(cx, cy)
	return Vector2i(-1, -1)


func _view_at(cell: Vector2i) -> Object:
	return _views.get(cell, null)


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
	# 懸停格外框。
	if _in_board(_hover_cell):
		_preview_layer.draw_rect(_cell_rect(_hover_cell), COL_HOVER, true)
		_preview_layer.draw_rect(_cell_rect(_hover_cell), Color(1, 1, 1, 0.5), false, 2.0)
	# 攻擊模式：懸停在我方棋子上 → 顯示其攻擊範圍（含 Fuchsia 鏡像）。
	if _mode == "attack" and _in_board(_hover_cell):
		var piece: PieceState = _my_piece_at(_hover_cell)
		if piece != null:
			for cell: Vector2i in _footprint_cells(piece):
				_preview_layer.draw_rect(_cell_rect(cell), COL_RANGE, true)


func _persist_draw() -> void:
	# 選取中（selected）與移動中（moving）棋子的持續高亮。
	if _core == null:
		return
	for piece: PieceState in _core.get_both_player_pieces():
		if piece.has_status("selected"):
			_persist_layer.draw_rect(_cell_rect(piece.pos()), COL_SELECTED, true)
		elif piece.is_moving():
			_persist_layer.draw_rect(_cell_rect(piece.pos()), COL_MOVING, true)


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
		_hint_label.text = ""
		return
	var txt: String = ""
	if _in_board(_hover_cell):
		var v: Object = _view_at(_hover_cell)
		if v != null:
			var cid: String = v.card_id
			var info: Dictionary = _db.text(cid)
			txt = "%s：%s" % [String(info.get("name", cid)), String(info.get("hint", ""))]
	_hint_label.text = txt


# ---------------- HUD 建構與刷新 ----------------

func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	_bg_layer = Node2D.new()
	add_child(_bg_layer)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.size = Vector2(1024, 768)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(bg)

	_grid_layer = Node2D.new()
	add_child(_grid_layer)
	_draw_grid()

	var persist := DrawLayer.new()
	persist.cb = _persist_draw
	_persist_layer = persist
	add_child(_persist_layer)

	var preview := DrawLayer.new()
	preview.cb = _preview_draw
	_preview_layer = preview
	add_child(_preview_layer)

	_board_layer = Node2D.new()
	add_child(_board_layer)

	_fx_layer = Node2D.new()
	add_child(_fx_layer)

	_scheduler = SchedulerScript.new()
	add_child(_scheduler)
	_scheduler.setup(Callable(self, "_view_at"), _fx_layer, Callable(self, "_cell_center"))
	_scheduler.instant = _instant

	_build_hud()


func _draw_grid() -> void:
	for i in range(BOARD + 1):
		var h := Line2D.new()
		h.add_point(ORIGIN + Vector2(0, i * STRIDE))
		h.add_point(ORIGIN + Vector2(BOARD * STRIDE, i * STRIDE))
		h.width = 1.5
		h.default_color = COL_GRID
		_grid_layer.add_child(h)
		var v := Line2D.new()
		v.add_point(ORIGIN + Vector2(i * STRIDE, 0))
		v.add_point(ORIGIN + Vector2(i * STRIDE, BOARD * STRIDE))
		v.width = 1.5
		v.default_color = COL_GRID
		_grid_layer.add_child(v)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	_score_label = _mk_label(Vector2(40, 14), 20, 700)
	_hud.add_child(_score_label)
	_turn_label = _mk_label(Vector2(40, 44), 16, 700)
	_hud.add_child(_turn_label)

	# 右側資訊面板。
	_res_label = _mk_label(Vector2(548, 150), 15, 260)
	_hud.add_child(_res_label)
	_counts_label = _mk_label(Vector2(548, 300), 15, 460)
	_hud.add_child(_counts_label)

	# 模式工具列。
	var modes := [["attack", "攻擊(A)"], ["move", "移動(M)"], ["heal", "治療(H)"], ["cube", "方塊(C)"]]
	var mx := 548.0
	for entry in modes:
		var b := _mk_button(entry[1], Vector2(mx, 430), Vector2(108, 34))
		b.pressed.connect(_set_mode.bind(entry[0]))
		_hud.add_child(b)
		_mode_buttons[entry[0]] = b
		mx += 116.0

	_upgrade_btn = _mk_button("升級切換(+)", Vector2(548, 472), Vector2(150, 32))
	_upgrade_btn.pressed.connect(_on_toggle_upgrade)
	_hud.add_child(_upgrade_btn)

	_toggle_hint_btn = _mk_button("提示：開", Vector2(708, 472), Vector2(110, 32))
	_toggle_hint_btn.pressed.connect(_on_toggle_hints)
	_hud.add_child(_toggle_hint_btn)

	_toggle_anim_btn = _mk_button("動畫：開", Vector2(828, 472), Vector2(110, 32))
	_toggle_anim_btn.pressed.connect(func() -> void: set_animation_enabled(_instant))
	_hud.add_child(_toggle_anim_btn)

	var end_btn := _mk_button("結束回合 (Space)", Vector2(548, 512), Vector2(230, 44))
	end_btn.pressed.connect(_do.bind("end_turn", -1, -1, -1))
	_hud.add_child(end_btn)

	_hint_label = _mk_label(Vector2(40, 632), 14, 940)
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	_hud.add_child(_hint_label)

	# 手牌列。
	_hand_box = HBoxContainer.new()
	_hand_box.position = Vector2(40, 662)
	_hand_box.add_theme_constant_override("separation", 6)
	_hud.add_child(_hand_box)

	_build_win_panel()


func _refresh_hud() -> void:
	if not _ui_built:
		return
	var thr: int = _core.config.win_threshold
	var lead: String = ""
	if _core.score < 0:
		lead = "（P1 領先 %d）" % (-_core.score)
	elif _core.score > 0:
		lead = "（P2 領先 %d）" % _core.score
	_score_label.text = "分數 %d / 勝負門檻 ±%d %s" % [_core.score, thr, lead]

	var cur: String = _core.current_player()
	var cur_txt: String = "先手 P1" if cur == "player1" else "後手 P2"
	_turn_label.text = "回合 %d｜當前：%s" % [_core.turn_number, cur_txt]
	_turn_label.add_theme_color_override("font_color", P1_COL if cur == "player1" else P2_COL)

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

func _build_win_panel() -> void:
	_win_panel = Panel.new()
	_win_panel.position = Vector2(232, 250)
	_win_panel.size = Vector2(560, 270)
	_win_panel.visible = false
	_hud.add_child(_win_panel)

	_win_label = _mk_label(Vector2(30, 40), 26, 500)
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_panel.add_child(_win_label)

	var again := _mk_button("再來一局 (R)", Vector2(30, 170), Vector2(160, 52))
	again.pressed.connect(_on_win_restart)
	_win_panel.add_child(again)

	var stats := _mk_button("終局統計", Vector2(200, 170), Vector2(160, 52))
	stats.pressed.connect(_open_end_game)
	_win_panel.add_child(stats)

	var menu := _mk_button("回主選單", Vector2(370, 170), Vector2(160, 52))
	menu.pressed.connect(_on_win_menu)
	_win_panel.add_child(menu)


func _show_win() -> void:
	var w: int = _core.winner()
	var who: String = "先手 P1" if w == 0 else ("後手 P2" if w == 1 else "平手")
	_win_label.text = "%s 獲勝！\n最終分數 %d" % [who, _core.score]
	_win_panel.visible = true


func _hide_win() -> void:
	if _win_panel != null:
		_win_panel.visible = false


# ---------------- 小工具 ----------------

func _mk_label(pos: Vector2, font_size: int, width: float) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
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


# 預設牌組（編輯器 F6 直接執行用；含 B/G/C/DKG 以顯示四種色資源列）。
func _default_deck_a() -> Array:
	return ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]


func _default_deck_b() -> Array:
	return ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]
