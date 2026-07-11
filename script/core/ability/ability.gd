# P1-3 能力定義（見 docs/rebuild/04 §5.2）。
# 命名加 V2 以與舊碼 script/abilities/ability.gd 的 Ability 區隔（Phase 6 收編再統一）。
class_name AbilityV2
extends RefCounted

var id: String = ""                 # 沉默用唯一鍵，如 "red_adc_grow"
var trigger: int = 0                # TriggerV2.Type
var tags: Array[int] = []           # AbilityComponentV2.Tag（沉默/分類用）
var priority: int = 0               # MOD_FIELD_INTERCEPT 排序用（APTF=20）
var condition: Callable = Callable() # func(ctx: AbilityContextV2) -> bool；未設定＝恆真
var effects: Array = []             # Array[AbilityEffectV2]


func _init(p_id: String = "", p_trigger: int = 0, p_effects: Array = [],
		p_tags: Array[int] = [], p_priority: int = 0) -> void:
	id = p_id
	trigger = p_trigger
	effects = p_effects
	tags = p_tags
	priority = p_priority
