# P1-3 能力效果基底（見 docs/rebuild/04 §5.2）。
# 回傳語義依 trigger 類別（由 AbilityComponentV2 的對應方法解讀）：
#   MOD_DAMAGE_BONUS / MOD_DAMAGE_REDUCE / ON_SETTLE → 回傳新的 int（串接）；
#   BLOCK_DAMAGE / ON_ABILITY_HIT / CAN_BE_KILLED / CUSTOM_MOVE → 回傳 bool；
#   MOD_FIELD_INTERCEPT → 回傳 {priority:int, value:int, feedback:Callable} 或 null；
#   其餘（ON_KILLED/ON_DEPLOY…）→ 純副作用，回傳可為 null。
class_name AbilityEffectV2
extends RefCounted


func execute(_ctx: AbilityContextV2) -> Variant:
	return null
