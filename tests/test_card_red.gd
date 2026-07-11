# P1-5 驗收：Red 全卡（翻譯自 Python tests/test_card_red.py）。
# 涵蓋 ADCR/APR/TANKR/HFR/LFR/ASSR/APTR 的滾雪球增益與 SPR 鏡射，
# 外加任務指定的 HFR 怒氣不死身、0 分結算、治療救回 0HP 怒氣者。
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


func run(t: Object) -> void:
	const SCORED := Statistics.StatType.SCORED
	const ADC_INC := 1     # Red ADC damage_increase
	const AP_STEAL := 2    # Red AP：目標 ADCR damage 2 × 100% = 2
	const TANK_ARM := 2    # Red TANK armor_increase
	const HF_DEC := 1      # Red HF health_decrease
	const HF_INC := 1      # Red HF damage_increase
	const LF_ARM := 1
	const LF_DMG := 1
	const ASS_INC := 2
	const APT_ARM := 1
	const APT_DMG := 1
	var cores: Array = []

	# ---------------- ADCR ----------------
	# 造成傷害後自身 ATK+1。
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCR", "player1", 0, 0)
	_place(c1, "TANKR", "player2", 2, 0)
	var adc1_before: int = adc1.damage
	Combat.attack(c1, adc1)
	t.eq(adc1.damage, adc1_before + ADC_INC, "ADCR 造成傷害後自身 ATK+1")

	# 我方 SPR 同步 +1。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCR", "player1", 0, 0)
	var sp2 := _place(c2, "SPR", "player1", 0, 1)
	_place(c2, "TANKR", "player2", 2, 0)
	var sp2_before: int = sp2.damage
	Combat.attack(c2, adc2)
	t.eq(sp2.damage, sp2_before + ADC_INC, "ADCR 攻擊後我方 SPR ATK+1")

	# 敵方 SPR 不受益。
	var c3 := _make_core(3); cores.append(c3)
	var adc3 := _place(c3, "ADCR", "player1", 0, 0)
	var esp3 := _place(c3, "SPR", "player2", 3, 0)
	_place(c3, "TANKR", "player2", 2, 0)
	var esp3_before: int = esp3.damage
	Combat.attack(c3, adc3)
	t.eq(esp3.damage, esp3_before, "ADCR 不增益敵方 SPR")

	# 無目標時不攻擊、ATK 不變。
	var c4 := _make_core(4); cores.append(c4)
	var adc4 := _place(c4, "ADCR", "player1", 0, 0)
	var adc4_before: int = adc4.damage
	var r4: bool = Combat.attack(c4, adc4)
	t.ok(not r4, "ADCR 無目標攻擊回傳 false")
	t.eq(adc4.damage, adc4_before, "ADCR 無目標時 ATK 不變")

	# ---------------- APR ----------------
	# 目標麻痺 + 偷取 100% ATK。
	var c5 := _make_core(5); cores.append(c5)
	var ap5 := _place(c5, "APR", "player1", 0, 0)
	var tgt5 := _place(c5, "ADCR", "player2", 1, 0)
	tgt5.set_numb(false)
	var ap5_before: int = ap5.damage
	var tgt5_before: int = tgt5.damage
	Combat.attack(c5, ap5)
	t.ok(tgt5.is_numb(), "APR 攻擊後目標麻痺")
	t.eq(ap5.damage, ap5_before + AP_STEAL, "APR 偷取後自身 +偷取值")
	t.eq(tgt5.damage, tgt5_before - AP_STEAL, "APR 偷取後目標 -偷取值")

	# 我方 SPR 承接偷取值。
	var c6 := _make_core(6); cores.append(c6)
	var ap6 := _place(c6, "APR", "player1", 0, 0)
	var sp6 := _place(c6, "SPR", "player1", 0, 1)
	_place(c6, "ADCR", "player2", 1, 0)
	var sp6_before: int = sp6.damage
	Combat.attack(c6, ap6)
	t.eq(sp6.damage, sp6_before + AP_STEAL, "APR 我方 SPR 承接偷取值")

	# ---------------- TANKR ----------------
	# 被攻擊後最近友方 +2 護盾。
	var c7 := _make_core(7); cores.append(c7)
	var tank7 := _place(c7, "TANKR", "player1", 1, 1)
	var ally7 := _place(c7, "ADCR", "player1", 1, 2)
	var enemy7 := _place(c7, "ADCR", "player2", 2, 1)
	var ally7_before: int = ally7.armor
	Combat.damage_calculate(c7, tank7, 1, enemy7, false, 0.0)
	t.eq(ally7.armor, ally7_before + TANK_ARM, "TANKR 被攻擊後最近友方 +2 護盾")

	# 被攻擊後我方 SPR +2 護盾。
	var c8 := _make_core(8); cores.append(c8)
	var tank8 := _place(c8, "TANKR", "player1", 1, 1)
	_place(c8, "ADCR", "player1", 1, 2)
	var sp8 := _place(c8, "SPR", "player1", 3, 3)
	var enemy8 := _place(c8, "ADCR", "player2", 2, 1)
	var sp8_before: int = sp8.armor
	Combat.damage_calculate(c8, tank8, 1, enemy8, false, 0.0)
	t.eq(sp8.armor, sp8_before + TANK_ARM, "TANKR 被攻擊後我方 SPR +2 護盾")

	# 無友方時 TANKR 自身不獲護盾。
	var c9 := _make_core(9); cores.append(c9)
	var tank9 := _place(c9, "TANKR", "player1", 0, 0)
	var enemy9 := _place(c9, "ADCR", "player2", 1, 0)
	var tank9_before: int = tank9.armor
	Combat.damage_calculate(c9, tank9, 1, enemy9, false, 0.0)
	t.eq(tank9.armor, tank9_before, "TANKR 無友方時自身不獲護盾")

	# ---------------- HFR ----------------
	# 造成傷害後自損 1HP、ATK+1。
	var c10 := _make_core(10); cores.append(c10)
	var hf10 := _place(c10, "HFR", "player1", 1, 1)
	_place(c10, "ADCR", "player2", 2, 1)
	var hf10_hp: int = hf10.health
	var hf10_dmg: int = hf10.damage
	Combat.attack(c10, hf10)
	t.eq(hf10.health, hf10_hp - HF_DEC, "HFR 攻擊後自損 1HP")
	t.eq(hf10.damage, hf10_dmg + HF_INC, "HFR 攻擊後 ATK+1")

	# HP 歸 0 → 進怒氣。
	var c11 := _make_core(11); cores.append(c11)
	var hf11 := _place(c11, "HFR", "player1", 1, 1)
	_place(c11, "ADCR", "player2", 2, 1)
	hf11.health = 1
	Combat.attack(c11, hf11)
	t.ok(hf11.is_angry(), "HFR HP 歸 0 進怒氣")

	# 怒氣不死身（can_be_killed false）。
	var c12 := _make_core(12); cores.append(c12)
	var hf12 := _place(c12, "HFR", "player1", 0, 0)
	hf12.set_anger(true)
	t.ok(not c12.can_be_killed(hf12), "HFR 怒氣時不可被擊殺")

	# HP 未歸 0 不進怒氣。
	var c13 := _make_core(13); cores.append(c13)
	var hf13 := _place(c13, "HFR", "player1", 1, 1)
	_place(c13, "ADCR", "player2", 2, 1)
	hf13.health = 5
	Combat.attack(c13, hf13)
	t.ok(not hf13.is_angry(), "HFR HP 未歸 0 不進怒氣")

	# 怒氣 settle 得 0 分且清怒氣。
	var c14 := _make_core(14); cores.append(c14)
	var hf14 := _place(c14, "HFR", "player1", 0, 0)
	hf14.set_anger(true)
	c14.settle_piece(hf14)
	t.eq(c14.stats.get_stat(SCORED, hf14.uid()), 0, "HFR 怒氣 settle 得 0 分")
	t.ok(not hf14.is_angry(), "HFR settle 後清怒氣")

	# 治療救回 0HP 怒氣者：治療後 HP 回升、回收仍存活。
	var c15 := _make_core(15); cores.append(c15)
	var hf15 := _place(c15, "HFR", "player1", 0, 0)
	hf15.health = 0
	hf15.set_anger(true)
	c15._heal_piece(hf15, GameConfig.HEAL_AMOUNT)
	t.eq(hf15.health, GameConfig.HEAL_AMOUNT, "HFR 0HP 怒氣者治療後 HP 回升")
	t.ok(c15.player1.on_board.has(hf15), "HFR 治療後回收仍存活")
	c15.logic_step()
	t.ok(c15.player1.on_board.has(hf15), "HFR 治療後 logic_step 仍存活")

	# ---------------- LFR ----------------
	# 自身 +1 護盾 +1 ATK。
	var c16 := _make_core(16); cores.append(c16)
	var lf16 := _place(c16, "LFR", "player1", 1, 1)
	_place(c16, "ADCR", "player2", 2, 1)
	var lf16_arm: int = lf16.armor
	var lf16_dmg: int = lf16.damage
	Combat.attack(c16, lf16)
	t.eq(lf16.armor, lf16_arm + LF_ARM, "LFR 攻擊後自身 +1 護盾")
	t.eq(lf16.damage, lf16_dmg + LF_DMG, "LFR 攻擊後自身 +1 ATK")

	# 我方 SPR 同步。
	var c17 := _make_core(17); cores.append(c17)
	var lf17 := _place(c17, "LFR", "player1", 1, 1)
	var sp17 := _place(c17, "SPR", "player1", 0, 0)
	_place(c17, "ADCR", "player2", 2, 1)
	var sp17_arm: int = sp17.armor
	var sp17_dmg: int = sp17.damage
	Combat.attack(c17, lf17)
	t.eq(sp17.armor, sp17_arm + LF_ARM, "LFR 攻擊後我方 SPR +1 護盾")
	t.eq(sp17.damage, sp17_dmg + LF_DMG, "LFR 攻擊後我方 SPR +1 ATK")

	# ---------------- ASSR ----------------
	# 斬殺後最近友方 ATK+2。
	var c18 := _make_core(18); cores.append(c18)
	var ass18 := _place(c18, "ASSR", "player1", 1, 1)
	var ally18 := _place(c18, "ADCR", "player1", 1, 2)
	var enemy18 := _place(c18, "ADCR", "player2", 2, 0)
	enemy18.health = 1
	var ally18_before: int = ally18.damage
	Combat.attack(c18, ass18)
	t.eq(ally18.damage, ally18_before + ASS_INC, "ASSR 斬殺後最近友方 ATK+2")

	# 斬殺後我方 SPR +2。
	var c19 := _make_core(19); cores.append(c19)
	var ass19 := _place(c19, "ASSR", "player1", 1, 1)
	_place(c19, "ADCR", "player1", 1, 2)
	var sp19 := _place(c19, "SPR", "player1", 3, 3)
	var enemy19 := _place(c19, "ADCR", "player2", 2, 0)
	enemy19.health = 1
	var sp19_before: int = sp19.damage
	Combat.attack(c19, ass19)
	t.eq(sp19.damage, sp19_before + ASS_INC, "ASSR 斬殺後我方 SPR ATK+2")

	# 未斬殺不增益。
	var c20 := _make_core(20); cores.append(c20)
	var ass20 := _place(c20, "ASSR", "player1", 1, 1)
	var ally20 := _place(c20, "ADCR", "player1", 1, 2)
	_place(c20, "TANKR", "player2", 2, 0)   # 9HP 不會被斬
	var ally20_before: int = ally20.damage
	Combat.attack(c20, ass20)
	t.eq(ally20.damage, ally20_before, "ASSR 未斬殺不增益友方")

	# ---------------- APTR ----------------
	# 自身 +1 護盾 +1 ATK。
	var c21 := _make_core(21); cores.append(c21)
	var apt21 := _place(c21, "APTR", "player1", 0, 0)
	_place(c21, "TANKR", "player2", 1, 0)
	var apt21_arm: int = apt21.armor
	var apt21_dmg: int = apt21.damage
	Combat.attack(c21, apt21)
	t.eq(apt21.armor, apt21_arm + APT_ARM, "APTR 攻擊後自身 +1 護盾")
	t.eq(apt21.damage, apt21_dmg + APT_DMG, "APTR 攻擊後自身 +1 ATK")

	# 最近友方 +1/+1。
	var c22 := _make_core(22); cores.append(c22)
	var apt22 := _place(c22, "APTR", "player1", 0, 0)
	var ally22 := _place(c22, "ADCR", "player1", 0, 1)
	_place(c22, "TANKR", "player2", 1, 0)
	var ally22_arm: int = ally22.armor
	var ally22_dmg: int = ally22.damage
	Combat.attack(c22, apt22)
	t.eq(ally22.armor, ally22_arm + APT_ARM, "APTR 攻擊後最近友方 +1 護盾")
	t.eq(ally22.damage, ally22_dmg + APT_DMG, "APTR 攻擊後最近友方 +1 ATK")

	# 我方 SPR +1/+1。
	var c23 := _make_core(23); cores.append(c23)
	var apt23 := _place(c23, "APTR", "player1", 0, 0)
	_place(c23, "ADCR", "player1", 0, 1)
	var sp23 := _place(c23, "SPR", "player1", 3, 3)
	_place(c23, "TANKR", "player2", 1, 0)
	var sp23_arm: int = sp23.armor
	var sp23_dmg: int = sp23.damage
	Combat.attack(c23, apt23)
	t.eq(sp23.armor, sp23_arm + APT_ARM, "APTR 攻擊後我方 SPR +1 護盾")
	t.eq(sp23.damage, sp23_dmg + APT_DMG, "APTR 攻擊後我方 SPR +1 ATK")

	for c in cores:
		if c.balance != null:
			c.balance.free()
