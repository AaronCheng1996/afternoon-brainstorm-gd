# P1-4 White 全卡能力組裝（見 docs/rebuild/02 §White，Python 出處 cards/card_white.py）。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[AbilityV2]）。
# White 為教學基準色：多數職業只有數值、無能力；能力僅 APW/APTW/SPW 三張。
# 特殊卡 CUBE/CUBES/HEAL/MOVE/MOVEO 的行為在 game_core（P1-2）處理，無 native 能力。
class_name WhiteCardsV2
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[AbilityV2]）。
static func registrations() -> Dictionary:
	return {
		"ADCW": Callable(WhiteCardsV2, "adcw"),
		"APW": Callable(WhiteCardsV2, "apw"),
		"HFW": Callable(WhiteCardsV2, "hfw"),
		"LFW": Callable(WhiteCardsV2, "lfw"),
		"ASSW": Callable(WhiteCardsV2, "assw"),
		"APTW": Callable(WhiteCardsV2, "aptw"),
		"SPW": Callable(WhiteCardsV2, "spw"),
		"TANKW": Callable(WhiteCardsV2, "tankw"),
	}


# --- 純數值職業（無 native 能力）---
static func adcw() -> Array: return []
static func hfw() -> Array: return []
static func lfw() -> Array: return []
# 先攻（入場不 numbness）由 PieceState.make 依 ASS 職業處理，故此處無能力。
static func assw() -> Array: return []
static func tankw() -> Array: return []


# APW：攻擊附帶麻痺（Python Ap.ability → target.numbness=True）。
static func apw() -> Array:
	var tags: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [AbilityV2.new("white_ap_numb", TriggerV2.Type.ON_ABILITY_HIT, [NumbEffect.new()], tags)]


# APTW：攻擊時最近友方（不含自己）與自己各獲得等同自身 ATK 的護盾（Python Apt.ability）。
static func aptw() -> Array:
	var tags: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [AbilityV2.new("white_apt_shield", TriggerV2.Type.ON_ABILITY_HIT, [NearestAllyShieldEffect.new()], tags)]


# SPW：settle 時（非 numbness）得 1 + extra_score 分（Python Sp.on_settle）。
static func spw() -> Array:
	var tags: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	return [AbilityV2.new("white_sp_score", TriggerV2.Type.ON_SETTLE, [ExtraScoreEffect.new()], tags)]


# --- 效果 ---

# 攻擊附帶麻痺：使目標 numbness（Python card_white.Ap.ability）。
class NumbEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		if ctx.target != null:
			ctx.target.set_numb(true)
		return true


# 最近友方（不含自己）+ 自己各得 self.damage 護盾（Python card_white.Apt.ability）。
class NearestAllyShieldEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var apt: PieceState = ctx.source
		var core: GameCore = ctx.core
		var allies: Array = core.get_player(apt.owner).on_board.filter(
			func(c: PieceState) -> bool: return c != apt)
		for ally: PieceState in CombatV2.detection(core, apt, "nearest", allies):
			ally.armor += apt.damage
		apt.armor += apt.damage
		return true


# SPW 計分：非 numbness → value + extra_score；numbness → 維持（base 已為 0）。
class ExtraScoreEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var sp: PieceState = ctx.source
		if sp.is_numb():
			return ctx.value
		var extra: int = int(ctx.core.balance.param("SPW", "extra_score", 0))
		return ctx.value + extra
