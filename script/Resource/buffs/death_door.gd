extends Buff
class_name DeathDoor


func apply_buff(target: Piece) -> void:
	#無法得分
	if target.score_component:
		value = target.score_component.score
		target.score_component.score -= value

func remove_buff(target: Piece) -> void:
	#恢復得分
	if value == 0:
		return
	if target.score_component:
		target.score_component.score += value

func tick(target: Piece) -> void:
	#死亡
	if duration == 1:
		target.die(true)
