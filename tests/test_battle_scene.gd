# P2-3 對戰場景 headless 冒煙測試（見 docs/rebuild/06 P2-3）。
# 「觀感/手感」由人工於編輯器跑 battle.tscn 驗收（見 docs/rebuild/驗收_對戰.md）；
# 這裡守可自動化的邏輯：所有行動經場景 dispatch 路徑正確驅動 core、視圖與 core 狀態同步、
# 攻擊範圍預覽（含鏡像）計算、勝負畫面與重開。以「動畫關（瞬時）」模式讓 _post_dispatch 同步收斂。
extends RefCounted

const BattleScript := preload("res://scenes/battle/battle.gd")


func run(t: Object) -> void:
	var dbs: Array = []
	_test_attack_flow(t, dbs)
	_test_all_actions(t, dbs)
	_test_win_and_restart(t, dbs)
	_test_range_preview_with_shadow(t, dbs)
	for db in dbs:
		db.free()


func _new_db() -> Object:
	return load("res://script/data/balance_db.gd").new()


func _mk_battle(dbs: Array, p1: Array, p2: Array, seed_v: int) -> Node:
	var db: Object = _new_db()
	dbs.append(db)
	var b: Node = BattleScript.new()
	b.boot(p1, p2, seed_v, db)
	b.set_animation_enabled(false)   # 瞬時模式：行動同步收斂（headless 無 _process）
	return b


func _deck(card_id: String, n: int) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


# ---------------- 1. 出牌 + 攻擊（經場景輸入路徑）----------------
func _test_attack_flow(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 100)

	# HUD 已組好、初盤無棋子。
	t.ok(b._ui_built, "attack：UI 已建構")
	t.ok(not b._score_label.text.is_empty(), "attack：分數標籤非空")
	t.eq(b._views.size(), 0, "attack：初盤無棋子視圖")

	# p1 出一子於 (1,1)：選手牌單位 → 點空格放置。
	b._on_hand_pressed(0)
	t.eq(b._placing_index, 0, "attack：選單位卡進入放置狀態")
	b._board_click(Vector2i(1, 1))
	t.eq(b._core.player1.on_board.size(), 1, "attack：p1 出牌後場上 1 子")
	t.eq(b._placing_index, -1, "attack：放置後清除放置狀態")
	t.ok(b._views.has(Vector2i(1, 1)), "attack：(1,1) 有棋子視圖")
	t.eq(b._views.size(), 1, "attack：視圖與棋子同步（1）")

	b._do("end_turn", -1, -1)
	t.eq(b._core.current_player(), "player2", "attack：換 p2")

	# p2 於同欄 (1,3) 放一子供 p1 大十字攻擊。
	b._on_hand_pressed(0)
	b._board_click(Vector2i(1, 3))
	t.eq(b._core.player2.on_board.size(), 1, "attack：p2 出牌後場上 1 子")
	b._do("end_turn", -1, -1)
	t.eq(b._core.turn_number, 2, "attack：turn=2")
	t.eq(b._core.number_of_attacks["player1"], 2, "attack：p1 攻擊次數累積 2")

	var target: PieceState = b._core.player2.on_board[0]
	var hp0: int = target.health
	# 攻擊模式（預設）點我方 (1,1) → 大十字命中同欄 (1,3)。
	t.eq(b._mode, "attack", "attack：預設攻擊模式")
	b._board_click(Vector2i(1, 1))
	t.eq(target.health, hp0 - 4, "attack：ADCW 大十字造成 4 傷")
	t.eq(b._core.number_of_attacks["player1"], 1, "attack：消耗 1 次攻擊")

	b.free()


# ---------------- 2. 全行動類型（出牌/升級切換/治療/移動兩段式/方塊/結束）----------------
func _test_all_actions(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 7)
	# 注入已知手牌與金幣（測試設定；行動仍全走場景 dispatch）。
	b._core.get_player("player1").hand.assign(["ADCW", "ADCC", "HEAL", "MOVE", "CUBES"])
	b._core.players_coin["player1"] = 50
	b._refresh_hud()

	# (1) 放置一般單位 ADCW → (0,0)。
	b._on_hand_pressed(0)
	b._board_click(Vector2i(0, 0))
	t.eq(b._core.player1.on_board.size(), 1, "all：ADCW 放置成功")

	# (2) 選 Cyan 卡 → 升級切換（名字加「 (+)」）。
	b._on_hand_pressed(0)   # 現在 hand[0]=ADCC
	t.eq(b._placing_index, 0, "all：選 Cyan 卡放置")
	b._on_toggle_upgrade()
	t.eq(b._core.player1.hand[0], "ADCC (+)", "all：升級切換加後綴")

	# (3) 放置升級版 ADCC → (0,1)（金幣足夠，price_check 通過）。
	b._board_click(Vector2i(0, 1))
	t.eq(b._core.player1.on_board.size(), 2, "all：升級 ADCC 放置成功")
	var upg_ok: bool = false
	for p: PieceState in b._core.player1.on_board:
		if p.card_id == "ADCC" and p.upgrade:
			upg_ok = true
	t.ok(upg_ok, "all：場上有升級版 ADCC")
	t.ok(b._core.players_coin["player1"] < 50, "all：升級版扣了金幣")

	# 讓 (0,0) 的 ADCW 解暈以便移動（入場暈眩不可移動）。
	var mover: PieceState = null
	for p: PieceState in b._core.player1.on_board:
		if p.pos() == Vector2i(0, 0):
			mover = p
	mover.set_numb(false)

	# (4) HEAL 魔法（即時打出獲得治療次數）→ 治療模式點自方棋子花掉。
	b._on_hand_pressed(0)   # HEAL
	t.eq(b._core.number_of_heals["player1"], 1, "all：HEAL 給 1 次治療")
	b._set_mode("heal")
	b._board_click(Vector2i(0, 0))
	t.eq(b._core.number_of_heals["player1"], 0, "all：治療花掉 1 次")

	# (5) MOVE 魔法 → 兩段式移動 (0,0)→(1,0)。
	b._on_hand_pressed(0)   # MOVE
	t.eq(b._core.number_of_movings["player1"], 1, "all：MOVE 給 1 次移動")
	b._set_mode("move")
	b._board_click(Vector2i(0, 0))   # 階段1：啟用移動（扣點）
	t.ok(mover.is_moving(), "all：移動階段1 棋子進入移動中")
	t.eq(b._core.number_of_movings["player1"], 0, "all：移動點於階段1 扣除")
	b._board_click(Vector2i(0, 0))   # 階段2a：選取
	b._board_click(Vector2i(1, 0))   # 階段2b：移動到相鄰空格
	t.eq(mover.pos(), Vector2i(1, 0), "all：兩段式移動成功到 (1,0)")

	# (6) CUBES 魔法 → 方塊模式放一顆中立方塊。
	b._on_hand_pressed(0)   # CUBES
	t.eq(b._core.number_of_cubes["player1"], 2, "all：CUBES 給 2 次方塊")
	b._set_mode("cube")
	b._board_click(Vector2i(2, 2))
	t.eq(b._core.neutral_pieces.size(), 1, "all：放置一顆中立方塊")
	t.eq(b._core.number_of_cubes["player1"], 1, "all：方塊花掉 1 次")

	# 視圖與 core 全部棋子同步（2 我方 + 1 中立）。
	t.eq(b._views.size(), 3, "all：視圖與全部棋子同步（3）")

	# (7) 結束回合換手。
	b._do("end_turn", -1, -1)
	t.eq(b._core.current_player(), "player2", "all：結束回合換 p2")

	b.free()


# ---------------- 3. 勝負畫面 + 重開 ----------------
func _test_win_and_restart(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 3)
	# 注入一個非暈眩的 p1 棋子（每回合結算 −1）；反覆結束回合直到 p1 達門檻獲勝。
	var scorer: PieceState = PieceState.make("ADCW", "player1", 0, 0, b._core.balance)
	scorer.set_numb(false)
	b._core.player1.on_board.append(scorer)
	b._core.board.set_occupied(Vector2i(0, 0), true)

	var guard: int = 0
	while not b._core.is_over() and guard < 60:
		guard += 1
		b._do("end_turn", -1, -1)

	t.ok(b._core.is_over(), "win：達門檻結束對局")
	t.eq(b._core.winner(), 0, "win：p1（score<0）獲勝")
	t.ok(b._win_panel.visible, "win：勝負畫面顯示")
	t.ok(not b._win_label.text.is_empty(), "win：勝負文字非空")

	# 重開：勝負畫面隱藏、盤面清空、可再戰。
	b._on_win_restart()
	t.ok(not b._core.is_over(), "win：重開後對局重置")
	t.ok(not b._win_panel.visible, "win：重開後勝負畫面隱藏")
	t.eq(b._views.size(), 0, "win：重開後盤面清空")
	t.eq(b._core.current_player(), "player1", "win：重開後回到先手")

	b.free()


# ---------------- 4. 攻擊範圍預覽（含 Fuchsia 鏡像）----------------
func _test_range_preview_with_shadow(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 11)

	# ADCW 大十字：以 (1,1) 為中心，命中同行同列（不含自身）。
	var adc: PieceState = PieceState.make("ADCW", "player1", 1, 1, b._core.balance)
	var cells: Array = b._footprint_cells(adc)
	t.ok(cells.has(Vector2i(1, 0)), "range：大十字含同欄 (1,0)")
	t.ok(cells.has(Vector2i(3, 1)), "range：大十字含同列 (3,1)")
	t.ok(not cells.has(Vector2i(1, 1)), "range：不含自身格")
	t.ok(not cells.has(Vector2i(2, 2)), "range：不含斜角 (2,2)")

	# 掛一個鏡像（linker=ADCW → 鏡像用 large_cross）於 (3,3)：範圍應加入以 (3,3) 為中心的行列。
	var shadow: PieceState = PieceState.make_shadow(adc, "player1", 3, 3, false)
	adc.shadows.append(shadow)
	var cells2: Array = b._footprint_cells(adc)
	t.ok(cells2.has(Vector2i(3, 0)), "range：含鏡像大十字同欄 (3,0)")
	t.ok(cells2.has(Vector2i(0, 3)), "range：含鏡像大十字同列 (0,3)")

	# 小十字（TANK）：僅上下左右。
	var tank: PieceState = PieceState.make("TANKW", "player1", 1, 1, b._core.balance)
	var tcells: Array = b._footprint_cells(tank)
	t.ok(tcells.has(Vector2i(1, 0)) and tcells.has(Vector2i(0, 1)), "range：小十字含正交鄰格")
	t.ok(not tcells.has(Vector2i(3, 1)), "range：小十字不含遠格")

	b.free()
