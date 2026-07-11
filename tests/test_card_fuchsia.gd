# P1-11 驗收：Fuchsia 全卡（翻譯自 Python tests/test_card_fuchsia.py）。
# 紫紅主題：鏡像 Shadow——佈署在本體對稱位生成鏡像、本體與鏡像共同攻擊、
# 斬殺生成新鏡像（ASSF）、鏡像格傷害攔截（APTF）、給友方掛鏡像（SPF）。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
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


func _deploy(core: GameCore, p: PieceState) -> void:
	p.abilities.run(TriggerV2.Type.ON_DEPLOY, AbilityContextV2.new(core, p, null, 0, {}))


func run(t: Object) -> void:
	var cores: Array = []
	var SIZE := GameConfig.BOARD_SIZE

	# ---------------- ADCF ----------------
	# 佈署在對稱位生成鏡像。
	var c1 := _make_core(1); cores.append(c1)
	var adc1 := _place(c1, "ADCF", "player1", 0, 0)
	_deploy(c1, adc1)
	t.eq(adc1.shadows.size(), 1, "ADCF 佈署生成 1 個鏡像")
	t.eq(adc1.shadows[0].board_x, SIZE - 1 - 0, "ADCF 鏡像 x = 對稱位")
	t.eq(adc1.shadows[0].board_y, SIZE - 1 - 0, "ADCF 鏡像 y = 對稱位")

	# 攻擊時本體與鏡像都發動（雙倍傷害）。
	var c2 := _make_core(2); cores.append(c2)
	var adc2 := _place(c2, "ADCF", "player1", 0, 0)
	var enemy2 := _place(c2, "TANKR", "player2", 3, 0)   # 本體同列、鏡像(3,3)同行皆命中
	var before2: int = enemy2.health
	_deploy(c2, adc2)
	adc2.set_numb(false)
	CombatV2.attack(c2, adc2)
	t.eq(enemy2.health, before2 - adc2.damage * 2, "ADCF 本體+鏡像雙重命中 = ATK×2")

	# ---------------- APF ----------------
	# 攻擊附帶麻痺目標。
	var c3 := _make_core(3); cores.append(c3)
	var ap3 := _place(c3, "APF", "player1", 0, 0)
	var tgt3 := _place(c3, "ADCR", "player2", 1, 0); tgt3.set_numb(false)
	ap3.set_numb(false)
	CombatV2.attack(c3, ap3)
	t.ok(tgt3.is_numb(), "APF 攻擊後目標麻痺")

	# 光環：站在鏡像格上的敵人麻痺。
	var c3b := _make_core(31); cores.append(c3b)
	var ap3b := _place(c3b, "APF", "player1", 0, 0)
	_deploy(c3b, ap3b)                                     # 鏡像於 (3,3)
	var onshadow := _place(c3b, "ADCR", "player2", SIZE - 1, SIZE - 1); onshadow.set_numb(false)
	ap3b.abilities.run(TriggerV2.Type.ON_REFRESH, AbilityContextV2.new(c3b, ap3b, null, 0, {}))
	t.ok(onshadow.is_numb(), "APF 光環：站在鏡像格上的敵人麻痺")

	# ---------------- HFF ----------------
	# 攻擊時本體與鏡像都發動（九宮格，雙倍傷害）。
	var c4 := _make_core(4); cores.append(c4)
	var hf4 := _place(c4, "HFF", "player1", 1, 1)
	var enemy4 := _place(c4, "TANKR", "player2", 1, 2)     # 本體小十字、鏡像(2,2)小十字皆命中
	var before4: int = enemy4.health
	_deploy(c4, hf4)
	hf4.set_numb(false)
	CombatV2.attack(c4, hf4)
	t.eq(enemy4.health, before4 - hf4.damage * 2, "HFF 本體+鏡像雙重命中 = ATK×2")

	# ---------------- ASSF ----------------
	# 斬殺後在受害者位置生成鏡像。
	var c5 := _make_core(5); cores.append(c5)
	var ass5 := _place(c5, "ASSF", "player1", 1, 1)
	var enemy5 := _place(c5, "ADCR", "player2", 2, 0); enemy5.health = 1   # small_x 命中
	ass5.set_numb(false)
	CombatV2.attack(c5, ass5)
	t.eq(ass5.shadows.size(), 1, "ASSF 斬殺後生成 1 個鏡像")
	t.eq(ass5.shadows[0].board_x, 2, "ASSF 鏡像於受害者 x")
	t.eq(ass5.shadows[0].board_y, 0, "ASSF 鏡像於受害者 y")

	# 生成的鏡像可正常代打。
	var c6 := _make_core(6); cores.append(c6)
	var ass6 := _place(c6, "ASSF", "player1", 1, 1)
	var victim6 := _place(c6, "TANKR", "player2", 2, 2); victim6.health = 1
	ass6.set_numb(false)
	CombatV2.attack(c6, ass6)                              # 斬殺 (2,2) → 鏡像於 (2,2)
	var enemy6 := _place(c6, "TANKR", "player2", 3, 3)
	var before6: int = enemy6.health
	CombatV2.attack(c6, ass6)                              # 本體無目標 → 鏡像(2,2) small_x 打 (3,3)
	t.eq(enemy6.health, before6 - ass6.damage, "ASSF 鏡像代打命中新敵方")

	# 鏡像斬殺亦生成新鏡像（越殺越多）。
	var c7 := _make_core(7); cores.append(c7)
	var ass7 := _place(c7, "ASSF", "player1", 1, 1)
	var fv7 := _place(c7, "TANKR", "player2", 2, 2); fv7.health = 1
	ass7.set_numb(false)
	CombatV2.attack(c7, ass7)                              # 鏡像於 (2,2)
	var sv7 := _place(c7, "TANKR", "player2", 3, 3); sv7.health = 1
	CombatV2.attack(c7, ass7)                              # 鏡像(2,2)斬殺 (3,3) → 新鏡像 (3,3)
	t.eq(ass7.shadows.size(), 2, "ASSF 鏡像斬殺後鏡像數 = 2")
	var positions7: Array = []
	for s: PieceState in ass7.shadows:
		positions7.append(Vector2i(s.board_x, s.board_y))
	t.ok(positions7.has(Vector2i(3, 3)), "ASSF 新鏡像位於第二受害者位置")

	# ---------------- SPF ----------------
	# 佈署時最遠的我方紫紅卡（非 SPF）獲得不可移動鏡像。
	var c8 := _make_core(8); cores.append(c8)
	var sp8 := _place(c8, "SPF", "player1", 0, 0)
	var near8 := _place(c8, "ADCF", "player1", 1, 0)
	var far8 := _place(c8, "HFF", "player1", 3, 2)
	_deploy(c8, sp8)
	t.eq(far8.shadows.size(), 1, "SPF：最遠紫紅友方獲得鏡像")
	t.eq(near8.shadows.size(), 0, "SPF：較近友方不獲得鏡像")
	t.eq(far8.shadows[0].board_x, SIZE - 1, "SPF 鏡像 x = SPF 對稱位")
	t.eq(far8.shadows[0].board_y, SIZE - 1, "SPF 鏡像 y = SPF 對稱位")
	t.ok(not far8.shadows[0].movable, "SPF 鏡像不可移動")
	t.eq(far8.shadows[0].attack_types, far8.attack_types, "SPF 鏡像沿用友方攻擊模式")

	# ---------------- APTF ----------------
	# 佈署生鏡像。
	var c9 := _make_core(9); cores.append(c9)
	var apt9 := _place(c9, "APTF", "player1", 0, 0)
	_deploy(c9, apt9)
	t.eq(apt9.shadows.size(), 1, "APTF 佈署生成鏡像")

	# 鏡像承傷 → linker 獲 value//2 護盾。
	var c10 := _make_core(10); cores.append(c10)
	var apt10 := _place(c10, "APTF", "player1", 0, 0)
	_deploy(c10, apt10)
	var shadow10: PieceState = apt10.shadows[0]
	var atk10 := _place(c10, "ADCR", "player2", 1, 0)
	var before10: int = apt10.armor
	shadow10.abilities.any_true(TriggerV2.Type.BLOCK_DAMAGE, AbilityContextV2.new(c10, shadow10, atk10, 4, {}))
	t.eq(apt10.armor, before10 + 2, "APTF 鏡像承傷 4 → 本體 +2 護盾")

	# 場地攔截：我方棋子站在鏡像格上受傷 → APTF 獲得護盾。
	var c11 := _make_core(11); cores.append(c11)
	var apt11 := _place(c11, "APTF", "player1", 0, 0)
	_deploy(c11, apt11)
	var shadow11: PieceState = apt11.shadows[0]
	var ally11 := _place(c11, "ADCR", "player1", shadow11.board_x, shadow11.board_y)
	var atk11 := _place(c11, "ADCR", "player2", 1, 0)
	var before11: int = apt11.armor
	var mods: Array = apt11.abilities.collect_field(AbilityContextV2.new(c11, apt11, ally11, 10, {"attacker": atk11}))
	t.ok(mods.size() > 0, "APTF 場地攔截：鏡像覆蓋友方時回傳修改子")
	t.eq(apt11.armor, before11 + 5, "APTF 場地攔截：獲得減免量護盾（floor(10*0.5)=5）")

	# ---------------- 鏡像移動同步 ----------------
	# 本體移動後，可移動鏡像鏡射到本體新位置的對稱位。
	var c12 := _make_core(12); cores.append(c12)
	var adc12 := _place(c12, "ADCF", "player1", 0, 0)
	_deploy(c12, adc12)                                    # 鏡像於 (3,3)
	adc12.set_moving(true)
	c12._move_piece(adc12, 1, 0)                           # 移到 (1,0) → 鏡像應到 (2,3)
	t.eq(adc12.shadows[0].board_x, SIZE - 1 - 1, "ADCF 移動後鏡像 x 同步")
	t.eq(adc12.shadows[0].board_y, SIZE - 1 - 0, "ADCF 移動後鏡像 y 同步")

	for c: GameCore in cores:
		if c.balance != null:
			c.balance.free()
