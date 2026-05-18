extends Piece
class_name BlueHF

var blue = preload("res://script/cards/blue/blue.gd").new()

func _init() -> void:
	show_name = Global.data.card.blue.hf.show_name
	description = Global.data.card.blue.hf.description.format([str(0)])
	hint = Global.data.card.blue.hf.hint
	piece_type = Global.PieceType.HF
	
func refresh() -> void:
	var text = str(blue.get_blue_charge_count(card_owner))
	text = Global.set_font_color(text, Global.get_font_color(blue.get_blue_charge_count(card_owner), 0))
	description = Global.data.card.blue.hf.description.format([text])
	super.refresh()

func attack() -> void:
	attack_component.attack(Global.get_board_pieces().filter(filter_opponent_piece), blue.get_blue_charge_count(card_owner))
	refresh()

func trigger_effect(value: int) -> void:
	refresh()
