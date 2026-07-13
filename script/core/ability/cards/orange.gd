# P1-8 Orange 全卡能力組裝（見 docs/rebuild/02 §Orange，Python 出處 cards/card_orange.py）。
# 橘色主題：機動——攻擊後獲得移動、移動後連鎖效果、MOVEO 臨時移動卡發放。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[Ability]）。
class_name OrangeCards
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[Ability]）。
static func registrations() -> Dictionary:
	return {
		"ADCO": Callable(OrangeCards, "adco"),
		"APO": Callable(OrangeCards, "apo"),
		"TANKO": Callable(OrangeCards, "tanko"),
		"HFO": Callable(OrangeCards, "hfo"),
		"LFO": Callable(OrangeCards, "lfo"),
		"ASSO": Callable(OrangeCards, "asso"),
		"APTO": Callable(OrangeCards, "apto"),
		"SPO": Callable(OrangeCards, "spo"),
	}


# ADCO：攻擊成功後獲得移動（moving）；移動後再發動一次攻擊（Python Adc.attack / after_movement）。
static func adco() -> Array:
	var passive: Array[int] = [AbilityComponent.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("orange_adc_attack_move", Trigger.Type.ATTACK_OVERRIDE, [AttackThenMoveEffect.new()], passive),
		Ability.new("orange_adc_move_attack", Trigger.Type.ON_AFTER_MOVEMENT, [AfterMoveAttackEffect.new()], trig),
	]


# APO：攻擊附帶麻痺目標；回合開始獲得一張 MOVEO（Python Ap.ability / on_refresh）。
static func apo() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("orange_ap_numb", Trigger.Type.ON_ABILITY_HIT, [ApNumbEffect.new()], trig),
		Ability.new("orange_ap_moveo", Trigger.Type.ON_REFRESH, [AddMoveoEffect.new()], trig),
	]


# TANKO：被攻擊後獲得一張 MOVEO（Python Tank.been_attacked）。
static func tanko() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("orange_tank_moveo", Trigger.Type.ON_BEEN_ATTACKED, [AddMoveoEffect.new()], trig)]


# HFO：攻擊後獲得移動；移動後 extra_damage +move_damage_gain 且進怒氣；
#   結算時清除 extra_damage 與怒氣（Python Hf.attack / after_movement / on_settle）。
#   damage_bonus 沿用 base（value + extra_damage），故無需額外 MOD（見 base.py Hf.damage_bonus == 預設）。
static func hfo() -> Array:
	var passive: Array[int] = [AbilityComponent.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	return [
		Ability.new("orange_hf_attack_move", Trigger.Type.ATTACK_OVERRIDE, [AttackThenMoveEffect.new()], passive),
		Ability.new("orange_hf_after_move", Trigger.Type.ON_AFTER_MOVEMENT, [HfAfterMoveEffect.new()], trig),
		Ability.new("orange_hf_settle", Trigger.Type.ON_SETTLE, [HfSettleEffect.new()], mod),
	]


# LFO：攻擊後獲得移動；移動後對最近敵方（僅對手棋子，不含中立）造成自身 ATK 傷害
#   （Python Lf.attack / after_movement）。
static func lfo() -> Array:
	var passive: Array[int] = [AbilityComponent.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("orange_lf_attack_move", Trigger.Type.ATTACK_OVERRIDE, [AttackThenMoveEffect.new()], passive),
		Ability.new("orange_lf_move_strike", Trigger.Type.ON_AFTER_MOVEMENT, [LfMoveStrikeEffect.new()], trig),
	]


# ASSO：移動後進怒氣；斬殺時獲得移動，若怒氣則攻擊次數 +attack_gain_per_kill 並清怒氣；
#   結算時清怒氣（Python Ass.after_movement / killed / on_settle）。
static func asso() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	return [
		Ability.new("orange_ass_after_move", Trigger.Type.ON_AFTER_MOVEMENT, [AssAfterMoveEffect.new()], trig),
		Ability.new("orange_ass_kill", Trigger.Type.ON_KILLED, [AssKilledEffect.new()], trig),
		Ability.new("orange_ass_settle", Trigger.Type.ON_SETTLE, [AssSettleEffect.new()], mod),
	]


# APTO：移動後 armor +move_armor_gain，並將 armor//2 轉為 damage（armor 取餘）；
#   任何我方棋子移動時（含自己）給該棋子與自身各 +move_armor_gain 護盾（Python Apt.after_movement / move_broadcast）。
static func apto() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("orange_apt_after_move", Trigger.Type.ON_AFTER_MOVEMENT, [AptAfterMoveEffect.new()], trig),
		Ability.new("orange_apt_move_armor", Trigger.Type.ON_MOVE_BROADCAST, [AptMoveBroadcastEffect.new()], trig),
	]


# SPO：任何我方棋子移動時（含自己），對最遠敵方（含中立）造成 move_strike_damage 傷害
#   （Python Sp.move_broadcast）。
static func spo() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("orange_sp_move_strike", Trigger.Type.ON_MOVE_BROADCAST, [SpMoveBroadcastEffect.new()], trig)]


# --- 效果 ---

# ADCO/HFO/LFO 共用：攻擊覆寫——照常攻擊，成功則獲得移動（moving）。
# ATTACK_OVERRIDE：回傳 bool＝攻擊是否成功（決定是否消耗攻擊次數，見 game_core._attack）。
# combat.attack 於本效果後統一 clear hit_cards（對齊 Python base.attack）。
class AttackThenMoveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var ok: bool = Combat.launch_attack(ctx.core, src, src.attack_types)
		if ok:
			src.set_moving(true)
		return ok


# ADCO：移動後再發動一次攻擊（完整 launch_attack，會 drain 追加攻擊佇列）。
class AfterMoveAttackEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		Combat.launch_attack(ctx.core, src, src.attack_types)
		return true


# APO：攻擊附帶麻痺目標。
class ApNumbEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		if ctx.target != null:
			ctx.target.set_numb(true)
		return true


# APO（on_refresh）/ TANKO（been_attacked）共用：給擁有者手牌一張 MOVEO（臨時移動卡）。
class AddMoveoEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.core.get_player(ctx.source.owner).hand.append("MOVEO")
		return true


# HFO：移動後 extra_damage +move_damage_gain 且進怒氣。
class HfAfterMoveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		src.extra_damage += int(ctx.core.balance.param(src.card_id, "move_damage_gain", 0))
		src.set_anger(true)
		return true


# HFO settle（Python Hf.on_settle，clear_numbness=True 語意）：清 extra_damage 與怒氣；
#   分數維持 base（0 if numb else 1，由 settle_piece 計算並傳入 ctx.value）。numbness 由 settle_piece 後清。
class HfSettleEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		src.extra_damage = 0
		src.set_anger(false)
		return ctx.value


# LFO：移動後對最近敵方（僅對手棋子，不含中立）造成自身 ATK 傷害（ability=True，同 Python 預設）。
class LfMoveStrikeEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var opp: String = core.opponent_name(src.owner)
		var pool: Array = core.get_player(opp).on_board.filter(
			func(c: PieceState) -> bool: return c != src)
		for target: PieceState in Combat.detection(core, src, "nearest", pool):
			Combat.damage_calculate(core, target, src.damage, src, true, 0.0)
		return true


# ASSO：移動後進怒氣。
class AssAfterMoveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.source.set_anger(true)
		return true


# ASSO：斬殺時獲得移動；若怒氣則攻擊次數 +attack_gain_per_kill 並清怒氣。
class AssKilledEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		src.set_moving(true)
		if src.is_angry():
			core.number_of_attacks[src.owner] += int(core.balance.param(src.card_id, "attack_gain_per_kill", 0))
			src.set_anger(false)
		return true


# ASSO settle（Python Ass.on_settle，clear_numbness=True 語意）：清怒氣；分數維持 base。
class AssSettleEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.source.set_anger(false)
		return ctx.value


# APTO：移動後 armor +move_armor_gain；armor//2 轉為 damage，armor 取餘。
class AptAfterMoveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		src.armor += int(ctx.core.balance.param(src.card_id, "move_armor_gain", 0))
		var value: int = src.armor / 2
		if value > 0:
			src.damage += value
			src.armor = src.armor % 2
		return true


# APTO：我方棋子移動時（含自己），給該棋子與自身各 +move_armor_gain 護盾。
# ON_MOVE_BROADCAST：ctx.source=APTO、ctx.target=移動者（mover）。
class AptMoveBroadcastEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var mover: PieceState = ctx.target
		if mover != null and mover.owner == src.owner and mover != src:
			var gain: int = int(ctx.core.balance.param(src.card_id, "move_armor_gain", 0))
			mover.armor += gain
			src.armor += gain
		return true


# SPO：我方棋子移動時（含自己），對最遠敵方（含中立）造成 move_strike_damage 傷害（ability=True）。
# ON_MOVE_BROADCAST：ctx.source=SPO、ctx.target=移動者（mover）。
class SpMoveBroadcastEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var mover: PieceState = ctx.target
		if mover != null and mover.owner == src.owner:
			var dmg: int = int(core.balance.param(src.card_id, "move_strike_damage", 0))
			for target: PieceState in Combat.detection(core, src, "farthest", core.get_enemies_of(src.owner)):
				Combat.damage_calculate(core, target, dmg, src, true, 0.0)
		return true
