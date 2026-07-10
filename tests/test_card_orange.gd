# P1-8 驗收：Orange 全卡（翻譯自 Python tests/test_card_orange.py，
# 追加：攻擊覆寫獲得移動、移動連鎖攻擊、APTO/SPO move_broadcast 整合）。
# 橘色主題：攻擊後移動、移動後連鎖效果、MOVEO 臨時移動卡發放。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script_v2/data/balance_db.gd").new()
	var core := GameCore.new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	core.setup(deck, deck, seed_v, db)
	return core


# 放一顆非暈眩、佔格的棋子（對齊 Python place_card）。
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
	var HF_MOVE_GAIN := 1
	var APT_ARMOR_GAIN := 1
	var ASS_ATK_GAIN := 1

	# ---------------- ADCO ----------------
	# 攻擊後獲得移動：ADCO 攻擊命中 → moving。
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCO", "player1", 0, 0)
	_place(c1, "TANKR", "player2", 2, 0)          # large_cross 同列命中
	CombatV2.attack(c1, adc1)
	t.ok(adc1.is_moving(), "ADCO 攻擊成功後獲得移動")

	# 移動後再攻擊：ADCO moving → 移到 (0,1) → after_movement 再打 (0,2)。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCO", "player1", 0, 0)
	var enemy2 := _place(c2, "TANKR", "player2", 0, 2)
	adc2.set_moving(true)
	var e2_before: int = enemy2.health
	t.ok(c2._move_piece(adc2, 0, 1), "ADCO 移動成功")
	t.eq(enemy2.health, e2_before - adc2.damage, "ADCO 移動後再攻擊命中最遠同列敵方")

	# ---------------- APO ----------------
	# 攻擊附帶麻痺目標。
	var c3 := _make_core(3); cores.append(c3)
	var ap3 := _place(c3, "APO", "player1", 0, 0)
	var tgt3 := _place(c3, "ADCR", "player2", 1, 0); tgt3.set_numb(false)
	CombatV2.attack(c3, ap3)
	t.ok(tgt3.is_numb(), "APO 攻擊後目標麻痺")

	# 回合開始獲得一張 MOVEO。
	var c4 := _make_core(4); cores.append(c4)
	var ap4 := _place(c4, "APO", "player1", 0, 0)
	var hand4_before: int = c4.get_player("player1").hand.size()
	ap4.abilities.run(TriggerV2.Type.ON_REFRESH, AbilityContextV2.new(c4, ap4, null, 0, {}))
	t.eq(c4.get_player("player1").hand.size(), hand4_before + 1, "APO 回合開始手牌 +1")
	t.eq(String(c4.get_player("player1").hand[-1]), "MOVEO", "APO 加入的是 MOVEO")

	# ---------------- TANKO ----------------
	# 被攻擊後獲得一張 MOVEO。
	var c5 := _make_core(5); cores.append(c5)
	var tank5 := _place(c5, "TANKO", "player1", 1, 1)
	var atk5 := _place(c5, "ADCR", "player2", 2, 1)
	var hand5_before: int = c5.get_player("player1").hand.size()
	tank5.abilities.run(TriggerV2.Type.ON_BEEN_ATTACKED, AbilityContextV2.new(c5, tank5, atk5, 1, {}))
	t.eq(c5.get_player("player1").hand.size(), hand5_before + 1, "TANKO 被攻擊後手牌 +1")
	t.eq(String(c5.get_player("player1").hand[-1]), "MOVEO", "TANKO 加入的是 MOVEO")

	# ---------------- HFO ----------------
	# 移動後 extra_damage +move_damage_gain 且進怒氣。
	var c6 := _make_core(6); cores.append(c6)
	var hf6 := _place(c6, "HFO", "player1", 0, 0)
	var ed6_before: int = hf6.extra_damage
	hf6.abilities.run(TriggerV2.Type.ON_AFTER_MOVEMENT, AbilityContextV2.new(c6, hf6, null, 0, {}))
	t.eq(hf6.extra_damage, ed6_before + HF_MOVE_GAIN, "HFO 移動後 extra_damage +1")
	t.ok(hf6.is_angry(), "HFO 移動後進怒氣")

	# extra_damage 加成經傷害管線生效（base damage_bonus = value + extra_damage）。
	var c7 := _make_core(7); cores.append(c7)
	var hf7 := _place(c7, "HFO", "player1", 0, 0)
	var vic7 := _place(c7, "TANKW", "player2", 1, 0)   # small_cross 命中，白 TANK 無被擊能力
	hf7.extra_damage = 3
	var v7_before: int = vic7.health
	CombatV2.attack(c7, hf7)
	t.eq(vic7.health, v7_before - (hf7.damage + 3), "HFO extra_damage 加成命中傷害 = ATK + extra")

	# 結算清除 extra_damage 與怒氣。
	var c8 := _make_core(8); cores.append(c8)
	var hf8 := _place(c8, "HFO", "player1", 0, 0)
	hf8.extra_damage = 5
	hf8.set_anger(true)
	c8.settle_piece(hf8)
	t.eq(hf8.extra_damage, 0, "HFO 結算清除 extra_damage")
	t.ok(not hf8.is_angry(), "HFO 結算清除怒氣")

	# ---------------- LFO ----------------
	# 攻擊後獲得移動。
	var c9 := _make_core(9); cores.append(c9)
	var lf9 := _place(c9, "LFO", "player1", 0, 0)
	_place(c9, "TANKR", "player2", 1, 0)          # small_cross 命中
	CombatV2.attack(c9, lf9)
	t.ok(lf9.is_moving(), "LFO 攻擊成功後獲得移動")

	# 移動後對最近敵方（不含中立）造成 ATK 傷害。
	var c10 := _make_core(10); cores.append(c10)
	var lf10 := _place(c10, "LFO", "player1", 1, 1)
	var enemy10 := _place(c10, "ADCR", "player2", 2, 1)
	var e10_before: int = enemy10.health
	lf10.abilities.run(TriggerV2.Type.ON_AFTER_MOVEMENT, AbilityContextV2.new(c10, lf10, null, 0, {}))
	t.ok(enemy10.health < e10_before, "LFO 移動後打擊最近敵方")

	# ---------------- ASSO ----------------
	# 移動後進怒氣。
	var c11 := _make_core(11); cores.append(c11)
	var ass11 := _place(c11, "ASSO", "player1", 0, 0)
	ass11.abilities.run(TriggerV2.Type.ON_AFTER_MOVEMENT, AbilityContextV2.new(c11, ass11, null, 0, {}))
	t.ok(ass11.is_angry(), "ASSO 移動後進怒氣")

	# 怒氣斬殺 → 攻擊次數 +attack_gain_per_kill。
	var c12 := _make_core(12); cores.append(c12)
	var ass12 := _place(c12, "ASSO", "player1", 1, 1)
	var enemy12 := _place(c12, "ADCR", "player2", 2, 0); enemy12.health = 1   # small_x
	ass12.set_anger(true)
	var atk12_before: int = c12.number_of_attacks["player1"]
	CombatV2.attack(c12, ass12)
	t.ok(enemy12.health <= 0, "ASSO 斬殺敵方")
	t.eq(c12.number_of_attacks["player1"], atk12_before + ASS_ATK_GAIN, "ASSO 怒氣斬殺攻擊次數 +1")

	# 無怒氣斬殺 → 攻擊次數不變。
	var c13 := _make_core(13); cores.append(c13)
	var ass13 := _place(c13, "ASSO", "player1", 1, 1)
	var enemy13 := _place(c13, "ADCR", "player2", 2, 0); enemy13.health = 1
	ass13.set_anger(false)
	var atk13_before: int = c13.number_of_attacks["player1"]
	CombatV2.attack(c13, ass13)
	t.eq(c13.number_of_attacks["player1"], atk13_before, "ASSO 無怒氣斬殺攻擊次數不變")

	# ---------------- APTO ----------------
	# 移動後 armor 轉 damage：armor 1 → +1 = 2 → damage +1、armor = 0。
	var c14 := _make_core(14); cores.append(c14)
	var apt14 := _place(c14, "APTO", "player1", 0, 0)
	apt14.armor = 1
	var dmg14_before: int = apt14.damage
	apt14.abilities.run(TriggerV2.Type.ON_AFTER_MOVEMENT, AbilityContextV2.new(c14, apt14, null, 0, {}))
	t.eq(apt14.damage, dmg14_before + 1, "APTO 移動後 armor//2 轉為 damage")
	t.eq(apt14.armor, 0, "APTO 移動後 armor 取餘為 0")

	# 我方棋子移動 → 該棋子與 APTO 各 +move_armor_gain 護盾。
	var c15 := _make_core(15); cores.append(c15)
	var apt15 := _place(c15, "APTO", "player1", 0, 0)
	var ally15 := _place(c15, "ADCR", "player1", 0, 1)
	var apt15_before: int = apt15.armor
	var ally15_before: int = ally15.armor
	apt15.abilities.run(TriggerV2.Type.ON_MOVE_BROADCAST, AbilityContextV2.new(c15, apt15, ally15, 0, {"mover": ally15}))
	t.eq(apt15.armor, apt15_before + APT_ARMOR_GAIN, "APTO 我方移動：自身 +1 護盾")
	t.eq(ally15.armor, ally15_before + APT_ARMOR_GAIN, "APTO 我方移動：移動者 +1 護盾")

	# ---------------- SPO ----------------
	# 我方棋子移動 → 對最遠敵方造成 move_strike_damage 傷害。
	var c16 := _make_core(16); cores.append(c16)
	var sp16 := _place(c16, "SPO", "player1", 0, 0)
	var ally16 := _place(c16, "ADCR", "player1", 0, 1)
	var enemy16 := _place(c16, "ADCR", "player2", 3, 3)
	var e16_before: int = enemy16.health
	sp16.abilities.run(TriggerV2.Type.ON_MOVE_BROADCAST, AbilityContextV2.new(c16, sp16, ally16, 0, {"mover": ally16}))
	t.ok(enemy16.health < e16_before, "SPO 我方移動打擊最遠敵方")

	for c in cores:
		if c.balance != null:
			c.balance.free()
