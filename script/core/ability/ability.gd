# P1-3 能力定義（見 docs/rebuild/04 §5.2）。
class_name Ability
extends RefCounted

var id: String = ""                 # 沉默用唯一鍵，如 "red_adc_grow"
var trigger: int = 0                # Trigger.Type
var tags: Array[int] = []           # AbilityComponent.Tag（沉默/分類用）
var priority: int = 0               # MOD_FIELD_INTERCEPT 排序用（APTF=20）
var condition: Callable = Callable() # func(ctx: AbilityContext) -> bool；未設定＝恆真
var effects: Array = []             # Array[AbilityEffect]


func _init(p_id: String = "", p_trigger: int = 0, p_effects: Array = [],
		p_tags: Array[int] = [], p_priority: int = 0) -> void:
	id = p_id
	trigger = p_trigger
	effects = p_effects
	tags = p_tags
	priority = p_priority
