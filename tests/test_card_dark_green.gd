# P1-9 驗收：DarkGreen 全卡 + 圖騰引擎（翻譯自 Python tests/test_card_dark_green.py，
# 追加：SPDKG 2^n 刻印倍率、LFDKG 佈署 small_cross 傷害）。
# 深綠主題：圖騰刻印（players_totem）→ extra_damage = 圖騰 // divisor。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script_v2/data/balance_db.gd").new()
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

	# ---------------- ADCDKG ----------------
	# update：extra_damage = 圖騰 // damage_divisor(4)。
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCDKG", "player1", 0, 0)
	c1.players_totem["player1"] = 8
	adc1.abilities.run(TriggerV2.Type.ON_UPDATE, AbilityContextV2.new(c1, adc1, null, 0, {}))
	t.eq(adc1.extra_damage, 8 / int(c1.balance.param("ADCDKG", "damage_divisor", 4)), "ADCDKG update：extra_damage = 圖騰//4")

	# extra_damage 經傷害管線生效（damage_bonus 沿用 base = value + extra_damage）。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCDKG", "player1", 0, 0)
	var vic2 := _place(c2, "TANKW", "player2", 2, 0)   # large_cross 同列
	adc2.extra_damage = 3
	var v2_before: int = vic2.health
	CombatV2.attack(c2, adc2)
	t.eq(vic2.health, v2_before - (adc2.damage + 3), "ADCDKG extra_damage 加成命中 = ATK + extra")

	# ---------------- APDKG ----------------
	# 攻擊附帶麻痺。
	var c3 := _make_core(3); cores.append(c3)
	var ap3 := _place(c3, "APDKG", "player1", 0, 0)
	var tgt3 := _place(c3, "ADCR", "player2", 1, 0); tgt3.set_numb(false)
	CombatV2.attack(c3, ap3)
	t.ok(tgt3.is_numb(), "APDKG 攻擊後目標麻痺")

	# 攻擊刻印 engraved_totem(5)。
	var c4 := _make_core(4); cores.append(c4)
	var ap4 := _place(c4, "APDKG", "player1", 0, 0)
	_place(c4, "ADCR", "player2", 1, 0)
	var tot4_before: int = c4.players_totem["player1"]
	CombatV2.attack(c4, ap4)
	t.eq(c4.players_totem["player1"], tot4_before + int(c4.balance.param("APDKG", "engraved_totem", 0)), "APDKG 攻擊刻印 +5")

	# ---------------- TANKDKG ----------------
	# 被攻擊後刻印 engraved_totem(3)。
	var c5 := _make_core(5); cores.append(c5)
	var tank5 := _place(c5, "TANKDKG", "player1", 1, 1)
	var atk5 := _place(c5, "ADCR", "player2", 2, 1)
	var tot5_before: int = c5.players_totem["player1"]
	tank5.abilities.run(TriggerV2.Type.ON_BEEN_ATTACKED, AbilityContextV2.new(c5, tank5, atk5, 1, {}))
	t.eq(c5.players_totem["player1"], tot5_before + int(c5.balance.param("TANKDKG", "engraved_totem", 0)), "TANKDKG 被攻擊刻印 +3")

	# ---------------- HFDKG ----------------
	# 造成傷害後自療 1。
	var c6 := _make_core(6); cores.append(c6)
	var hf6 := _place(c6, "HFDKG", "player1", 0, 0)
	_place(c6, "TANKW", "player2", 1, 0)   # small_cross
	hf6.health = hf6.max_health - 2
	var h6_before: int = hf6.health
	CombatV2.attack(c6, hf6)
	t.ok(hf6.health > h6_before, "HFDKG 造成傷害後自療")

	# 回合開始自傷 + 刻印 engraved_totem(2)。
	var c7 := _make_core(7); cores.append(c7)
	var hf7 := _place(c7, "HFDKG", "player1", 0, 0)
	var h7_before: int = hf7.health
	var tot7_before: int = c7.players_totem["player1"]
	hf7.abilities.run(TriggerV2.Type.ON_REFRESH, AbilityContextV2.new(c7, hf7, null, 0, {}))
	t.ok(hf7.health < h7_before, "HFDKG 回合開始自傷")
	t.eq(c7.players_totem["player1"], tot7_before + int(c7.balance.param("HFDKG", "engraved_totem", 0)), "HFDKG 回合開始刻印 +2")

	# ---------------- LFDKG ----------------
	# 造成傷害後刻印 engraved_totem(1)。
	var c8 := _make_core(8); cores.append(c8)
	var lf8 := _place(c8, "LFDKG", "player1", 1, 1)
	_place(c8, "ADCR", "player2", 2, 1)   # small_cross
	var tot8_before: int = c8.players_totem["player1"]
	CombatV2.attack(c8, lf8)
	t.eq(c8.players_totem["player1"], tot8_before + int(c8.balance.param("LFDKG", "engraved_totem", 0)), "LFDKG 攻擊刻印 +1")

	# 佈署對 small_cross 敵方造成 圖騰//4 傷害。
	var c9 := _make_core(9); cores.append(c9)
	var lf9 := _place(c9, "LFDKG", "player1", 1, 1)
	var vic9 := _place(c9, "TANKW", "player2", 0, 1)   # small_cross 內
	c9.players_totem["player1"] = 8
	var v9_before: int = vic9.health
	lf9.abilities.run(TriggerV2.Type.ON_DEPLOY, AbilityContextV2.new(c9, lf9, null, 0, {}))
	t.eq(vic9.health, v9_before - 2, "LFDKG 佈署對 small_cross 敵方造成 圖騰(8)//4 = 2 傷害")

	# ---------------- ASSDKG ----------------
	# 斬殺 → 自身 HP 歸 0（自殺）+ 刻印 engraved_totem(7)。
	var c10 := _make_core(10); cores.append(c10)
	var ass10 := _place(c10, "ASSDKG", "player1", 1, 1)
	var enemy10 := _place(c10, "ADCR", "player2", 2, 0); enemy10.health = 1   # small_x
	var tot10_before: int = c10.players_totem["player1"]
	CombatV2.attack(c10, ass10)
	t.eq(c10.players_totem["player1"], tot10_before + int(c10.balance.param("ASSDKG", "engraved_totem", 0)), "ASSDKG 斬殺刻印 +7")
	t.eq(ass10.health, 0, "ASSDKG 斬殺後自身 HP 歸 0")

	# ---------------- APTDKG ----------------
	# update：extra_damage = 圖騰 // 2。
	var c11 := _make_core(11); cores.append(c11)
	var apt11 := _place(c11, "APTDKG", "player1", 0, 0)
	c11.players_totem["player1"] = 6
	apt11.abilities.run(TriggerV2.Type.ON_UPDATE, AbilityContextV2.new(c11, apt11, null, 0, {}))
	t.eq(apt11.extra_damage, 3, "APTDKG update：extra_damage = 圖騰(6)//2 = 3")

	# extra_damage 經管線只加一次（damage_bonus 副作用不重複加值）。
	var c12 := _make_core(12); cores.append(c12)
	var apt12 := _place(c12, "APTDKG", "player1", 0, 0)
	var vic12 := _place(c12, "TANKW", "player2", 1, 0)   # nearest
	apt12.extra_damage = 4
	var v12_before: int = vic12.health
	CombatV2.attack(c12, apt12)
	t.eq(vic12.health, v12_before - 4, "APTDKG extra_damage 只加一次（ATK0 + extra4 = 4）")

	# after_damage_calculated：armor += value//2。
	var c13 := _make_core(13); cores.append(c13)
	var apt13 := _place(c13, "APTDKG", "player1", 0, 0)
	var t13 := _place(c13, "ADCR", "player2", 1, 0)
	var arm13_before: int = apt13.armor
	apt13.abilities.run(TriggerV2.Type.ON_AFTER_DAMAGE, AbilityContextV2.new(c13, apt13, t13, 6, {}))
	t.eq(apt13.armor, arm13_before + 3, "APTDKG 造成傷害後 armor += value(6)//2")

	# ---------------- SPDKG 刻印倍率 ----------------
	# 場上 1 張 SPDKG → 刻印量 ×2^1；TANKDKG 被攻擊刻印 3 → 實得 6。
	var c14 := _make_core(14); cores.append(c14)
	_place(c14, "SPDKG", "player1", 0, 0)
	var tank14 := _place(c14, "TANKDKG", "player1", 1, 1)
	var atk14 := _place(c14, "ADCR", "player2", 2, 1)
	var tot14_before: int = c14.players_totem["player1"]
	tank14.abilities.run(TriggerV2.Type.ON_BEEN_ATTACKED, AbilityContextV2.new(c14, tank14, atk14, 1, {}))
	t.eq(c14.players_totem["player1"], tot14_before + 6, "SPDKG 在場：TANKDKG 刻印 3 ×2 = 6")

	for c in cores:
		if c.balance != null:
			c.balance.free()
