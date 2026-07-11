# P1-7 驗收：Green 全卡 + LuckEngine（翻譯自 Python tests/test_card_green.py，
# 追加：固定運氣值斷言好運/壞運分支與 AP/AP_target/TANK 旗標；LUCKYBLOCK 被殺回饋；LFG 斬殺追打；APTG 禁攻）。
# 好運/壞運分支以「擲值 1–100 ≤ 運氣」為判定：運氣=100 必好運（roll≤100 恆真）、運氣=0 必壞運。
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


func run(t: Object) -> void:
	var cores: Array = []
	var S_HF_LUCK := 5
	var S_ASS_LOSS := 5

	# ---------------- APG（Python TestGreenAp）----------------
	# 攻擊附帶麻痺目標。
	var c1 := _make_core(1); cores.append(c1)
	var ap1 := _place(c1, "APG", "player1", 0, 0)
	var tgt1 := _place(c1, "ADCR", "player2", 1, 0); tgt1.set_numb(false)
	Combat.attack(c1, ap1)
	t.ok(tgt1.is_numb(), "APG 攻擊後目標麻痺")

	# ---------------- HFG（Python TestGreenHf）----------------
	# 對 LUCKYBLOCK 使用能力 → 自方運氣 +luck_increase。
	var c2 := _make_core(2); cores.append(c2)
	var hf2 := _place(c2, "HFG", "player1", 0, 0)
	var lb2 := _place(c2, "LUCKYBLOCK", "neutral", 1, 0)
	var luck2_before: int = c2.players_luck["player1"]
	hf2.abilities.run(Trigger.Type.ON_ABILITY_HIT, AbilityContext.new(c2, hf2, lb2, 0, {}))
	t.eq(c2.players_luck["player1"], luck2_before + S_HF_LUCK, "HFG 對 LUCKYBLOCK 運氣 +5")

	# 對非 LUCKYBLOCK 使用能力 → 運氣不變。
	var c3 := _make_core(3); cores.append(c3)
	var hf3 := _place(c3, "HFG", "player1", 0, 0)
	var other3 := _place(c3, "ADCR", "player2", 1, 0)
	var luck3_before: int = c3.players_luck["player1"]
	hf3.abilities.run(Trigger.Type.ON_ABILITY_HIT, AbilityContext.new(c3, hf3, other3, 0, {}))
	t.eq(c3.players_luck["player1"], luck3_before, "HFG 對非 LUCKYBLOCK 運氣不變")

	# ---------------- ASSG（Python TestGreenAss）----------------
	# 斬殺後 自方 +5、敵方 -enemy_luck_loss。
	var c4 := _make_core(4); cores.append(c4)
	var ass4 := _place(c4, "ASSG", "player1", 1, 1)
	var enemy4 := _place(c4, "ADCR", "player2", 2, 0); enemy4.health = 1
	var own4_before: int = c4.players_luck["player1"]
	var opp4_before: int = c4.players_luck["player2"]
	Combat.attack(c4, ass4)
	t.eq(c4.players_luck["player1"], own4_before + 5, "ASSG 斬殺後自方運氣 +5")
	t.eq(c4.players_luck["player2"], opp4_before - S_ASS_LOSS, "ASSG 斬殺後敵方運氣 -5")

	# ---------------- APTG（Python TestGreenApt）----------------
	# 回合開始：小十字四空格各生成 LUCKYBLOCK。
	var c5 := _make_core(5); cores.append(c5)
	var apt5 := _place(c5, "APTG", "player1", 1, 1)
	var nb5_before: int = c5.neutral_pieces.size()
	apt5.abilities.run(Trigger.Type.ON_REFRESH, AbilityContext.new(c5, apt5, null, 0, {}))
	t.eq(c5.neutral_pieces.size(), nb5_before + 4, "APTG 回合開始生成 4 個 LUCKYBLOCK")

	# APTG 不能攻擊（attack 恆 False，不傷及敵方）。
	var c6 := _make_core(6); cores.append(c6)
	var apt6 := _place(c6, "APTG", "player1", 1, 1)
	var enemy6 := _place(c6, "ADCR", "player2", 0, 1)   # nearest 目標
	var e6_before: int = enemy6.health
	t.ok(not Combat.attack(c6, apt6), "APTG 攻擊回傳 False")
	t.eq(enemy6.health, e6_before, "APTG 禁攻：敵方未受傷")

	# ---------------- SPG（Python TestGreenSp）----------------
	# 佈署 → 運氣 +luck_increase。
	var c7 := _make_core(7); cores.append(c7)
	var sp7 := _place(c7, "SPG", "player1", 0, 0)
	var sp_inc: int = int(c7.balance.param("SPG", "luck_increase", 0))
	var luck7_before: int = c7.players_luck["player1"]
	sp7.abilities.run(Trigger.Type.ON_DEPLOY, AbilityContext.new(c7, sp7, null, 0, {}))
	t.eq(c7.players_luck["player1"], luck7_before + sp_inc, "SPG 佈署運氣 +luck_increase")

	# 佈署且運氣足夠 → 生成 1 個 LUCKYBLOCK（運氣 50 → +10 = 60 → (60-50)//10 = 1）。
	var c8 := _make_core(8); cores.append(c8)
	var sp8 := _place(c8, "SPG", "player1", 0, 0)
	c8.players_luck["player1"] = 50
	var nb8_before: int = c8.neutral_pieces.size()
	sp8.abilities.run(Trigger.Type.ON_DEPLOY, AbilityContext.new(c8, sp8, null, 0, {}))
	t.eq(c8.neutral_pieces.size(), nb8_before + 1, "SPG 運氣足夠生成 1 個 LUCKYBLOCK")

	# ---------------- lucky_effects 分支（固定運氣值）----------------
	# 好運分支：運氣 100 → roll 恆好運 → 運氣 +1。
	var c9 := _make_core(9); cores.append(c9)
	var p9 := _place(c9, "TANKW", "player1", 1, 1)
	c9.players_luck["player1"] = 100
	GreenCards.lucky_effects(c9, p9)
	t.eq(c9.players_luck["player1"], 101, "lucky_effects 好運分支：運氣 +1")

	# 壞運分支：運氣 0 → roll 恆壞運 → 運氣 -1。
	var c10 := _make_core(10); cores.append(c10)
	var p10 := _place(c10, "TANKW", "player1", 1, 1)
	c10.players_luck["player1"] = 0
	GreenCards.lucky_effects(c10, p10)
	t.eq(c10.players_luck["player1"], -1, "lucky_effects 壞運分支：運氣 -1")

	# ap_target=True：即便運氣 100 也必走壞運分支（運氣 -1，且 ap=False 照扣）。
	var c11 := _make_core(11); cores.append(c11)
	var p11 := _place(c11, "TANKW", "player1", 1, 1)
	c11.players_luck["player1"] = 100
	GreenCards.lucky_effects(c11, p11, false, true, false)
	t.eq(c11.players_luck["player1"], 99, "lucky_effects ap_target 必走壞運（運氣 -1）")

	# tank=True 且好運 roll：好運分支跳過，運氣不變。
	var c12 := _make_core(12); cores.append(c12)
	var p12 := _place(c12, "TANKW", "player1", 1, 1)
	c12.players_luck["player1"] = 100
	GreenCards.lucky_effects(c12, p12, false, false, true)
	t.eq(c12.players_luck["player1"], 100, "lucky_effects tank 好運分支跳過（運氣不變）")

	# ap=True 且壞運 roll：自己不受懲罰，運氣不變。
	var c13 := _make_core(13); cores.append(c13)
	var p13 := _place(c13, "TANKW", "player1", 1, 1)
	c13.players_luck["player1"] = 0
	GreenCards.lucky_effects(c13, p13, true, false, false)
	t.eq(c13.players_luck["player1"], 0, "lucky_effects ap 壞運不受罰（運氣不變）")

	# ---------------- LUCKYBLOCK 被殺回饋 ----------------
	# 攻擊者運氣 100 → 被殺觸發好運（攻擊者運氣 +1）；攻擊者方 APTG +1 護盾。
	var c14 := _make_core(14); cores.append(c14)
	var killer14 := _place(c14, "ADCW", "player1", 0, 0)
	var lb14 := _place(c14, "LUCKYBLOCK", "neutral", 1, 0); lb14.health = 1
	var apt14 := _place(c14, "APTG", "player1", 2, 2)
	c14.players_luck["player1"] = 100
	var apt14_arm_before: int = apt14.armor
	Combat.attack(c14, killer14)   # ADCW large_cross 命中並斬殺 (1,0) 的 LUCKYBLOCK
	t.ok(lb14.health <= 0, "LUCKYBLOCK 被斬殺")
	t.ok(c14.players_luck["player1"] > 100, "LUCKYBLOCK 被殺 → 攻擊者觸發好運（運氣增加）")
	t.eq(apt14.armor, apt14_arm_before + 1, "LUCKYBLOCK 被殺 → 攻擊者方 APTG +1 護盾")

	# ---------------- LFG 斬殺 LUCKYBLOCK 追打 ----------------
	# 斬殺 LUCKYBLOCK 後對最近敵方（玩家，非中立）造成自身 ATK 傷害。
	var c15 := _make_core(15); cores.append(c15)
	var lf15 := _place(c15, "LFG", "player1", 1, 1)
	var lb15 := _place(c15, "LUCKYBLOCK", "neutral", 0, 1); lb15.health = 1   # small_cross 內
	var far15 := _place(c15, "TANKW", "player2", 3, 3)                        # 遠處唯一玩家敵方
	c15.players_luck["player1"] = 0   # 令 LUCKYBLOCK 回饋走壞運（施於 LFG，不影響追打數值）
	var far15_before: int = far15.health
	Combat.attack(c15, lf15)
	t.ok(lb15.health <= 0, "LFG 斬殺 LUCKYBLOCK")
	t.eq(far15.health, far15_before - 3, "LFG 斬殺 LUCKYBLOCK 後對最近敵方造成 ATK(3) 傷害")

	for c in cores:
		if c.balance != null:
			c.balance.free()
