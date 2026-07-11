# P1-3 能力執行情境（見 docs/rebuild/04 §5.2）。
# 傳給每個 AbilityEffectV2.execute()。value 於 MOD 類觸發鏈式傳遞。
class_name AbilityContextV2
extends RefCounted

var core: Object            # GameCore（避免與 core 類循環相依，宣告為 Object）
var source: PieceState      # 能力擁有者
var target: PieceState      # 目標（可 null）
var value: int              # 傳遞/修改值（MOD 類）
var extra: Dictionary       # 其他資料（attacker、feedback 等）


func _init(core_ref: Object = null, src: PieceState = null, tgt: PieceState = null,
		val: int = 0, ex: Dictionary = {}) -> void:
	core = core_ref
	source = src
	target = tgt
	value = val
	extra = ex
