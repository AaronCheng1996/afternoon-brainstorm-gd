# P1-12 驗收：Brown 全卡 + 內建沉默（Python 無 brown 測試 → 自寫，涵蓋任務指定驗收項）。
# 棕色主題：高數值高代價的巨人；SPBR 攻擊後沉默我方其他 Brown 卡全部效果。
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


func _is_silenced(p: PieceState) -> bool:
	return p.abilities != null and p.abilities.silenced_tags.has(AbilityComponentV2.Tag.FACTION)


func run(t: Object) -> void:
	var cores: Array = []
	const FACTION := AbilityComponentV2.Tag.FACTION

	# ---------------- ADCBR：攻擊後自身麻痺 ----------------
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCBR", "player1", 0, 0)
	var e1 := _place(c1, "TANKW", "player2", 2, 0)   # ADC large_cross 同列
	var e1_hp: int = e1.health
	CombatV2.attack(c1, adc1)
	t.ok(adc1.is_numb(), "ADCBR 攻擊後自身麻痺")
	t.eq(e1.health, e1_hp - adc1.damage, "ADCBR 有正常造成傷害")

	# ADCBR 被沉默 → 攻擊正常但不自麻。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCBR", "player1", 0, 0)
	var e2 := _place(c2, "TANKW", "player2", 2, 0)
	adc2.abilities.silence_tag(FACTION)
	var e2_hp: int = e2.health
	CombatV2.attack(c2, adc2)
	t.ok(not adc2.is_numb(), "ADCBR 沉默後攻擊不自麻")
	t.eq(e2.health, e2_hp - adc2.damage, "ADCBR 沉默後仍正常攻擊")

	# ---------------- APBR：造成傷害後對手抽 1 ----------------
	var c3 := _make_core(3); cores.append(c3)
	var ap3 := _place(c3, "APBR", "player1", 0, 0)
	_place(c3, "TANKW", "player2", 1, 0)   # AP nearest
	var draw3_before: int = c3.card_to_draw["player2"]
	CombatV2.attack(c3, ap3)
	t.eq(c3.card_to_draw["player2"], draw3_before + 1, "APBR 造成傷害後對手 +1 抽")

	# ---------------- TANKBR：兩回合沒被打掉 8 血 ----------------
	var c4 := _make_core(4); cores.append(c4)
	var tank4 := _place(c4, "TANKBR", "player1", 0, 0)
	t.eq(tank4.health, 20, "TANKBR 初始 20 HP")
	c4.refresh_piece(tank4)
	t.eq(tank4.health, 16, "TANKBR 回合開始未被攻擊 → -4")
	c4.refresh_piece(tank4)
	t.eq(tank4.health, 12, "TANKBR 兩回合未被攻擊 → 共 -8")

	# 被攻擊過的回合不自傷。
	var c5 := _make_core(5); cores.append(c5)
	var tank5 := _place(c5, "TANKBR", "player1", 0, 0)
	var atk5 := _place(c5, "ADCW", "player2", 1, 0)
	tank5.abilities.run(TriggerV2.Type.ON_BEEN_ATTACKED, AbilityContextV2.new(c5, tank5, atk5, 1, {}))
	c5.refresh_piece(tank5)
	t.eq(tank5.health, 20, "TANKBR 上回合被攻擊過 → 回合開始不自傷")
	c5.refresh_piece(tank5)
	t.eq(tank5.health, 16, "TANKBR 旗標已清 → 下一回合恢復自傷")

	# ---------------- HFBR：一次攻擊耗 2 次數 ----------------
	var c6 := _make_core(6); cores.append(c6)
	c6.turn_number = 0   # 當前玩家 = player1
	var hf6 := _place(c6, "HFBR", "player1", 1, 1)
	t.eq(hf6.attack_uses, 2, "HFBR attack_uses 初始 = 2")
	_place(c6, "TANKW", "player2", 1, 2)   # HF small_cross 內
	c6.number_of_attacks["player1"] = 2
	var act6 := GameAction.new("attack", "player1")
	act6.board_x = 1
	act6.board_y = 1
	c6.dispatch(act6)
	t.eq(c6.number_of_attacks["player1"], 0, "HFBR 一次攻擊耗 2 攻擊次數")

	# HFBR 被沉默 → attack_uses 退回 1。
	var c7 := _make_core(7); cores.append(c7)
	var hf7 := _place(c7, "HFBR", "player1", 1, 1)
	_place(c7, "TANKW", "player2", 1, 2)
	hf7.abilities.silence_tag(FACTION)
	CombatV2.attack(c7, hf7)
	t.eq(hf7.attack_uses, 1, "HFBR 沉默後 attack_uses = 1")

	# ---------------- LFBR：斬殺後敵方得 2 分 ----------------
	var c8 := _make_core(8); cores.append(c8)
	var lf8 := _place(c8, "LFBR", "player1", 1, 1)
	var v8 := _place(c8, "TANKW", "player2", 1, 2); v8.health = 1   # LF small_cross
	t.eq(c8.score, 0, "LFBR：初始分數 0")
	CombatV2.attack(c8, lf8)
	t.eq(c8.score, 2, "LFBR 斬殺後對面（player2）得 2 分")

	# ---------------- ASSBR：斬殺後我方跳過下回合抽牌 ----------------
	var c9 := _make_core(9); cores.append(c9)
	var ass9 := _place(c9, "ASSBR", "player1", 1, 1)
	var v9 := _place(c9, "TANKW", "player2", 2, 2); v9.health = 1   # ASS small_x
	CombatV2.attack(c9, ass9)
	t.ok(c9.skip_turn_draw["player1"], "ASSBR 斬殺後我方跳過下回合抽牌")

	# ---------------- APTBR：佈署給敵護盾 + 攻擊增益最近友方 ----------------
	# 佈署：所有敵方 +2 護盾。
	var c10 := _make_core(10); cores.append(c10)
	var apt10 := _place(c10, "APTBR", "player1", 0, 0)
	var e10 := _place(c10, "TANKW", "player2", 2, 2)
	apt10.abilities.run(TriggerV2.Type.ON_DEPLOY, AbilityContextV2.new(c10, apt10, null, 0, {}))
	t.eq(e10.armor, 2, "APTBR 佈署 → 敵方棋子 +2 護盾")

	# 攻擊：最近非 Brown 友方 +1/+1。
	var c11 := _make_core(11); cores.append(c11)
	var apt11 := _place(c11, "APTBR", "player1", 0, 0)
	var ally11 := _place(c11, "ADCW", "player1", 1, 0)
	var ally11_atk: int = ally11.damage
	var ally11_arm: int = ally11.armor
	apt11.abilities.run(TriggerV2.Type.ON_ABILITY_HIT, AbilityContextV2.new(c11, apt11, null, 0, {}))
	t.eq(ally11.damage, ally11_atk + 1, "APTBR 攻擊 → 最近友方 +1 ATK")
	t.eq(ally11.armor, ally11_arm + 1, "APTBR 攻擊 → 最近友方 +1 護盾")

	# 攻擊：最近 Brown 巨人友方 +1/+1 再 +1/+1（共 +2/+2）。
	var c12 := _make_core(12); cores.append(c12)
	var apt12 := _place(c12, "APTBR", "player1", 0, 0)
	var ally12 := _place(c12, "ADCBR", "player1", 1, 0)
	var ally12_atk: int = ally12.damage
	apt12.abilities.run(TriggerV2.Type.ON_ABILITY_HIT, AbilityContextV2.new(c12, apt12, null, 0, {}))
	t.eq(ally12.damage, ally12_atk + 2, "APTBR 攻擊 → 最近 Brown 友方 +2 ATK（含巨人加成）")

	# ---------------- SPBR：攻擊後沉默我方其他 Brown；死亡後恢復 ----------------
	var c13 := _make_core(13); cores.append(c13)
	var sp13 := _place(c13, "SPBR", "player1", 0, 0)
	var adc13 := _place(c13, "ADCBR", "player1", 1, 1)
	_place(c13, "TANKW", "player2", 3, 3)   # SP farthest（供 SPBR 命中觸發）
	var adc13_e := _place(c13, "TANKW", "player2", 1, 3)   # ADCBR large_cross 同欄
	CombatV2.attack(c13, sp13)
	t.ok(sp13.is_angry(), "SPBR 攻擊後自身亮怒氣")
	t.ok(_is_silenced(adc13), "SPBR 攻擊後 → 我方其他 Brown 被沉默")

	# 驗收項：SPBR 攻擊後 ADCBR 攻擊不再自麻。
	CombatV2.attack(c13, adc13)
	t.ok(not adc13.is_numb(), "SPBR 沉默後 ADCBR 攻擊不再自麻")
	t.ok(adc13_e.health < adc13_e.max_health, "ADCBR 沉默後仍正常攻擊命中")

	# 驗收項：場上 SPBR 死亡後下回合恢復。
	c13.get_player("player1").on_board.erase(sp13)
	c13.refresh_piece(adc13)
	t.ok(not _is_silenced(adc13), "SPBR 死亡後回合開始 → 沉默解除")
	adc13.set_numb(false)
	CombatV2.attack(c13, adc13)
	t.ok(adc13.is_numb(), "恢復後 ADCBR 攻擊又會自麻")

	for c in cores:
		if c.balance != null:
			c.balance.free()
