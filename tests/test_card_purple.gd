# P1-13 驗收：Purple 4 卡（翻譯自 Python tests/test_card_purple.py，追加佈署驅散與抽牌上限邊界）。
# 紫色僅實作 AP/TANK/HF/ASS；主題為控制（驅散、反移動、加攻擊次數、擊殺爆抽）。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var core := GameCore.new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	core.setup(deck, deck, seed_v, db)
	return core


func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	p.set_numb(false)
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func run(t: Object) -> void:
	var cores: Array = []

	# ---------------- APP：攻擊附帶麻痺 + 驅散 ----------------
	# 麻痺目標。
	var c1 := _make_core(1); cores.append(c1)
	var ap1 := _place(c1, "APP", "player1", 0, 0)
	var tgt1 := _place(c1, "ADCR", "player2", 1, 0)   # AP nearest
	CombatV2.attack(c1, ap1)
	t.ok(tgt1.is_numb(), "APP 攻擊 → 目標麻痺")

	# 驅散：護盾歸 0。
	var c2 := _make_core(2); cores.append(c2)
	var ap2 := _place(c2, "APP", "player1", 0, 0)
	var tgt2 := _place(c2, "ADCR", "player2", 1, 0)
	tgt2.armor = 10
	CombatV2.attack(c2, ap2)
	t.eq(tgt2.armor, 0, "APP 攻擊 → 目標護盾歸 0")

	# 驅散：ATK 回原值。
	var c3 := _make_core(3); cores.append(c3)
	var ap3 := _place(c3, "APP", "player1", 0, 0)
	var tgt3 := _place(c3, "ADCR", "player2", 1, 0)
	tgt3.damage = tgt3.original_damage + 5
	CombatV2.attack(c3, ap3)
	t.eq(tgt3.damage, tgt3.original_damage, "APP 攻擊 → 目標 ATK 回原值")

	# 佈署驅散最近敵方（護盾歸 0、ATK 回原值），不麻痺。
	var c4 := _make_core(4); cores.append(c4)
	var ap4 := _place(c4, "APP", "player1", 0, 0)
	var tgt4 := _place(c4, "ADCR", "player2", 1, 0)
	tgt4.armor = 7
	tgt4.damage = tgt4.original_damage + 3
	ap4.abilities.run(TriggerV2.Type.ON_DEPLOY, AbilityContextV2.new(c4, ap4, null, 0, {}))
	t.eq(tgt4.armor, 0, "APP 佈署 → 最近敵方護盾歸 0")
	t.eq(tgt4.damage, tgt4.original_damage, "APP 佈署 → 最近敵方 ATK 回原值")
	t.ok(not tgt4.is_numb(), "APP 佈署驅散不附帶麻痺")

	# ---------------- TANKP：敵方移動後被反擊 ----------------
	# 敵方移動 → 造成 move_strike_damage。
	var c5 := _make_core(5); cores.append(c5)
	var tank5 := _place(c5, "TANKP", "player1", 0, 0)
	var enemy5 := _place(c5, "ADCR", "player2", 1, 0)
	var e5_before: int = enemy5.health
	var strike: int = int(c5.balance.param("TANKP", "move_strike_damage", 0))
	tank5.abilities.run(TriggerV2.Type.ON_MOVE_BROADCAST, AbilityContextV2.new(c5, tank5, enemy5, 0, {"mover": enemy5}))
	t.eq(enemy5.health, e5_before - strike, "TANKP：敵方移動 → 造成 move_strike_damage")

	# 我方移動 → 不反擊。
	var c6 := _make_core(6); cores.append(c6)
	var tank6 := _place(c6, "TANKP", "player1", 0, 0)
	var ally6 := _place(c6, "ADCR", "player1", 0, 1)
	var a6_before: int = ally6.health
	tank6.abilities.run(TriggerV2.Type.ON_MOVE_BROADCAST, AbilityContextV2.new(c6, tank6, ally6, 0, {"mover": ally6}))
	t.eq(ally6.health, a6_before, "TANKP：我方移動 → 不反擊")

	# ---------------- HFP：範圍內每 3 敵人 +1 攻擊次數 ----------------
	# 3 個敵人在攻擊範圍 → +1。
	var c7 := _make_core(7); cores.append(c7)
	var hf7 := _place(c7, "HFP", "player1", 1, 1)
	_place(c7, "ADCR", "player2", 0, 0)   # small_x
	_place(c7, "ADCR", "player2", 1, 0)   # small_cross
	_place(c7, "ADCR", "player2", 2, 0)   # small_x
	var atk7_before: int = c7.number_of_attacks["player1"]
	hf7.abilities.run(TriggerV2.Type.ON_REFRESH, AbilityContextV2.new(c7, hf7, null, 0, {}))
	t.eq(c7.number_of_attacks["player1"], atk7_before + 1, "HFP：範圍內 3 敵人 → 攻擊次數 +1")

	# 少於 3 敵人 → 無加成。
	var c8 := _make_core(8); cores.append(c8)
	var hf8 := _place(c8, "HFP", "player1", 1, 1)
	_place(c8, "ADCR", "player2", 0, 0)
	_place(c8, "ADCR", "player2", 1, 0)
	var atk8_before: int = c8.number_of_attacks["player1"]
	hf8.abilities.run(TriggerV2.Type.ON_REFRESH, AbilityContextV2.new(c8, hf8, null, 0, {}))
	t.eq(c8.number_of_attacks["player1"], atk8_before, "HFP：少於 3 敵人 → 無加成")

	# ---------------- ASSP：擊殺依人數差爆抽（含上限）----------------
	# 敵方 4、我方 1 → 抽 min(4-1-2, 12) = 1。
	var c9 := _make_core(9); cores.append(c9)
	var ass9 := _place(c9, "ASSP", "player1", 1, 1)
	var v9 := _place(c9, "ADCR", "player2", 2, 0); v9.health = 1   # small_x
	_place(c9, "ADCR", "player2", 2, 1)
	_place(c9, "ADCR", "player2", 2, 2)
	_place(c9, "ADCR", "player2", 3, 0)
	var d9_before: int = c9.card_to_draw["player1"]
	CombatV2.attack(c9, ass9)
	t.eq(c9.card_to_draw["player1"], d9_before + 1, "ASSP：敵4 我1 → 抽 (4-1-2)=1")

	# 人數差不足 → 不抽（敵 2、我 1 → 2-1-2 = -1）。
	var c10 := _make_core(10); cores.append(c10)
	var ass10 := _place(c10, "ASSP", "player1", 1, 1)
	var v10 := _place(c10, "ADCR", "player2", 2, 0); v10.health = 1
	_place(c10, "ADCR", "player2", 2, 1)
	var d10_before: int = c10.card_to_draw["player1"]
	CombatV2.attack(c10, ass10)
	t.eq(c10.card_to_draw["player1"], d10_before, "ASSP：人數差不足 → 不抽")

	# 上限邊界：填滿棋盤（敵 15、我 1）→ min(15-1-2, 12) = 12（恰達上限）。
	var c11 := _make_core(11); cores.append(c11)
	var ass11 := _place(c11, "ASSP", "player1", 1, 1)
	var kill11: PieceState = null
	for x in 4:
		for y in 4:
			if x == 1 and y == 1:
				continue
			var e := _place(c11, "ADCR", "player2", x, y)
			if x == 0 and y == 0:
				kill11 = e   # (0,0) 為 ASS small_x 目標
	kill11.health = 1
	var d11_before: int = c11.card_to_draw["player1"]
	CombatV2.attack(c11, ass11)
	t.eq(c11.card_to_draw["player1"], d11_before + 12, "ASSP：填滿棋盤 → 抽牌達上限 12")

	for c in cores:
		if c.balance != null:
			c.balance.free()
