# P1-2 驗收：行動分派與移動（見 docs/rebuild/06 P1-2、01 §4）。
extends RefCounted


func _make_core(p1_deck: Array, p2_deck: Array, seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var core := GameCore.new()
	core.setup(p1_deck, p2_deck, seed_v, db)
	return core


func _deck(card_id: String, n: int) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


func _act(type: String, who: String, x: int = -1, y: int = -1, idx: int = -1) -> GameAction:
	var a := GameAction.new(type, who)
	a.board_x = x
	a.board_y = y
	a.hand_index = idx
	return a


func run(t: Object) -> void:
	var deck12: Array = _deck("ADCW", 12)
	var cores: Array = []

	# --- 1. 非當前玩家行動被拒 ---
	var c1 := _make_core(deck12, deck12, 1)
	cores.append(c1)
	t.eq(c1.current_player(), "player1", "首回合 player1")
	var r_notturn := c1.dispatch(_act("end_turn", "player2"))
	t.ok(not r_notturn.success, "player2 於 player1 回合行動被拒")
	t.eq(r_notturn.message, "Not your turn", "拒絕訊息 Not your turn")

	# --- 2. 攻擊次數不足被拒 ---
	var c2 := _make_core(deck12, deck12, 2)
	cores.append(c2)
	c2.number_of_attacks["player1"] = 0
	var r_atk := c2.dispatch(_act("attack", "player1", 0, 0))
	t.ok(not r_atk.success, "攻擊次數 0 → 被拒")
	t.eq(r_atk.message, "攻擊次數不足", "拒絕訊息 攻擊次數不足")

	# --- 3. CUBES 給 2 顆 + spawn_cube 佔格 ---
	var c3 := _make_core(deck12, deck12, 3)
	cores.append(c3)
	c3.player1.hand = ["CUBES"]
	c3.dispatch(_act("play_card", "player1", 0, 0, 0))
	t.eq(c3.number_of_cubes["player1"], 2, "CUBES 出牌 → 2 顆放置機會")
	t.eq(c3.player1.hand.size(), 0, "CUBES 出牌後離手")
	# 放兩顆方塊：佔格、扣次數、生成 neutral CUBE(4HP)。
	c3.dispatch(_act("spawn_cube", "player1", 0, 0))
	t.eq(c3.number_of_cubes["player1"], 1, "放一顆後剩 1")
	t.eq(c3.neutral_pieces.size(), 1, "neutral 多一顆 CUBE")
	t.eq(c3.neutral_pieces[0].health, 4, "CUBE 4 HP")
	t.eq(c3.neutral_pieces[0].card_id, "CUBE", "card_id = CUBE")
	t.ok(c3.board.occupy[Vector2i(0, 0)], "CUBE 佔住 (0,0)")
	# 同格再放 → 失敗（格子已佔），次數不變。
	c3.dispatch(_act("spawn_cube", "player1", 0, 0))
	t.eq(c3.number_of_cubes["player1"], 1, "佔用格放置失敗，次數不扣")

	# --- 4. HEAL +6 與溢出 //2 轉盾 ---
	var c4 := _make_core(deck12, deck12, 4)
	cores.append(c4)
	var tank := PieceState.make("TANKW", "player1", 2, 2, c4.balance)  # 15 HP
	tank.set_numb(false)
	c4.player1.on_board.append(tank)
	c4.board.set_occupied(Vector2i(2, 2), true)
	# (a) 未溢出：health 5 → 11（+6）。
	tank.health = 5
	c4.player1.hand = ["HEAL"]
	c4.dispatch(_act("play_card", "player1", 0, 0, 0))
	t.eq(c4.number_of_heals["player1"], 1, "HEAL 出牌 → 治療次數 +1")
	c4.dispatch(_act("heal", "player1", 2, 2))
	t.eq(tank.health, 11, "治療 +6（5→11）")
	t.eq(tank.armor, 0, "未溢出不轉盾")
	t.eq(c4.number_of_heals["player1"], 0, "治療後次數歸零")
	# (b) 溢出轉盾：health 11 → 補滿 15、溢出 2 → armor +1。
	tank.health = 11
	c4.number_of_heals["player1"] = 1
	c4.dispatch(_act("heal", "player1", 2, 2))
	t.eq(tank.health, 15, "補滿至 max_health")
	t.eq(tank.armor, 1, "溢出 2 //2 → 護盾 +1")

	# --- 5. 移動：成功（8 鄰）+ 點數消耗 ---
	var c5 := _make_core(deck12, deck12, 5)
	cores.append(c5)
	var mover := PieceState.make("TANKW", "player1", 1, 1, c5.balance)
	mover.set_numb(false)
	c5.player1.on_board.append(mover)
	c5.board.set_occupied(Vector2i(1, 1), true)
	c5.number_of_movings["player1"] = 2
	# 兩段式：啟用（扣點）→ 選取 → 目的地。
	c5.dispatch(_act("move_to", "player1", 1, 1))
	t.ok(mover.is_moving(), "啟用移動狀態")
	t.eq(c5.number_of_movings["player1"], 1, "啟用即扣 1 點")
	c5.dispatch(_act("move_to", "player1", 1, 1))
	t.ok(mover.has_status("selected"), "選取棋子")
	c5.dispatch(_act("move_to", "player1", 1, 2))   # 相鄰
	t.eq(mover.pos(), Vector2i(1, 2), "移動到相鄰格 (1,2)")
	t.ok(not c5.board.occupy[Vector2i(1, 1)], "舊格釋放")
	t.ok(c5.board.occupy[Vector2i(1, 2)], "新格佔用")
	t.ok(not mover.is_moving(), "移動後清 moving")

	# --- 6. 移動：非相鄰失敗、點數不退（B5）---
	var c6 := _make_core(deck12, deck12, 6)
	cores.append(c6)
	var m6 := PieceState.make("TANKW", "player1", 0, 0, c6.balance)
	m6.set_numb(false)
	c6.player1.on_board.append(m6)
	c6.board.set_occupied(Vector2i(0, 0), true)
	c6.number_of_movings["player1"] = 1
	c6.dispatch(_act("move_to", "player1", 0, 0))   # 啟用（扣點 → 0）
	c6.dispatch(_act("move_to", "player1", 0, 0))   # 選取
	c6.dispatch(_act("move_to", "player1", 2, 2))   # 切比雪夫 2 → 失敗
	t.eq(m6.pos(), Vector2i(0, 0), "非相鄰移動失敗，棋子留原地")
	t.eq(c6.number_of_movings["player1"], 0, "失敗不退移動點（B5）")
	t.ok(not m6.is_moving(), "失敗後清 moving")

	# --- 7. 移動：目的地被佔失敗 ---
	var c7 := _make_core(deck12, deck12, 7)
	cores.append(c7)
	var m7 := PieceState.make("TANKW", "player1", 0, 0, c7.balance)
	m7.set_numb(false)
	var blocker := PieceState.make("TANKW", "player1", 0, 1, c7.balance)
	blocker.set_numb(false)
	c7.player1.on_board.append(m7)
	c7.player1.on_board.append(blocker)
	c7.board.set_occupied(Vector2i(0, 0), true)
	c7.board.set_occupied(Vector2i(0, 1), true)
	c7.number_of_movings["player1"] = 1
	c7.dispatch(_act("move_to", "player1", 0, 0))   # 啟用 m7
	c7.dispatch(_act("move_to", "player1", 0, 0))   # 選取 m7
	c7.dispatch(_act("move_to", "player1", 0, 1))   # 相鄰但被佔 → 失敗
	t.eq(m7.pos(), Vector2i(0, 0), "移向被佔格失敗，留原地")
	t.eq(c7.number_of_movings["player1"], 0, "失敗不退點")

	# --- 8. MOVEO：出牌給移動點且離手；未出者回合結束消失 ---
	var c8 := _make_core(deck12, deck12, 8)
	cores.append(c8)
	c8.player1.hand = ["MOVEO", "ADCW"]
	c8.dispatch(_act("play_card", "player1", 0, 0, 0))   # 出 MOVEO
	t.eq(c8.number_of_movings["player1"], 1, "MOVEO 出牌 → 移動點 +1")
	t.ok(not c8.player1.hand.has("MOVEO"), "MOVEO 出牌即離手")
	t.ok(not c8.player1.discard_pile.has("MOVEO"), "MOVEO 不進棄牌堆")
	# 手上放一張未出的 MOVEO，回合結束應被清除。
	c8.player1.hand.append("MOVEO")
	c8.dispatch(_act("end_turn", "player1"))
	t.ok(not c8.player1.hand.has("MOVEO"), "未出的 MOVEO 回合結束消失")

	# --- 9. toggle_upgrade：Cyan 卡加/去 (+) 後綴 ---
	var c9 := _make_core(deck12, deck12, 9)
	cores.append(c9)
	c9.player1.hand = ["ADCC", "ADCW"]
	c9.dispatch(_act("toggle_upgrade", "player1", -1, -1, 0))
	t.eq(c9.player1.hand[0], "ADCC (+)", "Cyan 卡加升級後綴")
	c9.dispatch(_act("toggle_upgrade", "player1", -1, -1, 0))
	t.eq(c9.player1.hand[0], "ADCC", "再切換去除後綴")
	c9.dispatch(_act("toggle_upgrade", "player1", -1, -1, 1))
	t.eq(c9.player1.hand[1], "ADCW", "非 Cyan 卡不受影響")

	# 清理注入的 BalanceDB。
	for c in cores:
		if c.balance != null:
			c.balance.free()
