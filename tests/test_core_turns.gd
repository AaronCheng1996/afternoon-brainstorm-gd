# P1-1 驗收：基礎狀態與回合引擎（見 docs/rebuild/06 P1-1、01 §3）。
extends RefCounted


# 建一顆注入 BalanceDB 的 GameCore。
func _make_core(p1_deck: Array, p2_deck: Array, seed_v: int) -> GameCore:
	var db: Object = load("res://script_v2/data/balance_db.gd").new()
	var core := GameCore.new()
	core.setup(p1_deck, p2_deck, seed_v, db)
	return core


func _deck(card_id: String, n: int) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


func run(t: Object) -> void:
	var deck12: Array = _deck("ADCW", 12)

	# --- 1. 開局手牌 3/3、p1 攻擊次數 1、p2 為 0 ---
	var core := _make_core(deck12, deck12, 1)
	t.eq(core.player1.hand.size(), 3, "p1 起手 3 張")
	t.eq(core.player2.hand.size(), 3, "p2 起手 3 張")
	t.eq(core.number_of_attacks["player1"], 1, "p1 攻擊次數 1（先手 +1）")
	t.eq(core.number_of_attacks["player2"], 0, "p2 攻擊次數 0")
	t.eq(core.current_player(), "player1", "首回合為 player1")

	# --- 2. end_turn 後輪替正確（turn_start 抽牌 + 攻擊）---
	core.end_turn("player1")
	t.eq(core.turn_number, 1, "end_turn 後 turn_number=1")
	t.eq(core.current_player(), "player2", "換 player2 回合")
	t.eq(core.number_of_attacks["player2"], 1, "p2 turn_start +1 攻擊")
	t.eq(core.player2.hand.size(), 4, "p2 turn_start 抽 1 → 4 張")

	# --- 3. numbness 棋子首次 settle 得 0 分且之後解除 ---
	var core2 := _make_core(deck12, deck12, 2)
	var piece := PieceState.make("TANKW", "player1", 0, 0, core2.balance)
	core2.player1.on_board.append(piece)
	core2.board.set_occupied(Vector2i(0, 0), true)
	t.ok(piece.is_numb(), "非 ASS 棋子入場暈眩")
	core2.end_turn("player1")   # p1 settle：暈眩 → 0 分並解暈
	t.eq(core2.score, 0, "暈眩棋子首次結算 0 分")
	t.ok(not piece.is_numb(), "結算後解暈")
	core2.end_turn("player2")   # 回到 p1 回合（turn 2）
	core2.end_turn("player1")   # p1 再結算：非暈 → p1 得 1 分（score -1）
	t.eq(core2.score, -1, "解暈後再結算 p1 得 1 分（score -1）")

	# --- 4a. 分數達 +10 觸發勝負（player2 勝）---
	var core3 := _make_core(deck12, deck12, 3)
	core3.score = 9
	var pc2 := PieceState.make("TANKW", "player2", 1, 1, core3.balance)
	pc2.set_numb(false)
	core3.player2.on_board.append(pc2)
	core3.end_turn("player1")             # turn 1 → p2 回合
	var res := core3.end_turn("player2")  # p2 結算 +1 → score 10 → 勝負
	t.ok(core3.is_over(), "分數達門檻遊戲結束")
	t.eq(core3.winner_name(), "player2", "score=10 → player2 勝")
	t.eq(core3.winner(), 1, "winner() = 1")
	t.ok(res.quit, "end_turn 回傳 quit")

	# --- 4b. 分數達 -10 觸發勝負（player1 勝）---
	var core3b := _make_core(deck12, deck12, 4)
	core3b.score = -9
	var pc1 := PieceState.make("TANKW", "player1", 1, 1, core3b.balance)
	pc1.set_numb(false)
	core3b.player1.on_board.append(pc1)
	core3b.end_turn("player1")            # p1 結算 -1 → score -10 → 勝負
	t.ok(core3b.is_over(), "分數達門檻遊戲結束（負向）")
	t.eq(core3b.winner_name(), "player1", "score=-10 → player1 勝")

	# --- 5. skip_turn_draw 生效 ---
	var core4 := _make_core(deck12, deck12, 5)
	core4.skip_turn_draw["player2"] = true
	core4.end_turn("player1")             # 觸發 p2 turn_start
	t.eq(core4.player2.hand.size(), 3, "skip_turn_draw：p2 未抽牌（維持 3）")
	t.eq(core4.skip_turn_draw["player2"], false, "skip_turn_draw 旗標已清")
	t.eq(core4.number_of_attacks["player2"], 1, "略過抽牌仍 +1 攻擊")

	# --- 6. 摸完牌庫會洗棄牌堆再抽 ---
	var core5 := _make_core(deck12, deck12, 6)
	var p := core5.player1
	p.draw_pile.clear()
	p.hand.clear()
	p.discard_pile.assign(["ADCW", "TANKW", "SPW"])
	p.draw_card(core5.rng)
	t.eq(p.hand.size(), 1, "牌庫空 → 洗棄牌堆後抽到 1 張")
	t.eq(p.draw_pile.size(), 2, "棄牌堆洗入牌庫後剩 2 張")
	t.eq(p.discard_pile.size(), 0, "棄牌堆已清空")
	# 牌庫與棄牌堆皆空：不抽。
	p.draw_pile.clear()
	p.discard_pile.clear()
	var before: int = p.hand.size()
	p.draw_card(core5.rng)
	t.eq(p.hand.size(), before, "牌庫與棄牌堆皆空：抽不到牌")

	# 清理注入的 BalanceDB（避免孤兒節點警告）。
	for c in [core, core2, core3, core3b, core4, core5]:
		if c.balance != null:
			c.balance.free()
