# P1-6 Blue 全卡能力組裝（見 docs/rebuild/02 §Blue，Python 出處 cards/card_blue.py）。
# 藍色主題：token 引擎（3 顆換 1 抽，見 TokenEngineV2）。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[AbilityV2]）。
class_name BlueCardsV2
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[AbilityV2]）。
static func registrations() -> Dictionary:
	return {
		"ADCB": Callable(BlueCardsV2, "adcb"),
		"APB": Callable(BlueCardsV2, "apb"),
		"TANKB": Callable(BlueCardsV2, "tankb"),
		"HFB": Callable(BlueCardsV2, "hfb"),
		"LFB": Callable(BlueCardsV2, "lfb"),
		"ASSB": Callable(BlueCardsV2, "assb"),
		"APTB": Callable(BlueCardsV2, "aptb"),
		"SPB": Callable(BlueCardsV2, "spb"),
	}


# ADCB：斬殺後 +token_gain 並 got_token 一次（Python Adc.killed）；
#   token_draw 時（Python Adc.token_draw）：麻痺 → 解麻痺；否則排入一次免費攻擊。
static func adcb() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("blue_adc_kill_token", TriggerV2.Type.ON_KILLED, [KillGainOnceEffect.new()], trig),
		AbilityV2.new("blue_adc_token_draw", TriggerV2.Type.ON_TOKEN_DRAW, [AdcTokenDrawEffect.new()], trig),
	]


# APB：攻擊附帶麻痺 + 獲得 token_gain（got_token token_gain 次）（Python Ap.ability）。
static func apb() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [AbilityV2.new("blue_ap_numb_token", TriggerV2.Type.ON_ABILITY_HIT, [ApNumbTokenEffect.new()], trig)]


# TANKB：被攻擊後 +token_gain（got_token token_gain 次）（Python Tank.been_attacked）。
static func tankb() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [AbilityV2.new("blue_tank_token", TriggerV2.Type.ON_BEEN_ATTACKED, [GainTokenGainEffect.new()], trig)]


# HFB：extra_damage = 我方當前 token 數（Python Hf.update；damage_bonus 由管線步驟 4 自動加 extra_damage）。
static func hfb() -> Array:
	var mod: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	return [AbilityV2.new("blue_hf_token_dmg", TriggerV2.Type.ON_UPDATE, [HfTokenDamageEffect.new()], mod)]


# LFB：造成傷害後 +token_gain（got_token token_gain 次）（Python Lf.ability）。
static func lfb() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [AbilityV2.new("blue_lf_token", TriggerV2.Type.ON_ABILITY_HIT, [GainTokenGainEffect.new()], trig)]


# ASSB：斬殺後 +token_gain（got_token token_gain 次）（Python Ass.killed）。
static func assb() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [AbilityV2.new("blue_ass_token", TriggerV2.Type.ON_KILLED, [GainTokenGainEffect.new()], trig)]


# APTB：extra_damage = armor//divisor（Python Apt.update）；
#   造成傷害後獲得等量 token（Python Apt.after_damage_calculated）；
#   我方每獲得一次 token → 自身 +1 護盾（Python Apt.after_token）。
static func aptb() -> Array:
	var mod: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("blue_apt_armor_dmg", TriggerV2.Type.ON_UPDATE, [AptArmorDamageEffect.new()], mod),
		AbilityV2.new("blue_apt_dmg_token", TriggerV2.Type.ON_AFTER_DAMAGE, [AptDamageTokenEffect.new()], trig),
		AbilityV2.new("blue_apt_after_token", TriggerV2.Type.ON_TOKEN_GAINED, [AptAfterTokenEffect.new()], trig),
	]


# SPB：佈署時對隨機敵方（含中立）重複（我方場上數+棄牌堆數）次各造成 spawn_damage 傷；
#   結束後清空攻擊佇列（Python Sp.deploy）。
static func spb() -> Array:
	var enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	return [AbilityV2.new("blue_sp_deploy_burst", TriggerV2.Type.ON_DEPLOY, [SpDeployEffect.new()], enter)]


# --- 效果 ---

# 加 token_gain 並 got_token 一次（ADCB 斬殺用）。
class KillGainOnceEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var gain: int = int(core.balance.param(src.card_id, "token_gain", 0))
		TokenEngineV2.gain(core, src.owner, gain, 1)
		return true


# 加 token_gain 並 got_token token_gain 次（TANKB/LFB/ASSB 共用）。
class GainTokenGainEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var gain: int = int(core.balance.param(src.card_id, "token_gain", 0))
		TokenEngineV2.gain(core, src.owner, gain, gain)
		return true


# APB：目標麻痺 + 加 token_gain（got_token token_gain 次）。
class ApNumbTokenEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		if ctx.target != null:
			ctx.target.set_numb(true)
		var gain: int = int(core.balance.param(src.card_id, "token_gain", 0))
		TokenEngineV2.gain(core, src.owner, gain, gain)
		return true


# ADCB token_draw：麻痺 → 解麻痺；否則排入一次免費攻擊（不同步遞迴，經佇列）。
class AdcTokenDrawEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		if src.is_numb():
			src.set_numb(false)
		else:
			CombatV2.enqueue_attack(ctx.core, src)
		return true


# HFB：extra_damage = 我方當前 token 數。
class HfTokenDamageEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		src.extra_damage = int(ctx.core.players_token[src.owner])
		return ctx.value


# APTB：extra_damage = armor // token_from_armor_divisor。
class AptArmorDamageEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var div: int = int(ctx.core.balance.param(src.card_id, "token_from_armor_divisor", 1))
		src.extra_damage = src.armor / maxi(1, div)
		return ctx.value


# APTB：造成傷害後獲得等量 token（value = 本次造成傷害），got_token value 次。
class AptDamageTokenEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var value: int = ctx.value
		TokenEngineV2.gain(ctx.core, ctx.source.owner, value, value)
		return true


# APTB：我方每獲得一次 token → 自身 +1 護盾（after_token）。
class AptAfterTokenEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		ctx.source.armor += 1
		return true


# SPB 佈署爆發：對隨機存活敵方重複（我方場上數+棄牌堆數）次各造成 spawn_damage 傷，最後清佇列。
# 注意：佈署在「本子加入 on_board 之前」執行（見 game_core._spawn_card 對齊 Python），故計數不含自己。
class SpDeployEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var owner: String = src.owner
		var dmg: int = int(core.balance.param(src.card_id, "spawn_damage", 1))
		var p: PlayerState = core.get_player(owner)
		var count: int = p.on_board.size() + p.discard_pile.size()
		var enemies: Array = core.get_enemies_of(owner).filter(
			func(c: PieceState) -> bool: return c.health > 0)
		for _i in count:
			if enemies.is_empty():
				break
			var victim: PieceState = core.rng.choice(enemies)
			CombatV2.damage_calculate(core, victim, dmg, src, true, 0.0)
			enemies = core.get_enemies_of(owner).filter(
				func(c: PieceState) -> bool: return c.health > 0)
		core.pending_attacks.clear()
		return true
