extends Piece
class_name RedAPT

var red = preload("res://script/cards/red/red.gd").new()
var buff_value : int = 1

func _init() -> void:
	show_name = Global.data.card.red.apt.show_name
	description = Global.data.card.red.apt.description.format([str(buff_value)])
	hint = Global.data.card.red.apt.hint
	piece_type = Global.PieceType.APT

#攻擊時為最近友方附加+1/+1
func attack() -> void:
	if attack_component:
		super.attack()
		#buff
		red.attack_buff(buff_value, self)
		red.buff_health(buff_value, self)
		#最近友方
		var ally = get_nearest_ally()
		if ally != null:
			red.attack_buff(buff_value, ally)
			red.buff_health(buff_value, ally)
