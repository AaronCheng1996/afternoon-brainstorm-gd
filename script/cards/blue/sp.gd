extends Piece
class_name BlueSP

var blue = preload("res://script/cards/blue/blue.gd").new()
var beam_scene = preload("res://scenes/attack/beam_attack.tscn")
var hit_value = 1

var default_count: int = 0
var count: int = 0
var count_show: int = 0

func _init() -> void:
	show_name = Global.data.card.blue.sp.show_name
	description = Global.data.card.blue.sp.description.format([str(hit_value), str(default_count)])
	hint = Global.data.card.blue.sp.hint
	piece_type = Global.PieceType.SP

func _process(delta: float) -> void:
	if card_owner != null:
		count = 0
		count += Global.get_board_pieces().filter(filter_ally_piece).size()
		count += card_owner.grave.size()
		if (count != count_show):
			count_show = count
			var text = str(count)
			text = Global.set_font_color(text, Global.get_font_color(count, default_count))
			description = Global.data.card.blue.sp.description.format([str(hit_value), text])

func on_piece_set() -> void:
	super.on_piece_set()
	#攻擊隨機敵人
	for i in range(count):
		var enemy = get_random_enemy()
		attack_component.hit(enemy, hit_value - attack_component.atk)
		if not enemy == null:
			var beam = beam_scene.instantiate()
			var random_offset = Vector2(Global.rng.randi_range(-10, 10), Global.rng.randi_range(-10, 10))
			beam.start_position = Vector2(0, 0)
			beam.end_position = Vector2((enemy.location - location) * 80) + random_offset
			add_child(beam)
			await get_tree().create_timer(0.1).timeout
			beam.queue_free()
	refresh()
