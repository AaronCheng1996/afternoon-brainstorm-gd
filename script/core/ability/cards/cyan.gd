# P1-10 Cyan 全卡能力組裝 + CoinEngine（見 docs/rebuild/02 §Cyan，Python 出處 cards/card_cyan.py）。
# 金幣主題：多數卡行動時 get_coins；手牌可切升級形態，升級版生成時付費（price_check 在 GameCore）。
# 升級與否的差異在效果內以 ctx.source.upgrade 於執行期分流（能力依 card_id 註冊，不分升級版）。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[AbilityV2]）。
class_name CyanCardsV2
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[AbilityV2]）。
static func registrations() -> Dictionary:
	return {
		"ADCC": Callable(CyanCardsV2, "adcc"),
		"APC": Callable(CyanCardsV2, "apc"),
		"TANKC": Callable(CyanCardsV2, "tankc"),
		"HFC": Callable(CyanCardsV2, "hfc"),
		"LFC": Callable(CyanCardsV2, "lfc"),
		"ASSC": Callable(CyanCardsV2, "assc"),
		"APTC": Callable(CyanCardsV2, "aptc"),
		"SPC": Callable(CyanCardsV2, "spc"),
	}


# ADCC：造成傷害後 +coin_gain$（Python Adc.ability）；升級版 攻擊成功後再攻擊一次（Python Adc.attack）。
static func adcc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	return [
		AbilityV2.new("cyan_adc_coin", TriggerV2.Type.ON_ABILITY_HIT, [CoinGainOnAbilityEffect.new()], trig),
		AbilityV2.new("cyan_adc_double", TriggerV2.Type.ATTACK_OVERRIDE, [AdcAttackEffect.new()], passive),
	]


# APC：攻擊附帶麻痺 +coin_gain$（Python Ap.ability）；佈署攻擊（Python Ap.deploy，基礎=無視麻痺攻 2 次、升級=代打）。
static func apc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	return [
		AbilityV2.new("cyan_ap_numb_coin", TriggerV2.Type.ON_ABILITY_HIT, [ApNumbCoinEffect.new()], trig),
		AbilityV2.new("cyan_ap_deploy", TriggerV2.Type.ON_DEPLOY, [ApDeployEffect.new()], enter),
	]


# TANKC：被攻擊 +coin_gain$（Python Tank.been_attacked）；升級版 格擋第一次攻擊（怒氣→damage_block）。
static func tankc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var mod: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	return [
		AbilityV2.new("cyan_tank_coin", TriggerV2.Type.ON_BEEN_ATTACKED, [CoinGainOnBeenAttackedEffect.new()], trig),
		AbilityV2.new("cyan_tank_init_anger", TriggerV2.Type.ON_DEPLOY, [UpgradeAngerInitEffect.new()], enter),
		AbilityV2.new("cyan_tank_block", TriggerV2.Type.BLOCK_DAMAGE, [AngerBlockEffect.new()], mod),
	]


# HFC：造成傷害後 +coin_gain$（Python Hf.ability）；升級版 死亡時進怒氣多活一回合並 ATK+damage_bonus，該回合不得分。
static func hfc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var mod: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	return [
		AbilityV2.new("cyan_hf_coin", TriggerV2.Type.ON_ABILITY_HIT, [CoinGainOnAbilityEffect.new()], trig),
		AbilityV2.new("cyan_hf_revive", TriggerV2.Type.ON_BEEN_KILLED, [HfReviveEffect.new()], trig),
		AbilityV2.new("cyan_hf_immortal", TriggerV2.Type.CAN_BE_KILLED, [AngerImmortalEffect.new()], mod),
		AbilityV2.new("cyan_hf_settle", TriggerV2.Type.ON_SETTLE, [HfSettleEffect.new()], mod),
	]


# LFC：造成傷害後 +coin_gain$（Python Lf.ability）；升級版 每回合開始隨機換攻擊模式（Python Lf.on_refresh）。
static func lfc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("cyan_lf_coin", TriggerV2.Type.ON_ABILITY_HIT, [CoinGainOnAbilityEffect.new()], trig),
		AbilityV2.new("cyan_lf_random_mode", TriggerV2.Type.ON_REFRESH, [LfRandomModeEffect.new()], trig),
	]


# ASSC：斬殺 +coin_gain$（Python Ass.killed）；升級版 第一次攻擊 +damage_bonus（一次性 extra_damage）。
static func assc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var mod: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	return [
		AbilityV2.new("cyan_ass_coin", TriggerV2.Type.ON_KILLED, [CoinGainOnKilledEffect.new()], trig),
		AbilityV2.new("cyan_ass_init_bonus", TriggerV2.Type.ON_DEPLOY, [AssInitBonusEffect.new()], enter),
		AbilityV2.new("cyan_ass_bonus_reset", TriggerV2.Type.MOD_DAMAGE_BONUS, [AssBonusResetEffect.new()], mod),
	]


# APTC：回合開始 +coin_gain$（Python Apt.on_refresh）；升級版 受傷減免 = 金幣//coin_per（上限 max）。
static func aptc() -> Array:
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var mod: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	return [
		AbilityV2.new("cyan_apt_coin", TriggerV2.Type.ON_REFRESH, [CoinGainOnRefreshEffect.new()], trig),
		AbilityV2.new("cyan_apt_reduce", TriggerV2.Type.MOD_DAMAGE_REDUCE, [AptCoinReduceEffect.new()], mod),
	]


# SPC：佈署 +coin_gain$（Python Sp.deploy）；升級版折扣在 GameCore._cyan_price_check 處理（無 native 能力）。
static func spc() -> Array:
	var enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	return [AbilityV2.new("cyan_sp_deploy_coin", TriggerV2.Type.ON_DEPLOY, [CoinGainOnDeployEffect.new()], enter)]


# --- 通用金幣效果（各卡 coin_gain 取自各自 card_id）---

class CoinGainOnAbilityEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		CoinEngineV2.gain(ctx.core, ctx.source.owner, int(ctx.core.balance.param(ctx.source.card_id, "coin_gain", 0)))
		return true


class CoinGainOnBeenAttackedEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		CoinEngineV2.gain(ctx.core, ctx.source.owner, int(ctx.core.balance.param(ctx.source.card_id, "coin_gain", 0)))
		return true


class CoinGainOnKilledEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		CoinEngineV2.gain(ctx.core, ctx.source.owner, int(ctx.core.balance.param(ctx.source.card_id, "coin_gain", 0)))
		return true


class CoinGainOnRefreshEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		CoinEngineV2.gain(ctx.core, ctx.source.owner, int(ctx.core.balance.param(ctx.source.card_id, "coin_gain", 0)))
		return true


class CoinGainOnDeployEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		CoinEngineV2.gain(ctx.core, ctx.source.owner, int(ctx.core.balance.param(ctx.source.card_id, "coin_gain", 0)))
		return true


# --- 卡牌專屬效果 ---

# ADCC 攻擊覆寫：launch_attack；升級版成功後再攻擊一次（非升級等同一般攻擊）。
class AdcAttackEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		if CombatV2.launch_attack(ctx.core, src, src.attack_types):
			if src.upgrade:
				CombatV2.launch_attack(ctx.core, src, src.attack_types)
			return true
		return false


# APC 攻擊附帶：目標麻痺 + coin_gain$。
class ApNumbCoinEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		if ctx.target != null:
			ctx.target.set_numb(true)
		CoinEngineV2.gain(ctx.core, ctx.source.owner, int(ctx.core.balance.param(ctx.source.card_id, "coin_gain", 0)))
		return true


# APC 佈署攻擊（Python Ap.deploy）：
#   基礎：重複 number_of_attack 次，無視麻痺以自身攻擊模式攻擊。
#   升級：重複 number_of_attack 次，隨機指派一個我方 nearest/farthest 攻擊者對「APC 的最近目標」發動攻擊；
#         找不到代打者才自己無視麻痺攻擊。佈署在本子入場前執行，故 on_board 不含自己。
class ApDeployEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var times: int = int(core.balance.param(src.card_id, "number_of_attack", 0))
		if not src.upgrade:
			for _i in times:
				CombatV2.launch_attack(core, src, src.attack_types, [], true)
			return true
		for _i in times:
			var candidates: Array = core.get_player(src.owner).on_board.filter(
				func(c: PieceState) -> bool:
					return c != src and not c.is_numb() \
						and ("nearest" in c.attack_types or "farthest" in c.attack_types))
			if candidates.is_empty():
				CombatV2.launch_attack(core, src, src.attack_types, [], true)
				continue
			var chosen: PieceState = core.rng.choice(candidates)
			var pool: Array = []
			pool.append_array(core.get_player(core.opponent_name(src.owner)).on_board)
			pool.append_array(core.neutral_pieces)
			var targets: Array = CombatV2.detection(core, src, src.attack_types, pool)
			CombatV2.launch_attack(core, chosen, chosen.attack_types, targets)
		return true


# 升級版佈署設怒氣（TANKC init：upgrade → anger=True，供 damage_block 格擋首擊）。
class UpgradeAngerInitEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		if ctx.source.upgrade:
			ctx.source.set_anger(true)
		return true


# 怒氣格擋：怒氣時 damage_block 回 true（整段傷害管線取消），並清怒氣（一次性）。
class AngerBlockEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		if ctx.source.is_angry():
			ctx.source.set_anger(false)
			return true
		return false


# HFC 升級版被殺：進怒氣（不死身）+ ATK+damage_bonus。
class HfReviveEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		if src.upgrade:
			src.set_anger(true)
			src.damage += int(ctx.core.balance.param(src.card_id, "damage_bonus", 0))
		return true


# 怒氣不死身（CAN_BE_KILLED 回 true = 保護不死）。
class AngerImmortalEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		return ctx.source.is_angry()


# HFC settle（Python Hf.on_settle，含 count 機制）：怒氣時 count→0；numbness 或 count==0 → 清怒氣、得 0；否則得 base。
class HfSettleEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		if src.is_angry():
			src.counters["count"] = 0
		var count: int = int(src.counters.get("count", 1))
		if src.is_numb() or count == 0:
			src.set_anger(false)   # numbness 由 settle_piece 於效果後清除
			return 0
		return ctx.value


# LFC 升級版回合開始：隨機換攻擊模式。
class LfRandomModeEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		if ctx.source.upgrade:
			var modes: Array = ["large_cross", "nearest", "small_cross", "small_cross small_x", "farthest"]
			ctx.source.attack_types = str(ctx.core.rng.choice(modes))
		return true


# ASSC 升級版佈署：進怒氣 + extra_damage = damage_bonus（首擊一次性加成）。
class AssInitBonusEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		if src.upgrade:
			src.set_anger(true)
			src.extra_damage = int(ctx.core.balance.param(src.card_id, "damage_bonus", 0))
		return true


# ASSC damage_bonus（Python Ass.damage_bonus）：extra_damage 已由管線步驟 4 自動加入 ctx.value，
# 此效果僅負責「用後歸零 extra_damage、清怒氣」，回傳原值不重複加。
class AssBonusResetEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		src.set_anger(false)
		var v: int = ctx.value
		src.extra_damage = 0
		return v


# APTC 升級版受傷減免：value -= min(金幣//coin_per, max)，下限 0。
class AptCoinReduceEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		if not src.upgrade:
			return ctx.value
		var per: int = maxi(1, int(core.balance.param(src.card_id, "coin_per_damage_resistance", 1)))
		var maxr: int = int(core.balance.param(src.card_id, "maximum_damage_resistance", 0))
		var reduce: int = mini(int(core.players_coin[src.owner]) / per, maxr)
		return maxi(ctx.value - reduce, 0)
