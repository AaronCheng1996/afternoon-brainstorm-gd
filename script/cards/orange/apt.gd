extends Piece
class_name OrangeAPT

var buff_value : int = 1
var trans_rate : int = 50

func _init() -> void:
	show_name = Global.data.card.orange.apt.show_name
	description = Global.data.card.orange.apt.description.format([str(buff_value), str(trans_rate)])
	hint = Global.data.card.orange.apt.hint
	piece_type = Global.PieceType.APT

func trigger_effect(piece: Piece) -> void:
	if not is_on_board:
		return
	#給自己附加護盾
	shielded(buff_value, self)
	#給友方附加護盾
	piece.shielded(buff_value, self)

#護盾1/2轉為攻擊力
func after_move() -> void:
	Global.piece_moved(self)
	var attack_buff = AttackBuff.new()
	attack_buff.show_name = Global.data.buff.attack_buff.name
	attack_buff.description = Global.data.buff.attack_buff.description.format([str(health_component.shield * trans_rate / 100)])
	attack_buff.tag.append_array([Global.BuffTag.BUFF, Global.BuffTag.ORANGE])
	attack_buff.value = health_component.shield * trans_rate / 100
	health_component.shield -= attack_buff.value
	add_buff(attack_buff)
