extends Piece
class_name GreenLF

var green = preload("res://script/cards/green/green.gd").new()
var beam_scene = preload("res://scenes/attack/beam_attack.tscn")

func _init() -> void:
	show_name = Global.data.card.green.lf.show_name
	description = Global.data.card.green.lf.description.format([str(4)])
	hint = Global.data.card.green.lf.hint
	piece_type = Global.PieceType.LF

func refresh() -> void:
	if attack_component:
		var text = str(attack_component.atk * 2)
		text = Global.set_font_color(text, Global.get_font_color(attack_component.atk, attack_component.DEFAULT_ATK))
		description = Global.data.card.green.lf.description.format([text])
	super.refresh()

func _on_attack_component_on_kill(target: Piece) -> void:
	if target.show_name == Global.data.card.spell_and_token.lucky_box.show_name:
		var enemy = get_random_enemy()
		if not enemy == null:
			var beam = beam_scene.instantiate()
			var random_offset = Vector2(Global.rng.randi_range(-10, 10), Global.rng.randi_range(-10, 10))
			beam.start_position = Vector2(0, 0)
			beam.end_position = Vector2((enemy.location - location) * 80) + random_offset
			add_child(beam)
			await get_tree().create_timer(0.1).timeout
			beam.queue_free()
		attack_component.hit(enemy, attack_component.atk)
		#機率返刀
		if green.luck_is_trigger(card_owner, 2):
			if Global.DEBUG:
				print("[DEBUG] 觸發返刀")
			card_owner.add_attack_count(1)
