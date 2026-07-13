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

# 視圖層 / 節點（皆綁定自 battle.tscn 內宣告的 `%` 唯一名稱節點）
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
			_board_layer.add_child(sv)
			sv.configure("SHADOW", _owner_int(sh.owner), _db, true, job)
			_shadow_views.append(sv)


func _make_piece_view(card_id: String, owner_int: int, cell: Vector2i) -> Node2D:
	var v: Node2D = PieceViewScene.instantiate()
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
