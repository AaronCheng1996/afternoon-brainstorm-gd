extends Piece
class_name WhiteAP

func _init() -> void:
	show_name = Global.data.card.white.ap.show_name
	description = Global.data.card.white.ap.description
	hint = Global.data.card.white.ap.hint
	piece_type = Global.PieceType.AP

func _on_attack_component_on_hit(target: Piece) -> void:
	if not target.buff_component:
		return
	#給予暈眩
	if not target.buff_component.has_buff(Global.data.buff.stun.name): #不疊加
		target.add_buff(Global.get_stun_debuff())
