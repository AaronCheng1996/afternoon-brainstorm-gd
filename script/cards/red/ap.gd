extends Piece
class_name RedAP

var buff_value : int = 100

func _init() -> void:
	show_name = Global.data.card.red.ap.show_name
	description = Global.data.card.red.ap.description.format([str(buff_value)])
	hint = Global.data.card.red.ap.hint
	piece_type = Global.PieceType.AP


func _ready() -> void:
	if ability_component:
		ability_component.setup(self, RedAPAbilities.create())
	super._ready()
