extends Buff
class_name Stun

func apply_buff(target: Piece) -> void:
	if target.outfit_component:
		#無法主動攻擊
		target.outfit_component.disable_attack()
		#無法移動
		target.outfit_component.disable_move()
	#無法得分
	if target.score_component:
		value = target.score_component.score
		target.score_component.score -= value

func remove_buff(target: Piece) -> void:
	if target.outfit_component:
		#恢復攻擊
		target.outfit_component.enable_attack()
		#恢復移動
		target.outfit_component.enable_move()
	#恢復得分
	if value == 0:
		return
	if target.score_component:
		target.score_component.score += value
