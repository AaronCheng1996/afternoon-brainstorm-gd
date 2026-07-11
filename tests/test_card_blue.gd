# P1-6 驗收：Blue 全卡 + TokenEngine（翻譯自 Python tests/test_card_blue.py，
# 追加任務指定案例：ADCB 追加攻擊經佇列、APB token=2 只換 1 抽剩 1 球、SPB 佈署爆發+清佇列）。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var core := GameCore.new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	core.setup(deck, deck, seed_v, db)
	return core


# 放一顆非暈眩、佔格的棋子（對齊 Python place_card + do_attack 清 numbness）。
func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	p.set_numb(false)
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func _run_token_draw(core: GameCore, piece: PieceState) -> void:
	piece.abilities.run(Trigger.Type.ON_TOKEN_DRAW, AbilityContext.new(core, piece, null, 0, {}))


func run(t: Object) -> void:
	const DAMAGE_DEALT := Statistics.StatType.DAMAGE_DEALT
	var cores: Array = []

	# ---------------- ADCB ----------------
	# 斬殺後獲得 token（token_gain=2，未達門檻不換抽）。
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCB", "player1", 1, 1)
	var e1 := _place(c1, "TANKW", "player2", 3, 1); e1.health = 1
	var tok1_before: int = c1.players_token["player1"]
	Combat.attack(c1, adc1)
	t.ok(c1.players_token["player1"] >= tok1_before + 2, "ADCB 斬殺後獲得 2 token")

	# 斬殺達門檻 → card_to_draw 增加。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCB", "player1", 0, 0)
	var e2 := _place(c2, "TANKW", "player2", 2, 0); e2.health = 1
	c2.players_token["player1"] = 3 - 2   # 斬殺 +2 剛好達門檻 3
	var draw2_before: int = c2.card_to_draw["player1"]
	Combat.attack(c2, adc2)
	t.ok(c2.card_to_draw["player1"] > draw2_before, "ADCB 斬殺達門檻換 1 抽")

	# 斬殺達門檻 → token_draw 排入一次免費攻擊（經佇列、不遞迴）：第二目標被打兩次。
	var c3 := _make_core(3); cores.append(c3)
	var adc3 := _place(c3, "ADCB", "player1", 0, 0)
	var victim3 := _place(c3, "TANKW", "player2", 2, 0); victim3.health = 1
	var second3 := _place(c3, "TANKW", "player2", 0, 2)
	c3.players_token["player1"] = 3 - 2
	var second3_before: int = second3.health
	Combat.attack(c3, adc3)
	t.ok(victim3.health <= 0, "ADCB 追加攻擊：首目標被斬")
	t.ok(c3.card_to_draw["player1"] >= 1, "ADCB 追加攻擊：達門檻換抽")
	t.eq(second3.health, second3_before - adc3.damage * 2, "ADCB 追加攻擊：次目標被打兩次")

	# token_draw：麻痺者被解除麻痺（不排攻擊）。
	var c4 := _make_core(4); cores.append(c4)
	var adc4 := _place(c4, "ADCB", "player1", 0, 0)
	adc4.set_numb(true)
	_run_token_draw(c4, adc4)
	t.ok(not adc4.is_numb(), "ADCB token_draw 解除麻痺")
	t.eq(c4.pending_attacks.size(), 0, "ADCB token_draw 麻痺時不排攻擊")

	# token_draw：非麻痺者排入一次攻擊。
	var c5 := _make_core(5); cores.append(c5)
	var adc5 := _place(c5, "ADCB", "player1", 0, 0)
	adc5.set_numb(false)
	_run_token_draw(c5, adc5)
	t.eq(c5.pending_attacks.size(), 1, "ADCB token_draw 非麻痺時排 1 次攻擊")

	# ---------------- APB ----------------
	# 攻擊附帶麻痺。
	var c6 := _make_core(6); cores.append(c6)
	var ap6 := _place(c6, "APB", "player1", 0, 0)
	var tgt6 := _place(c6, "TANKW", "player2", 1, 0); tgt6.set_numb(false)
	Combat.attack(c6, ap6)
	t.ok(tgt6.is_numb(), "APB 攻擊後目標麻痺")

	# 攻擊獲得 token_gain=2（未達門檻）。
	var c7 := _make_core(7); cores.append(c7)
	var ap7 := _place(c7, "APB", "player1", 0, 0)
	_place(c7, "TANKW", "player2", 1, 0)
	var tok7_before: int = c7.players_token["player1"]
	Combat.attack(c7, ap7)
	t.ok(c7.players_token["player1"] >= tok7_before + 2, "APB 攻擊後獲得 2 token")

	# 追加驗收：token 起始 2 → APB 攻擊 got_token 兩次，只換 1 抽、剩 1 球。
	var c8 := _make_core(8); cores.append(c8)
	var ap8 := _place(c8, "APB", "player1", 0, 0)
	_place(c8, "TANKW", "player2", 1, 0)
	c8.players_token["player1"] = 2
	var draw8_before: int = c8.card_to_draw["player1"]
	Combat.attack(c8, ap8)   # +2 → 4；got_token#1 換抽剩 1；got_token#2 不足
	t.eq(c8.card_to_draw["player1"], draw8_before + 1, "APB token=2 攻擊只換 1 抽")
	t.eq(c8.players_token["player1"], 1, "APB token=2 攻擊後剩 1 球")

	# ---------------- TANKB ----------------
	# 被攻擊後獲得 token_gain=1。
	var c9 := _make_core(9); cores.append(c9)
	var tank9 := _place(c9, "TANKB", "player1", 1, 1)
	var atk9 := _place(c9, "ADCW", "player2", 2, 1)
	var tok9_before: int = c9.players_token["player1"]
	Combat.damage_calculate(c9, tank9, 1, atk9, false, 0.0)
	t.eq(c9.players_token["player1"], tok9_before + 1, "TANKB 被攻擊後獲得 1 token")

	# ---------------- HFB ----------------
	# extra_damage = 我方當前 token 數。
	var c10 := _make_core(10); cores.append(c10)
	var hf10 := _place(c10, "HFB", "player1", 0, 0)
	c10.players_token["player1"] = 5
	hf10.abilities.run(Trigger.Type.ON_UPDATE, AbilityContext.new(c10, hf10, null, 0, {}))
	t.eq(hf10.extra_damage, 5, "HFB extra_damage = token 數")

	# 造成傷害含 extra_damage（token=4 → 傷害 = base+4）。
	var c11 := _make_core(11); cores.append(c11)
	var hf11 := _place(c11, "HFB", "player1", 0, 0)
	var tgt11 := _place(c11, "TANKW", "player2", 0, 1)   # 15HP，九宮格內
	c11.players_token["player1"] = 4
	hf11.abilities.run(Trigger.Type.ON_UPDATE, AbilityContext.new(c11, hf11, null, 0, {}))
	var expect11: int = hf11.damage + 4
	Combat.attack(c11, hf11)
	t.eq(c11.stats.get_stat(DAMAGE_DEALT, hf11.uid()), expect11, "HFB 傷害含 extra_damage")

	# ---------------- LFB ----------------
	# 造成傷害後獲得 token_gain=1。
	var c12 := _make_core(12); cores.append(c12)
	var lf12 := _place(c12, "LFB", "player1", 1, 1)
	_place(c12, "TANKW", "player2", 2, 1)
	var tok12_before: int = c12.players_token["player1"]
	Combat.attack(c12, lf12)
	t.ok(c12.players_token["player1"] >= tok12_before + 1, "LFB 攻擊後獲得 1 token")

	# ---------------- ASSB ----------------
	# 斬殺後獲得 token_gain=2。
	var c13 := _make_core(13); cores.append(c13)
	var ass13 := _place(c13, "ASSB", "player1", 1, 1)
	var e13 := _place(c13, "TANKW", "player2", 2, 0); e13.health = 1
	var tok13_before: int = c13.players_token["player1"]
	Combat.attack(c13, ass13)
	t.ok(c13.players_token["player1"] >= tok13_before + 2, "ASSB 斬殺後獲得 2 token")

	# 未斬殺不獲 token。
	var c14 := _make_core(14); cores.append(c14)
	var ass14 := _place(c14, "ASSB", "player1", 1, 1)
	_place(c14, "TANKW", "player2", 2, 0)   # 15HP，不會被斬
	var tok14_before: int = c14.players_token["player1"]
	Combat.attack(c14, ass14)
	t.eq(c14.players_token["player1"], tok14_before, "ASSB 未斬殺不獲 token")

	# ---------------- APTB ----------------
	# 每獲得一次 token → 自身 +1 護盾（after_token）。
	var c15 := _make_core(15); cores.append(c15)
	var apt15 := _place(c15, "APTB", "player1", 0, 0)
	var arm15_before: int = apt15.armor
	apt15.abilities.run(Trigger.Type.ON_TOKEN_GAINED, AbilityContext.new(c15, apt15, null, 0, {}))
	t.eq(apt15.armor, arm15_before + 1, "APTB after_token +1 護盾")

	# extra_damage = armor//divisor；造成傷害後獲得等量 token。
	var c16 := _make_core(16); cores.append(c16)
	var apt16 := _place(c16, "APTB", "player1", 0, 0)
	_place(c16, "TANKW", "player2", 1, 0)
	var div16: int = int(c16.balance.param("APTB", "token_from_armor_divisor", 3))
	apt16.armor = div16 * 2
	apt16.abilities.run(Trigger.Type.ON_UPDATE, AbilityContext.new(c16, apt16, null, 0, {}))
	t.eq(apt16.extra_damage, 2, "APTB extra_damage = armor//divisor")
	var tok16_before: int = c16.players_token["player1"]
	Combat.attack(c16, apt16)
	t.ok(c16.players_token["player1"] >= tok16_before + 2, "APTB 造成 2 傷後獲得 2 token")

	# ---------------- SPB ----------------
	# 佈署：對隨機敵方重複（我方場上數+棄牌堆數）次各造成 spawn_damage 傷，最後清佇列。
	var c17 := _make_core(17); cores.append(c17)
	_place(c17, "ADCW", "player1", 1, 1)          # 我方場上 1 子（SPB 尚未計入）
	c17.player1.discard_pile = ["ADCW", "ADCW"]   # 棄牌堆 2 → count = 3
	var enemy17 := _place(c17, "TANKW", "player2", 3, 3)   # 唯一敵方（15HP）
	var enemy17_before: int = enemy17.health
	c17.pending_attacks.append(Combat.make_request(enemy17))   # 佈署後應被清空
	var ok17: bool = c17._spawn_card(0, 0, "SPB", "player1", c17.player1.on_board)
	t.ok(ok17, "SPB 生成成功")
	t.eq(enemy17.health, enemy17_before - 3, "SPB 佈署對敵方造成 3 傷（count=3×1）")
	t.eq(c17.pending_attacks.size(), 0, "SPB 佈署後清空攻擊佇列")

	for c in cores:
		if c.balance != null:
			c.balance.free()
