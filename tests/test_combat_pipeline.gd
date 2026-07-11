# P1-3 驗收：傷害管線 + 攻擊佇列（見 docs/rebuild/06 P1-3、01 §5–§7）。
extends RefCounted


func _make_core(p1_deck: Array, p2_deck: Array, seed_v: int) -> GameCore:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var core := GameCore.new()
	core.setup(p1_deck, p2_deck, seed_v, db)
	return core


func _deck(card_id: String, n: int) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


func _act(type: String, who: String, x: int = -1, y: int = -1, idx: int = -1) -> GameAction:
	var a := GameAction.new(type, who)
	a.board_x = x
	a.board_y = y
	a.hand_index = idx
	return a


# 放一顆棋子在場上（非暈眩、佔格），可即參與戰鬥。
func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	p.set_numb(false)
	p.extra_damage = 0
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func _find_event(core: GameCore, kind: int) -> GameEventV2:
	for e: GameEventV2 in core.event_sink:
		if e.kind == kind:
			return e
	return null


func run(t: Object) -> void:
	var deck12: Array = _deck("ADCW", 12)
	var cores: Array = []
	const DEALT := Statistics.StatType.DAMAGE_DEALT
	const TAKEN := Statistics.StatType.DAMAGE_TAKEN
	const TCOUNT := Statistics.StatType.DAMAGE_TAKEN_COUNT
	const HIT := Statistics.StatType.HIT
	const KILLED := Statistics.StatType.KILLED
	const DEATH := Statistics.StatType.DEATH

	# --- 1. 護盾恰好抵銷（armor >= value）---
	var cA := _make_core(deck12, deck12, 1); cores.append(cA)
	var atkA := _place(cA, "ADCW", "player1", 0, 0); atkA.damage = 3
	var vicA := _place(cA, "TANKW", "player2", 1, 0)
	vicA.health = 10; vicA.max_health = 10; vicA.armor = 5
	CombatV2.damage_calculate(cA, vicA, 3, atkA, false, 0.0)
	t.eq(vicA.armor, 2, "護盾抵銷：armor 5-3=2")
	t.eq(vicA.health, 10, "護盾抵銷：本體無傷")
	t.eq(cA.stats.get_stat(DEALT, atkA.uid()), 3, "護盾抵銷：DAMAGE_DEALT=3")
	t.eq(cA.stats.get_stat(TAKEN, vicA.uid()), 3, "護盾抵銷：DAMAGE_TAKEN=3")
	t.eq(cA.stats.get_stat(TCOUNT, vicA.uid()), 1, "護盾抵銷：DAMAGE_TAKEN_COUNT=1")

	# --- 2. 護盾溢出（0<armor<value，非致死）---
	var cB := _make_core(deck12, deck12, 2); cores.append(cB)
	var atkB := _place(cB, "ADCW", "player1", 0, 0); atkB.damage = 5
	var vicB := _place(cB, "TANKW", "player2", 1, 0)
	vicB.health = 10; vicB.max_health = 10; vicB.armor = 2
	CombatV2.damage_calculate(cB, vicB, 5, atkB, false, 0.0)
	t.eq(vicB.armor, 0, "溢出：護盾清空")
	t.eq(vicB.health, 7, "溢出：溢出 3 打血 10→7")
	t.eq(cB.stats.get_stat(DEALT, atkB.uid()), 5, "溢出：DAMAGE_DEALT 記全額 5")
	t.eq(cB.stats.get_stat(TAKEN, vicB.uid()), 5, "溢出：DAMAGE_TAKEN=5")

	# --- 3. 無盾且致死（armor==0，value 超過 health 記實際扣血）---
	var cC := _make_core(deck12, deck12, 3); cores.append(cC)
	var atkC := _place(cC, "ADCW", "player1", 0, 0); atkC.damage = 10
	var vicC := _place(cC, "TANKW", "player2", 1, 0)
	vicC.health = 4; vicC.max_health = 4; vicC.armor = 0
	CombatV2.damage_calculate(cC, vicC, 10, atkC, false, 1.5)
	t.eq(vicC.health, 0, "無盾致死：health→0")
	t.eq(cC.stats.get_stat(DEALT, atkC.uid()), 4, "無盾致死：DAMAGE_DEALT 記實際 4（非 10）")
	t.eq(cC.stats.get_stat(KILLED, atkC.uid()), 1, "無盾致死：KILLED+1")
	t.eq(cC.stats.get_stat(DEATH, vicC.uid()), 1, "無盾致死：DEATH+1")
	t.ok(vicC.pending_death, "致死：標記 pending_death")
	var deC := _find_event(cC, GameEventV2.Kind.DEATH)
	t.ok(deC != null, "致死：產生 death 事件")
	t.eq(deC.data["delay"], 1.5, "death 事件 delay = anim_delay(1.5)")

	# --- 4. 擊殺鉤子順序 killed → been_killed ---
	var cK := _make_core(deck12, deck12, 4); cores.append(cK)
	var atkK := _place(cK, "ADCW", "player1", 0, 0); atkK.damage = 10
	var vicK := _place(cK, "TANKW", "player2", 1, 0)
	vicK.health = 4; vicK.max_health = 4; vicK.armor = 0
	var order_log: Array = []
	var tags1: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	atkK.abilities.grant(AbilityV2.new("k_killed", TriggerV2.Type.ON_KILLED,
		[RecordEffect.new(order_log, "killed")], tags1))
	vicK.abilities.grant(AbilityV2.new("k_bk", TriggerV2.Type.ON_BEEN_KILLED,
		[RecordEffect.new(order_log, "been_killed")], tags1))
	CombatV2.damage_calculate(cK, vicK, 10, atkK, false, 0.0)
	t.eq(order_log, ["killed", "been_killed"], "擊殺鉤子順序：killed 先於 been_killed")

	# --- 5. 攻擊 numbness 者無效且不耗次數、不記 HIT ---
	var cN := _make_core(deck12, deck12, 5); cores.append(cN)
	var atkN := PieceState.make("ADCW", "player1", 0, 0, cN.balance)  # 入場 numbness=True
	cN.player1.on_board.append(atkN)
	cN.board.set_occupied(Vector2i(0, 0), true)
	var vicN := _place(cN, "TANKW", "player2", 0, 1)  # 同列，large_cross 可及
	vicN.health = 10; vicN.max_health = 10
	cN.number_of_attacks["player1"] = 1
	cN.dispatch(_act("attack", "player1", 0, 0))
	t.eq(cN.number_of_attacks["player1"], 1, "numb 攻擊不消耗攻擊次數")
	t.eq(vicN.health, 10, "numb 攻擊不造成傷害")
	t.eq(cN.stats.get_stat(HIT, atkN.uid()), 0, "numb 攻擊不記 HIT")

	# --- 6. 追加攻擊經佇列不遞迴 ---
	var cQ := _make_core(deck12, deck12, 6); cores.append(cQ)
	var A := _place(cQ, "ADCW", "player1", 0, 0); A.damage = 3
	var V := _place(cQ, "TANKW", "player2", 1, 1)
	V.health = 20; V.max_health = 20; V.armor = 0
	var B := _place(cQ, "ADCW", "player1", 3, 3); B.damage = 5
	var box: Dictionary = {"n": 0, "draining": false}
	var eff := EnqueueFollowupEffect.new()
	eff.follower = B; eff.victim = V; eff.box = box
	var tags2: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	A.abilities.grant(AbilityV2.new("q_follow", TriggerV2.Type.ON_AFTER_DAMAGE, [eff], tags2))
	# A 直接對 V 打（custom target 繞過 detection）；ignore_numbness 已非暈眩但明示。
	CombatV2.launch_attack(cQ, A, A.attack_types, [V], true, true)
	A.hit_cards.clear()
	t.eq(V.health, 12, "佇列 drain：A(3)+B(5)=8 傷害，20→12")
	t.eq(box["n"], 1, "追加攻擊只入列一次（不同步遞迴）")
	t.ok(box["draining"], "enqueue 發生於 draining 期間（佇列而非遞迴）")
	t.ok(cQ.pending_attacks.is_empty(), "佇列已排空")
	t.ok(not cQ._attack_draining, "draining 旗標已復位")

	for c in cores:
		if c.balance != null:
			c.balance.free()


# --- 測試用假效果 ---

# 記錄觸發順序。
class RecordEffect extends AbilityEffectV2:
	var log: Array
	var tag: String
	func _init(l: Array, tg: String) -> void:
		log = l
		tag = tg
	func execute(ctx: AbilityContextV2) -> Variant:
		log.append(tag)
		return null


# 於傷害後把「另一隻棋子攻擊 victim」排入佇列（只入列一次，並記錄當下 draining 狀態）。
class EnqueueFollowupEffect extends AbilityEffectV2:
	var follower: PieceState
	var victim: PieceState
	var box: Dictionary
	func execute(ctx: AbilityContextV2) -> Variant:
		if int(box.get("n", 0)) == 0:
			box["n"] = 1
			box["draining"] = ctx.core._attack_draining
			CombatV2.enqueue_attack(ctx.core, follower, null, [victim], true, false)
		return null
