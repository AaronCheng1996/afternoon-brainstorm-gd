# P1-13 Purple 全卡能力組裝（見 docs/rebuild/02 §Purple，Python 出處 cards/card_purple.py）。
# 紫色**僅實作 4 張**：AP/TANK/HF/ASS（ADC/LF/APT/SP 在 Python 未註冊、選秀不出現、balance 為 0）。
# 主題：控制——驅散、反制敵方移動、依敵數加攻擊次數、擊殺爆抽。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[Ability]）。
class_name PurpleCards
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[Ability]）。僅 4 張。
static func registrations() -> Dictionary:
	return {
		"APP": Callable(PurpleCards, "app"),
		"TANKP": Callable(PurpleCards, "tankp"),
		"HFP": Callable(PurpleCards, "hfp"),
		"ASSP": Callable(PurpleCards, "assp"),
	}


# APP：佈署驅散最近敵方（護盾歸 0、ATK 回原值）；攻擊附帶麻痺 + 驅散（Python Ap.deploy/ability）。
static func app() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("purple_ap_deploy", Trigger.Type.ON_DEPLOY, [ApDeployEffect.new()], tags),
		Ability.new("purple_ap_dispel", Trigger.Type.ON_ABILITY_HIT, [ApDispelEffect.new()], tags),
	]


# TANKP：敵方棋子移動後 → 對其造成 move_strike_damage（Python Tank.move_broadcast）。
static func tankp() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("purple_tank_counter_move", Trigger.Type.ON_MOVE_BROADCAST, [TankCounterMoveEffect.new()], tags)]


# HFP：回合開始，攻擊範圍內每 3 個敵人 → 攻擊次數 +1（Python Hf.on_refresh）。
static func hfp() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("purple_hf_attacks", Trigger.Type.ON_REFRESH, [HfAttacksEffect.new()], tags)]


# ASSP：斬殺後抽（敵方場上數 − 我方場上數 − unit_gap）張，上限 maximum_card_draw_from_killed（Python Ass.killed）。
static func assp() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("purple_ass_draw", Trigger.Type.ON_KILLED, [AssDrawEffect.new()], tags)]


# --- 效果 ---

# APP 佈署：對最近敵方（對手場上、health>0）驅散——armor 歸 0、damage 回 original_damage。
class ApDeployEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var enemies: Array = core.get_player(core.opponent_name(src.owner)).on_board.filter(
			func(c: PieceState) -> bool: return c.health > 0)
		for target: PieceState in Combat.detection(core, src, "nearest", enemies):
			target.armor = 0
			target.damage = target.original_damage
		return null


# APP 攻擊附帶：對命中目標麻痺 + 驅散（armor 歸 0、damage 回 original_damage）。
class ApDispelEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var target: PieceState = ctx.target
		if target == null:
			return true
		target.set_numb(true)
		target.armor = 0
		target.damage = target.original_damage
		return true


# TANKP：移動者為敵方 → 對其造成 move_strike_damage（ctx.target = mover）。
class TankCounterMoveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var mover: PieceState = ctx.target
		if mover != null and mover.owner != src.owner:
			var dmg: int = int(core.balance.param(src.card_id, "move_strike_damage", 0))
			Combat.damage_calculate(core, mover, dmg, src, true, 0.0)
			src.hit_cards.clear()
		return null


# HFP：回合開始，攻擊範圍內敵方數 // 3 加到攻擊次數（範圍＝自身 attack_types，對象＝對手場上棋子）。
class HfAttacksEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		if src.attack_types == "":
			return null
		var enemies: Array = core.get_player(core.opponent_name(src.owner)).on_board
		var count: int = Combat.detection(core, src, src.attack_types, enemies).size()
		core.number_of_attacks[src.owner] += count / 3
		return null


# ASSP：斬殺後抽（敵方數 − 我方數 − unit_gap）張，上限 max（count<=0 不抽；killed 早於回收，被殺者仍計入敵方數）。
class AssDrawEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var victim: PieceState = ctx.target
		if victim == null:
			return true
		var gap: int = int(core.balance.param(src.card_id, "unit_gap", 0))
		var cap: int = int(core.balance.param(src.card_id, "maximum_card_draw_from_killed", 0))
		var enemy_count: int = core.get_player(victim.owner).on_board.size()
		var my_count: int = core.get_player(src.owner).on_board.size()
		var count: int = mini(enemy_count - my_count - gap, cap)
		if count > 0:
			core.card_to_draw[src.owner] += count
		return true
