extends Piece
class_name PurpleAP

func _init() -> void:
	show_name = Global.data.card.purple.ap.show_name
	description = Global.data.card.purple.ap.description
	hint = Global.data.card.purple.ap.hint
	piece_type = Global.PieceType.AP

func _on_attack_component_on_hit(target: Piece) -> void:
	if not target.buff_component:
		return
	#清除buff並暈眩
	target.clear_buffs()
	target.add_buff(Global.get_stun_debuff())
	#破甲
	var hp = target.get("health_component")
	if not hp:
		return
	hp.shield = 0
