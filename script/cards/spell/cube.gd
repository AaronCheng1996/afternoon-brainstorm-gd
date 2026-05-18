extends Spell
class_name Cube

var attack : int = 0
var health : int = 4
const CUBE_TOKEN = preload("res://scenes/cards/token/cube_token.tscn")

func _init() -> void:
	show_name = Global.data.card.spell_and_token.cube.show_name
	description = Global.data.card.spell_and_token.cube.description.format([str(attack), str(health)])
	hint = Global.data.card.spell_and_token.cube.hint

#效果
func effect(target: Vector2i) -> void:
	var cube = CUBE_TOKEN.instantiate()
	cube.card_owner = null
	add_piece_to_board.emit(cube, target)

#施放完（不進墓地）
func used() -> void:
	_leave_hand()
