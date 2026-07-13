# P2-2 命中特效（佔位）：一圈快速擴散並淡出的閃光。見 04 §7.2/7.3。
class_name ImpactFlash
extends Node2D

const FILL := Color(1.0, 0.95, 0.6)
const DURATION := 0.20

var _ring: Polygon2D = null
var tint: Color = FILL          # P9-3：派別色（set_color 於 play 前設定）


func _ready() -> void:
	_ring = Polygon2D.new()
	_ring.name = "Ring"
	_ring.polygon = _circle(10.0, 16)
	_ring.color = tint
	add_child(_ring)


# P9-3：設定命中特效顏色（派別色）。play 前呼叫。
func set_color(c: Color) -> void:
	tint = c
	if _ring != null:
		_ring.color = c


# 播放閃光。instant=true 時不演出、直接消失。
func play(instant: bool) -> void:
	if instant:
		queue_free()
		return
	scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.6, 1.6), DURATION)
	tw.tween_property(self, "modulate:a", 0.0, DURATION)
	tw.chain().tween_callback(queue_free)


func _circle(radius: float, segments: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out
