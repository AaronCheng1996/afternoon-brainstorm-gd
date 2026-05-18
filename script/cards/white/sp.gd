extends Piece
class_name WhiteSP

func _init() -> void:
	show_name = Global.data.card.white.sp.show_name
	description = Global.data.card.white.sp.description
	hint = Global.data.card.white.sp.hint
	piece_type = Global.PieceType.SP

func refresh() -> void:
	var text = str(score_component.score - 1)
	text = Global.set_font_color(text, Global.get_font_color(score_component.score, score_component.DEFAULT_SCORE))
	description = Global.data.card.white.sp.description.format([text])
	super.refresh()
