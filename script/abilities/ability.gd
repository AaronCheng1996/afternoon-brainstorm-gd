class_name Ability
extends Resource

enum Tag { TRIGGERED, PASSIVE, ON_ENTER, FACTION }

@export var id: String = ""
@export var trigger: GameTrigger.Type = GameTrigger.Type.ON_ATTACK_HIT
## 使用 Ability.Tag 的整數值（GDScript 4.x 內部 enum 陣列）
var tags: Array[int] = []
var effects: Array[AbilityEffect] = []
var condition: Callable = Callable()
var params: Dictionary = {}


func matches_trigger(trigger_type: GameTrigger.Type) -> bool:
	return trigger == trigger_type


func can_run(ctx: GameEvent) -> bool:
	if condition.is_valid():
		return condition.call(ctx)
	return true


func run(ctx: GameEvent) -> void:
	for effect: AbilityEffect in effects:
		effect.execute(ctx)
