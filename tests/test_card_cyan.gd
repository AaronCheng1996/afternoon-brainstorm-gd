# P1-10 驗收：Cyan 全卡 + CoinEngine（翻譯自 Python tests/test_card_cyan.py，
# 追加核心佈線案例：升級數值、ADCC 二連擊、price_check 付費/不足、SPC 折扣、金幣上限、APC 佈署攻擊）。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var core := GameCore.new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	core.setup(deck, deck, seed_v, db)
	return core


# 放一顆非暈眩、佔格的棋子（可指定升級版）。
func _place(core: GameCore, card_id: String, owner: String, x: int, y: int, upgrade: bool = false) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance, upgrade)
	p.set_numb(false)
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func run(t: Object) -> void:
	const DAMAGE_DEALT := Statistics.StatType.DAMAGE_DEALT
	var cores: Array = []

	# ---------------- 升級數值 ----------------
	var c0 := _make_core(100); cores.append(c0)
	var base_adc := PieceState.make("ADCC", "player1", 0, 0, c0.balance, false)
	var up_adc := PieceState.make("ADCC", "player1", 0, 0, c0.balance, true)
	t.eq(base_adc.health, 4, "ADCC 基礎 HP=4")
	t.eq(base_adc.damage, 1, "ADCC 基礎 ATK=1")
	t.eq(up_adc.health, 5, "ADCC 升級 HP=5")
	t.eq(up_adc.damage, 3, "ADCC 升級 ATK=3")

	# ---------------- ADCC ----------------
	# 升級版：二連擊命中兩次。
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCC", "player1", 0, 0, true)
	var enemy1 := _place(c1, "TANKR", "player2", 2, 0); enemy1.health = adc1.damage * 3
	var e1_before: int = enemy1.health
	Combat.attack(c1, adc1)
	t.eq(enemy1.health, e1_before - adc1.damage * 2, "ADCC 升級二連擊命中兩次")

	# ability 給金幣。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCC", "player1", 0, 0)
	_place(c2, "TANKR", "player2", 2, 0)
	var coin2_before: int = c2.players_coin["player1"]
	Combat.attack(c2, adc2)
	t.ok(c2.players_coin["player1"] >= coin2_before + 2, "ADCC 造成傷害後 +2$")

	# ---------------- APC ----------------
	# 攻擊附帶麻痺。
	var c3 := _make_core(3); cores.append(c3)
	var ap3 := _place(c3, "APC", "player1", 0, 0)
	var tgt3 := _place(c3, "ADCR", "player2", 1, 0); tgt3.set_numb(false)
	Combat.attack(c3, ap3)
	t.ok(tgt3.is_numb(), "APC 攻擊後目標麻痺")

	# ability 給金幣。
	var c4 := _make_core(4); cores.append(c4)
	var ap4 := _place(c4, "APC", "player1", 0, 0)
	_place(c4, "ADCR", "player2", 1, 0)
	var coin4_before: int = c4.players_coin["player1"]
	Combat.attack(c4, ap4)
	t.ok(c4.players_coin["player1"] >= coin4_before + 3, "APC 攻擊後 +3$")

	# 佈署攻擊（基礎版無視麻痺攻 number_of_attack 次）。
	var c5 := _make_core(5); cores.append(c5)
	var enemy5 := _place(c5, "TANKR", "player2", 1, 0)   # nearest 目標，15+HP
	var e5_before: int = enemy5.health
	var ok5: bool = c5._spawn_card(0, 0, "APC", "player1", c5.player1.on_board)
	t.ok(ok5, "APC 佈署成功")
	t.eq(enemy5.health, e5_before - 1 * 2, "APC 基礎佈署無視麻痺攻 2 次（ATK1×2）")

	# ---------------- TANKC ----------------
	# 被攻擊給金幣。
	var c6 := _make_core(6); cores.append(c6)
	var tank6 := _place(c6, "TANKC", "player1", 1, 1)
	var atk6 := _place(c6, "ADCW", "player2", 2, 1)
	var coin6_before: int = c6.players_coin["player1"]
	Combat.damage_calculate(c6, tank6, 1, atk6, false, 0.0)
	t.eq(c6.players_coin["player1"], coin6_before + 2, "TANKC 被攻擊後 +2$")

	# 升級版怒氣格擋首擊（整段管線取消）。
	var c7 := _make_core(7); cores.append(c7)
	var tank7 := _place(c7, "TANKC", "player1", 0, 0); tank7.set_anger(true)
	var atk7 := _place(c7, "ADCR", "player2", 1, 0)
	var h7_before: int = tank7.health
	var coin7_before: int = c7.players_coin["player1"]
	Combat.damage_calculate(c7, tank7, 5, atk7, false, 0.0)
	t.eq(tank7.health, h7_before, "TANKC 格擋：血量不變")
	t.ok(not tank7.is_angry(), "TANKC 格擋後怒氣清除")
	t.eq(c7.players_coin["player1"], coin7_before, "TANKC 格擋整段跳過：不觸發 been_attacked 金幣")

	# ---------------- HFC ----------------
	# ability 給金幣。
	var c8 := _make_core(8); cores.append(c8)
	var hf8 := _place(c8, "HFC", "player1", 0, 0)
	_place(c8, "ADCR", "player2", 1, 0)
	var coin8_before: int = c8.players_coin["player1"]
	Combat.attack(c8, hf8)
	t.ok(c8.players_coin["player1"] >= coin8_before + 2, "HFC 造成傷害後 +2$")

	# 升級版被殺 → 怒氣 + ATK+damage_bonus。
	var c9 := _make_core(9); cores.append(c9)
	var hf9 := _place(c9, "HFC", "player1", 0, 0, true)
	var enemy9 := _place(c9, "ADCR", "player2", 1, 0)
	var d9_before: int = hf9.damage
	hf9.abilities.run(Trigger.Type.ON_BEEN_KILLED, AbilityContext.new(c9, hf9, enemy9, 0, {"attacker": enemy9}))
	t.ok(hf9.is_angry(), "HFC 升級被殺後進怒氣")
	t.eq(hf9.damage, d9_before + 2, "HFC 升級被殺後 ATK+damage_bonus")

	# 怒氣時不可被殺。
	var c10 := _make_core(10); cores.append(c10)
	var hf10 := _place(c10, "HFC", "player1", 0, 0); hf10.set_anger(true)
	t.ok(not c10.can_be_killed(hf10), "HFC 怒氣時 can_be_killed=false")

	# 升級版致命一擊：不進 pending_death、不發 death 事件。
	var c11 := _make_core(11); cores.append(c11)
	var hf11 := _place(c11, "HFC", "player1", 0, 0, true)
	var enemy11 := _place(c11, "ADCR", "player2", 1, 0)
	hf11.health = enemy11.damage   # 剛好致命
	c11.event_sink.clear()
	Combat.damage_calculate(c11, hf11, enemy11.damage, enemy11, false, 0.0)
	t.eq(hf11.health, 0, "HFC 升級致命後 HP=0")
	t.ok(hf11.is_angry(), "HFC 升級致命後進怒氣")
	t.ok(not hf11.pending_death, "HFC 升級致命後不設 pending_death")
	var death11: int = c11.event_sink.filter(
		func(e: GameEvent) -> bool: return e.kind == GameEvent.Kind.DEATH).size()
	t.eq(death11, 0, "HFC 升級致命後不發 death 事件")

	# ---------------- LFC ----------------
	# ability 給金幣。
	var c12 := _make_core(12); cores.append(c12)
	var lf12 := _place(c12, "LFC", "player1", 1, 1)
	_place(c12, "ADCR", "player2", 2, 1)
	var coin12_before: int = c12.players_coin["player1"]
	Combat.attack(c12, lf12)
	t.ok(c12.players_coin["player1"] >= coin12_before + 2, "LFC 造成傷害後 +2$")

	# 升級版回合開始隨機換攻擊模式（換成五種之一）。
	var c13 := _make_core(13); cores.append(c13)
	var lf13 := _place(c13, "LFC", "player1", 0, 0, true)
	lf13.abilities.run(Trigger.Type.ON_REFRESH, AbilityContext.new(c13, lf13, null, 0, {}))
	var valid_modes: Array = ["large_cross", "nearest", "small_cross", "small_cross small_x", "farthest"]
	t.ok(valid_modes.has(lf13.attack_types), "LFC 升級回合開始換成合法攻擊模式")

	# ---------------- ASSC ----------------
	# 斬殺給金幣。
	var c14 := _make_core(14); cores.append(c14)
	var ass14 := _place(c14, "ASSC", "player1", 1, 1)
	var e14 := _place(c14, "ADCR", "player2", 2, 2); e14.health = 1
	var coin14_before: int = c14.players_coin["player1"]
	Combat.attack(c14, ass14)
	t.ok(c14.players_coin["player1"] >= coin14_before + 6, "ASSC 斬殺後 +6$")

	# damage_bonus 一次性：extra_damage 加進傷害後歸零。
	var c15 := _make_core(15); cores.append(c15)
	var ass15 := _place(c15, "ASSC", "player1", 0, 0)
	var e15 := _place(c15, "TANKR", "player2", 1, 1)   # small_x，高 HP
	ass15.extra_damage = 2
	Combat.attack(c15, ass15)
	t.eq(c15.stats.get_stat(DAMAGE_DEALT, ass15.uid()), ass15.damage + 2, "ASSC 首擊含 extra_damage")
	t.eq(ass15.extra_damage, 0, "ASSC damage_bonus 用後 extra_damage 歸零")

	# ---------------- APTC ----------------
	# 升級版受傷減免 = 金幣//coin_per。
	var c16 := _make_core(16); cores.append(c16)
	var apt16 := _place(c16, "APTC", "player1", 0, 0, true)
	c16.players_coin["player1"] = 10
	var per16: int = int(c16.balance.param("APTC", "coin_per_damage_resistance", 5))
	var red16: int = apt16.abilities.dispatch_mod(
		Trigger.Type.MOD_DAMAGE_REDUCE, AbilityContext.new(c16, apt16, null, 5, {}))
	t.eq(red16, 5 - (10 / per16), "APTC 升級受傷減免 = 金幣//coin_per")

	# 減免上限。
	var c17 := _make_core(17); cores.append(c17)
	var apt17 := _place(c17, "APTC", "player1", 0, 0, true)
	c17.players_coin["player1"] = 50
	var maxr17: int = int(c17.balance.param("APTC", "maximum_damage_resistance", 3))
	var red17: int = apt17.abilities.dispatch_mod(
		Trigger.Type.MOD_DAMAGE_REDUCE, AbilityContext.new(c17, apt17, null, 10, {}))
	t.eq(red17, 10 - maxr17, "APTC 減免上限 = maximum_damage_resistance")

	# 未升級無減免。
	var c18 := _make_core(18); cores.append(c18)
	var apt18 := _place(c18, "APTC", "player1", 0, 0, false)
	c18.players_coin["player1"] = 50
	var red18: int = apt18.abilities.dispatch_mod(
		Trigger.Type.MOD_DAMAGE_REDUCE, AbilityContext.new(c18, apt18, null, 10, {}))
	t.eq(red18, 10, "APTC 未升級無減免")

	# 回合開始給金幣。
	var c19 := _make_core(19); cores.append(c19)
	var apt19 := _place(c19, "APTC", "player1", 0, 0)
	var coin19_before: int = c19.players_coin["player1"]
	apt19.abilities.run(Trigger.Type.ON_REFRESH, AbilityContext.new(c19, apt19, null, 0, {}))
	t.eq(c19.players_coin["player1"], coin19_before + 4, "APTC 回合開始 +4$")

	# ---------------- SPC ----------------
	# 佈署給金幣。
	var c20 := _make_core(20); cores.append(c20)
	var sp20 := _place(c20, "SPC", "player1", 0, 0)
	var coin20_before: int = c20.players_coin["player1"]
	sp20.abilities.run(Trigger.Type.ON_DEPLOY, AbilityContext.new(c20, sp20, null, 0, {}))
	t.eq(c20.players_coin["player1"], coin20_before + 10, "SPC 佈署 +10$")

	# ---------------- 金幣上限 ----------------
	var c21 := _make_core(21); cores.append(c21)
	var apt21 := _place(c21, "APTC", "player1", 0, 0)
	c21.players_coin["player1"] = 49
	apt21.abilities.run(Trigger.Type.ON_REFRESH, AbilityContext.new(c21, apt21, null, 0, {}))
	t.eq(c21.players_coin["player1"], 50, "金幣上限封頂 50（49+4→50）")

	# ---------------- price_check ----------------
	# 金幣足夠 → 升級版生成成功並扣費。
	var c22 := _make_core(22); cores.append(c22)
	c22.players_coin["player1"] = 6
	var ok22: bool = c22._spawn_card(1, 1, "ADCC", "player1", c22.player1.on_board, true)
	t.ok(ok22, "price_check：金幣足夠升級版生成成功")
	t.eq(c22.players_coin["player1"], 0, "price_check：扣除 cost=6")

	# 金幣不足 → 生成失敗、不扣費。
	var c23 := _make_core(23); cores.append(c23)
	c23.players_coin["player1"] = 5
	var ok23: bool = c23._spawn_card(1, 1, "ADCC", "player1", c23.player1.on_board, true)
	t.ok(not ok23, "price_check：金幣不足升級版生成失敗")
	t.eq(c23.players_coin["player1"], 5, "price_check：失敗不扣費")
	t.ok(c23.board.is_free(Vector2i(1, 1)), "price_check：失敗不佔格")

	# 升級版 SPC 在場 → 折扣 cost_reduction。
	var c24 := _make_core(24); cores.append(c24)
	_place(c24, "SPC", "player1", 0, 0, true)   # 升級版 SPC
	c24.players_coin["player1"] = 4              # cost 6 − reduction 2 = 4
	var ok24: bool = c24._spawn_card(1, 1, "ADCC", "player1", c24.player1.on_board, true)
	t.ok(ok24, "price_check：升級 SPC 折扣後金幣足夠")
	t.eq(c24.players_coin["player1"], 0, "price_check：折扣價 = cost − cost_reduction")

	for c in cores:
		if c.balance != null:
			c.balance.free()
