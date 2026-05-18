extends Node2D
class_name BeamAttack

@onready var beam: Line2D = $beam
@onready var start_point: Sprite2D = $start_point
@onready var end_point: Sprite2D = $end_point

var start_position = Vector2(0, 0)
var end_position = Vector2(0, 0)
var offset = Vector2(9, 0)

func _ready() -> void:
	beam.clear_points()
	beam.add_point(start_position)
	beam.add_point(end_position)
	
	start_point.position = start_position
	end_point.position = end_position
	
	var direction = end_position - start_position
	var angle = direction.angle()
	offset = offset.rotated(angle)
	beam.position -= offset
	start_point.rotate(angle)
	end_point.rotate(angle)

func on_beam_animation_complete():
	beam.visible = false
	beam.queue_free()
