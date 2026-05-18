extends Piece
class_name GreenAP

var green = preload("res://script/cards/green/green.gd").new()

func _init() -> void:
	show_name = Global.data.card.green.ap.show_name
	description = Global.data.card.green.ap.description
	hint = Global.data.card.green.ap.hint
	piece_type = Global.PieceType.AP

func _on_attack_component_on_hit(target: Piece) -> void:
	if not target.buff_component:
		return
	#給予暈眩
	if not target.buff_component.has_buff(Global.data.buff.stun.name): #不疊加
		target.add_buff(Global.get_stun_debuff())
	#對手不幸事件
	green.unlucky_event(target, true)
	#自己幸運事件
	green.lucky_event(self, true)
