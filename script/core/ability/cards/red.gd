# P1-5 Red 全卡能力組裝（見 docs/rebuild/02 §Red，Python 出處 cards/card_red.py）。
# 紅色主題：攻擊力滾雪球；**所有紅色增益同時鏡射到我方場上每張 SPR**。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[Ability]）。
class_name RedCards
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[Ability]）。
static func registrations() -> Dictionary:
	return {
		"ADCR": Callable(RedCards, "adcr"),
		"APR": Callable(RedCards, "apr"),
		"TANKR": Callable(RedCards, "tankr"),
		"HFR": Callable(RedCards, "hfr"),
		"LFR": Callable(RedCards, "lfr"),
		"ASSR": Callable(RedCards, "assr"),
		"APTR": Callable(RedCards, "aptr"),
		"SPR": Callable(RedCards, "spr"),
	}


# ADCR：造成傷害後 自身 ATK+1；同步鏡射到我方每張 SPR（Python Adc.ability）。
static func adcr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("red_adc_grow", Trigger.Type.ON_ABILITY_HIT, [AdcGrowEffect.new()], tags)]


# APR：攻擊附帶麻痺 + 偷取目標 100% ATK（自身與 SPR +偷取值，目標 ATK 歸 0）（Python Ap.ability）。
static func apr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("red_ap_steal", Trigger.Type.ON_ABILITY_HIT, [ApStealEffect.new()], tags)]


# TANKR：被攻擊後 最近友方（不含自己）+2 護盾；SPR +2 護盾（Python Tank.been_attacked）。
static func tankr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("red_tank_armor", Trigger.Type.ON_BEEN_ATTACKED, [TankArmorEffect.new()], tags)]


# HFR：造成傷害後 自損 1HP + ATK+1（SPR +1）；HP 歸 0 → 進怒氣（不死身 + settle 得 0 清怒氣）。
static func hfr() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	return [
		Ability.new("red_hf_grow", Trigger.Type.ON_ABILITY_HIT, [HfGrowEffect.new()], trig),
		Ability.new("red_hf_immortal", Trigger.Type.CAN_BE_KILLED, [HfImmortalEffect.new()], mod),
		Ability.new("red_hf_settle", Trigger.Type.ON_SETTLE, [HfSettleEffect.new()], mod),
	]


# LFR：造成傷害後 自身 +1 護盾 +1 ATK；SPR 同步（Python Lf.ability）。
static func lfr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("red_lf_grow", Trigger.Type.ON_ABILITY_HIT, [LfGrowEffect.new()], tags)]


# ASSR：斬殺後 最近友方 ATK+2；SPR +2（Python Ass.killed）。
static func assr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("red_ass_kill_buff", Trigger.Type.ON_KILLED, [AssKillBuffEffect.new()], tags)]


# APTR：攻擊時 最近友方 +1/+1，自己 +1/+1，SPR +1/+1（護盾/ATK）（Python Apt.ability）。
static func aptr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("red_apt_buff", Trigger.Type.ON_ABILITY_HIT, [AptBuffEffect.new()], tags)]


# SPR：無主動能力；承接全部紅色系增益。
static func spr() -> Array: return []


# --- 共用輔助 ---

# 我方場上所有 SPR（承接增益的鏡射目標）。
static func _allied_sprs(core: GameCore, owner: String) -> Array:
	return core.get_player(owner).on_board.filter(
		func(c: PieceState) -> bool: return c.card_id == "SPR")


# 最近的我方友方（排除自己）；無則空陣列。
static func _nearest_allies(core: GameCore, source: PieceState) -> Array:
	var allies: Array = core.get_player(source.owner).on_board.filter(
		func(c: PieceState) -> bool: return c != source)
	return Combat.detection(core, source, "nearest", allies)


# --- 效果 ---

# ADCR：自身 ATK+damage_increase，SPR 同步。
class AdcGrowEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var inc: int = int(core.balance.param(src.card_id, "damage_increase", 0))
		src.damage += inc
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.damage += inc
		return true


# APR：目標麻痺；偷取目標 attack_steal_rate% ATK，自身與 SPR +偷取值，目標 ATK -偷取值。
class ApStealEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var target: PieceState = ctx.target
		var core: GameCore = ctx.core
		if target == null:
			return true
		target.set_numb(true)
		var rate: int = int(core.balance.param(src.card_id, "attack_steal_rate", 0))
		var value: int = int(target.damage * (float(rate) / 100.0))
		src.damage += value
		target.damage -= value
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.damage += value
		return true


# TANKR：最近友方（不含自己）+armor_increase；SPR +armor_increase（兩迴圈獨立，最近友方若是 SPR 會 +2×）。
class TankArmorEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var inc: int = int(core.balance.param(src.card_id, "armor_increase", 0))
		for ally: PieceState in RedCards._nearest_allies(core, src):
			ally.armor += inc
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.armor += inc
		return true


# HFR：自損 health_decrease，HP 歸 0 進怒氣；ATK+damage_increase，SPR 同步。
class HfGrowEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		src.health -= int(core.balance.param(src.card_id, "health_decrease", 0))
		if src.health == 0:
			src.set_anger(true)
		# 演出：自傷飄血（對齊 Python pending_combat_events "hurt"）。
		core.event_sink.append(GameEvent.hurt(src.pos(), 0.0, src.health))
		var inc: int = int(core.balance.param(src.card_id, "damage_increase", 0))
		src.damage += inc
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.damage += inc
		return true


# HFR：怒氣時不死身（CAN_BE_KILLED 回傳 true = 保護不死）。
class HfImmortalEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		return ctx.source.is_angry()


# HFR settle（Python Hf.on_settle，clear_numbness=True 語意；numbness 由 settle_piece 於效果後清除）：
#   麻痺 → 清怒氣、得 0；怒氣（非麻痺）→ 清怒氣、得 0；否則正常（維持 base）。
class HfSettleEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		if src.is_numb():
			src.set_anger(false)
			return ctx.value      # base 已為 0
		if src.is_angry():
			src.set_anger(false)
			return 0
		return ctx.value


# LFR：自身 +armor_increase 護盾 +damage_increase ATK；SPR 同步。
class LfGrowEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var arm: int = int(core.balance.param(src.card_id, "armor_increase", 0))
		var dmg: int = int(core.balance.param(src.card_id, "damage_increase", 0))
		src.armor += arm
		src.damage += dmg
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.armor += arm
			sp.damage += dmg
		return true


# ASSR：斬殺後 最近友方 ATK+damage_increase；SPR 同步。
class AssKillBuffEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var inc: int = int(core.balance.param(src.card_id, "damage_increase", 0))
		for ally: PieceState in RedCards._nearest_allies(core, src):
			ally.damage += inc
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.damage += inc
		return true


# APTR：最近友方 +armor/+damage，自己 +armor/+damage，SPR +armor/+damage。
class AptBuffEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var arm: int = int(core.balance.param(src.card_id, "armor_increase", 0))
		var dmg: int = int(core.balance.param(src.card_id, "damage_increase", 0))
		for ally: PieceState in RedCards._nearest_allies(core, src):
			ally.armor += arm
			ally.damage += dmg
		for sp: PieceState in RedCards._allied_sprs(core, src.owner):
			sp.armor += arm
			sp.damage += dmg
		src.armor += arm
		src.damage += dmg
		return true
