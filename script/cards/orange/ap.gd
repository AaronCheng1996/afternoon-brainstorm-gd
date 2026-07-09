extends Piece
class_name OrangeAP

var value : int = 1

func _init() -> void:
	show_name = Global.data.card.orange.ap.show_name
	description = Global.data.card.orange.ap.description.format([str(value)])
	hint = Global.data.card.orange.ap.hint
	piece_type = Global.PieceType.AP


func _ready() -> void:
	if ability_component:
		ability_component.setup(self, OrangeAPAbilities.create())
	super._ready()
