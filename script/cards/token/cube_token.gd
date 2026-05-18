extends Piece
class_name CubeToken

func _init() -> void:
	show_name = Global.data.card.spell_and_token.cube_token.show_name
	description = Global.data.card.spell_and_token.cube_token.description
	hint = Global.data.card.spell_and_token.cube_token.hint
	card_type = Global.CardType.TOKEN

func die(true_death: bool = false) -> void:
	#預留：動畫位置
	Global.board_dic[location] = 0
	emit_signal("piece_die", self)
