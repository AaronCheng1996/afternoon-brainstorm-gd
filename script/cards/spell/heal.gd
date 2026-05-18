extends Spell
class_name Heal

var value : int = 6

func _init() -> void:
	show_name = Global.data.card.spell_and_token.heal.show_name
	description = Global.data.card.spell_and_token.heal.description.format([str(value)])
	hint = Global.data.card.spell_and_token.heal.hint

#取得可放置範圍
func get_valid_location() -> Array:
	var result := []
	for piece: Piece in Global.get_board_pieces():
		result.append(piece.location)
	return result

#效果
func effect(target: Vector2i) -> void:
	Global.board_dic[target].heal(value, self)
