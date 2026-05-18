extends Piece
class_name BlueAPT

var blue = preload("res://script/cards/blue/blue.gd").new()
var buff_value : int = 1

func _init() -> void:
	show_name = Global.data.card.blue.apt.show_name
	description = Global.data.card.blue.apt.description.format([str(buff_value), str(0)])
	hint = Global.data.card.blue.apt.hint
	piece_type = Global.PieceType.APT

func refresh() -> void:
	if health_component:
		var text = str(health_component.shield / 4)
		text = Global.set_font_color(text, Global.get_font_color(health_component.shield / 4, health_component.DEFAULT_SHIELD / 4))
		description = Global.data.card.blue.apt.description.format([str(buff_value), text])
	super.refresh()

#攻擊後獲得護盾 1/4 藍球
func attack() -> void:
	super.attack()
	if health_component.shield / 4 > 0:
		blue.add_blue_charge(card_owner, health_component.shield / 4)

func trigger_effect(value: int) -> void:
	if is_on_board:
		shielded(value * buff_value, self)
