extends Piece
class_name PurpleHF

var value : int = 4

func _init() -> void:
	show_name = Global.data.card.purple.hf.show_name
	description = Global.data.card.purple.hf.description.format([str(value)])
	hint = Global.data.card.purple.hf.hint
	piece_type = Global.PieceType.HF

#回合開始時
func on_turn_start(current_turn: int) -> void:
	if current_turn == card_owner.id:
		var count = 0
		for piece: Piece in Global.get_board_pieces().filter(filter_opponent_piece):
			if attack_component.in_attack_range(location, piece.location):
				count += 1
		card_owner.add_attack_count(count / 3)
	super.on_turn_start(current_turn)
