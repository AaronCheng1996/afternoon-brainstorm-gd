extends Piece
class_name OrangeLF

func _init() -> void:
	show_name = Global.data.card.orange.lf.show_name
	description = Global.data.card.orange.lf.description.format([str(3)])
	hint = Global.data.card.orange.lf.hint
	piece_type = Global.PieceType.LF

func refresh() -> void:
	if attack_component:
		var text = str(attack_component.atk)
		text = Global.set_font_color(text, Global.get_font_color(attack_component.atk, attack_component.DEFAULT_ATK))
		description = Global.data.card.orange.lf.description.format([text])
	super.refresh()

func attack() -> void:
	super.attack()
	if not buff_component.has_buff(Global.data.buff.move.name):
		add_buff(Global.get_move_buff())

func after_move() -> void:
	Global.piece_moved(self)
	attack_component.hit(get_nearest_enemy())
