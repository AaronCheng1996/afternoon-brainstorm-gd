# P1-9 DarkGreen 全卡能力組裝 + 圖騰引擎（見 docs/rebuild/02 §DarkGreen，Python 出處 cards/card_dark_green.py）。
# 深綠主題：圖騰（players_totem）——刻印累積、SPDKG 在場使刻印量 2^n 翻倍（見 TotemEngine）。
# 多張卡以 extra_damage = totem // divisor 把圖騰轉為傷害（damage_bonus 沿用 base pipeline 自動加 extra_damage）。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[Ability]）。
class_name DarkGreenCards
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[Ability]）。
static func registrations() -> Dictionary:
	return {
		"ADCDKG": Callable(DarkGreenCards, "adcdkg"),
		"APDKG": Callable(DarkGreenCards, "apdkg"),
		"TANKDKG": Callable(DarkGreenCards, "tankdkg"),
		"HFDKG": Callable(DarkGreenCards, "hfdkg"),
		"LFDKG": Callable(DarkGreenCards, "lfdkg"),
		"ASSDKG": Callable(DarkGreenCards, "assdkg"),
		"APTDKG": Callable(DarkGreenCards, "aptdkg"),
		"SPDKG": Callable(DarkGreenCards, "spdkg"),
	}


# ADCDKG：extra_damage = 圖騰 // damage_divisor（Python Adc.update；damage_bonus 沿用 base）。
static func adcdkg() -> Array:
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	return [Ability.new("dkg_adc_totem_dmg", Trigger.Type.ON_UPDATE, [TotemToDamageEffect.new("damage_divisor")], mod)]


# APDKG：攻擊附帶麻痺 + 刻印 engraved_totem 次（Python Ap.ability）。
static func apdkg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("dkg_ap_numb_totem", Trigger.Type.ON_ABILITY_HIT, [ApNumbEngraveEffect.new()], trig)]


# TANKDKG：被攻擊後 刻印 engraved_totem 次（Python Tank.been_attacked）。
static func tankdkg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("dkg_tank_totem", Trigger.Type.ON_BEEN_ATTACKED, [EngraveEffect.new("engraved_totem")], trig)]


# HFDKG：造成傷害後自療 1（Python Hf.ability）；HP<=4 時 extra_damage=damage_bonus（Python Hf.update）；
#   回合開始自傷 turn_start_health_loss 並刻印 engraved_totem（Python Hf.on_refresh）。
static func hfdkg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	return [
		Ability.new("dkg_hf_heal", Trigger.Type.ON_ABILITY_HIT, [HfHealEffect.new()], trig),
		Ability.new("dkg_hf_low_hp_dmg", Trigger.Type.ON_UPDATE, [HfLowHpDamageEffect.new()], mod),
		Ability.new("dkg_hf_refresh", Trigger.Type.ON_REFRESH, [HfRefreshEffect.new()], trig),
	]


# LFDKG：佈署時對 small_cross 敵方（含中立）造成 圖騰//4 傷害（Python Lf.deploy）；
#   回合開始自傷 turn_start_health_loss（Python Lf.on_refresh）；造成傷害後刻印 engraved_totem（Python Lf.ability）。
static func lfdkg() -> Array:
	var enter: Array[int] = [AbilityComponent.Tag.ON_ENTER]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("dkg_lf_deploy", Trigger.Type.ON_DEPLOY, [LfDeployEffect.new()], enter),
		Ability.new("dkg_lf_refresh", Trigger.Type.ON_REFRESH, [SelfHealthLossEffect.new()], trig),
		Ability.new("dkg_lf_totem", Trigger.Type.ON_ABILITY_HIT, [EngraveEffect.new("engraved_totem")], trig),
	]


# ASSDKG：extra_damage = 圖騰 // damage_divisor（Python Ass.update）；
#   斬殺時自身 HP 歸 0（自殺）並刻印 engraved_totem（Python Ass.killed）。
static func assdkg() -> Array:
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("dkg_ass_totem_dmg", Trigger.Type.ON_UPDATE, [TotemToDamageEffect.new("damage_divisor")], mod),
		Ability.new("dkg_ass_suicide", Trigger.Type.ON_KILLED, [AssSuicideEffect.new()], trig),
	]


# APTDKG：extra_damage = 圖騰 // 2（Python Apt.update）；damage_bonus 時額外刻印 armor//2（Python Apt.damage_bonus 副作用）；
#   造成傷害後 armor += value//2（Python Apt.after_damage_calculated）。
static func aptdkg() -> Array:
	var mod: Array[int] = [AbilityComponent.Tag.MODIFIER]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("dkg_apt_totem_dmg", Trigger.Type.ON_UPDATE, [AptTotemDamageEffect.new()], mod),
		Ability.new("dkg_apt_bonus_engrave", Trigger.Type.MOD_DAMAGE_BONUS, [AptBonusEngraveEffect.new()], mod),
		Ability.new("dkg_apt_gain_armor", Trigger.Type.ON_AFTER_DAMAGE, [AptGainArmorEffect.new()], trig),
	]


# SPDKG：無主動能力；其存在使全隊刻印量 2^n 翻倍（由 TotemEngine 計數）。
static func spdkg() -> Array:
	return []


# --- 效果 ---

# 通用：extra_damage = 圖騰 // param(key)。用於 ADCDKG/ASSDKG（damage_bonus 沿用 base）。
class TotemToDamageEffect extends AbilityEffect:
	var _key: String
	func _init(key: String) -> void:
		_key = key
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var div: int = int(ctx.core.balance.param(src.card_id, _key, 1))
		src.extra_damage = int(ctx.core.players_totem[src.owner]) / maxi(1, div)
		return ctx.value


# 通用：刻印 param(key) 次。用於 TANKDKG（been_attacked）、LFDKG（ability）。
class EngraveEffect extends AbilityEffect:
	var _key: String
	func _init(key: String) -> void:
		_key = key
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		TotemEngine.engrave(ctx.core, src.owner, int(ctx.core.balance.param(src.card_id, _key, 0)))
		return true


# APDKG：目標麻痺 + 刻印 engraved_totem。
class ApNumbEngraveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		if ctx.target != null:
			ctx.target.set_numb(true)
		TotemEngine.engrave(ctx.core, src.owner, int(ctx.core.balance.param(src.card_id, "engraved_totem", 0)))
		return true


# HFDKG：造成傷害後自療 1（溢出轉盾，經 GameCore._heal_piece）。
class HfHealEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.core._heal_piece(ctx.source, 1)
		return true


# HFDKG：HP<=4 時 extra_damage=damage_bonus，否則 0。
class HfLowHpDamageEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		src.extra_damage = int(ctx.core.balance.param(src.card_id, "damage_bonus", 0)) if src.health <= 4 else 0
		return ctx.value


# HFDKG：回合開始自傷 turn_start_health_loss（無附帶）並刻印 engraved_totem。
class HfRefreshEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var loss: int = int(ctx.core.balance.param(src.card_id, "turn_start_health_loss", 0))
		Combat.damage_calculate(ctx.core, src, loss, src, false, 0.0)
		src.hit_cards.clear()   # 自傷（attacker==victim）會把自己壓進 hit_cards，清掉以免自我循環參考洩漏。
		TotemEngine.engrave(ctx.core, src.owner, int(ctx.core.balance.param(src.card_id, "engraved_totem", 0)))
		return true


# LFDKG/HFDKG 共用回合開始自傷（無附帶）。LFDKG 用（不刻印，見 Python Lf.on_refresh）。
class SelfHealthLossEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var loss: int = int(ctx.core.balance.param(src.card_id, "turn_start_health_loss", 0))
		Combat.damage_calculate(ctx.core, src, loss, src, false, 0.0)
		src.hit_cards.clear()   # 自傷（attacker==victim）會把自己壓進 hit_cards，清掉以免自我循環參考洩漏。
		return true


# LFDKG：佈署時對 small_cross 敵方（含中立）造成 圖騰//4 傷害（ability=True，會觸發自身 engrave）。
class LfDeployEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var dmg: int = int(core.players_totem[src.owner]) / 4
		for target: PieceState in Combat.detection(core, src, "small_cross", core.get_enemies_of(src.owner)):
			Combat.damage_calculate(core, target, dmg, src, true, 0.0)
		return true


# ASSDKG：斬殺時自身 HP 歸 0（自殺）並刻印 engraved_totem。
class AssSuicideEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		src.health = 0
		ctx.core.event_sink.append(GameEvent.hurt(src.pos(), 0.0, 0))
		TotemEngine.engrave(ctx.core, src.owner, int(ctx.core.balance.param(src.card_id, "engraved_totem", 0)))
		return true


# APTDKG：extra_damage = 圖騰 // 2。
class AptTotemDamageEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.source.extra_damage = int(ctx.core.players_totem[ctx.source.owner]) / 2
		return ctx.value


# APTDKG：damage_bonus 副作用——刻印 armor//2；不再加 extra_damage（base pipeline 已於步驟 4 自動加）。
class AptBonusEngraveEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		TotemEngine.engrave(ctx.core, src.owner, src.armor / 2)
		return ctx.value


# APTDKG：造成傷害後 armor += value//2。
class AptGainArmorEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.source.armor += ctx.value / 2
		return true
