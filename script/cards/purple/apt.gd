extends Piece
class_name PurpleAPT

var percent : int = 100

func _init() -> void:
	show_name = Global.data.card.purple.apt.show_name
	description = Global.data.card.purple.apt.description.format([str(percent)])
	hint = Global.data.card.purple.apt.hint
	piece_type = Global.PieceType.APT

func take_damaged(damage: int, applyer) -> bool:
	var damage_reduced: int = 0
	if applyer != null:
		if applyer.attack_component:
			damage_reduced = (damage - applyer.attack_component.atk) / 2
			if damage_reduced < 0:
				damage_reduced = 0
	if damage_reduced > 0:
		var ally = get_nearest_ally()
		if not ally == null:
			ally.shielded(damage_reduced * percent / 100, self)
	return super.take_damaged(damage - damage_reduced, applyer)
