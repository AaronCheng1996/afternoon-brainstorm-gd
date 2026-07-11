# P1-4 驗收：White 全卡（翻譯自 Python tests/test_card_white.py）。
# 涵蓋 APW 麻痺、APTW 護盾、SPW 計分（numb / 非 numb）。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var core := GameCore.new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	core.setup(deck, deck, seed_v, db)
	return core


# 放一顆非暈眩、佔格的棋子（對齊 Python helpers.place_card + do_attack 清 numbness）。
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
	var cores: Array = []

	# --- TestWhiteAp：攻擊附帶麻痺 ---
	var cAp := _make_core(1); cores.append(cAp)
	var ap := _place(cAp, "APW", "player1", 0, 0)
	var ap_target := _place(cAp, "ADCW", "player2", 1, 0)
	ap_target.set_numb(false)
	CombatV2.attack(cAp, ap)
	t.ok(ap_target.is_numb(), "APW 攻擊後目標進入麻痺")

	# --- TestWhiteApt：最近友方 + 自己各得 self.damage 護盾 ---
	var cApt := _make_core(2); cores.append(cApt)
	var apt := _place(cApt, "APTW", "player1", 0, 0)
	var ally := _place(cApt, "ADCW", "player1", 0, 1)
	_place(cApt, "ADCW", "player2", 1, 0)   # 敵方目標（APTW nearest 攻擊對象）
	var before_apt: int = apt.armor
	var before_ally: int = ally.armor
	CombatV2.attack(cApt, apt)
	t.eq(apt.armor, before_apt + apt.damage, "APTW 攻擊後自身 +ATK 護盾")
	t.eq(ally.armor, before_ally + apt.damage, "APTW 攻擊後最近友方 +ATK 護盾")

	# --- TestWhiteSp：非 numbness 得 1+extra_score 分 ---
	var cSp1 := _make_core(3); cores.append(cSp1)
	var sp1 := _place(cSp1, "SPW", "player1", 0, 0)
	sp1.set_numb(false)
	cSp1.settle_piece(sp1)
	var expected: int = 1 + int(cSp1.balance.param("SPW", "extra_score", 0))
	t.eq(cSp1.stats.get_stat(SCORED, sp1.uid()), expected, "SPW 非麻痺 settle 得 1+extra_score 分")
	t.eq(expected, 2, "SPW extra_score=1 → 每次計 2 分")

	# --- TestWhiteSp：numbness 得 0 分 ---
	var cSp2 := _make_core(4); cores.append(cSp2)
	var sp2 := PieceState.make("SPW", "player1", 0, 0, cSp2.balance)   # 入場 numbness=True
	cSp2.player1.on_board.append(sp2)
	cSp2.board.set_occupied(Vector2i(0, 0), true)
	t.ok(sp2.is_numb(), "SPW 入場為麻痺")
	cSp2.settle_piece(sp2)
	t.eq(cSp2.stats.get_stat(SCORED, sp2.uid()), 0, "SPW 麻痺 settle 得 0 分")
	t.ok(not sp2.is_numb(), "SPW settle 後解除麻痺")

	for c in cores:
		if c.balance != null:
			c.balance.free()
