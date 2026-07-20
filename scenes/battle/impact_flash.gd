# P2-2 命中特效（佔位）：一圈快速擴散並淡出的閃光。見 04 §7.2/7.3。
# P14-6：外觀與節奏參數改 @export（**預設值＝改版前的常數**，畫面不變）——美術可直接開
# `scenes/battle/impact_flash.tscn` 調，不必讀程式。
class_name ImpactFlash
extends Node2D

@export_group("外觀")
## 閃光填色。實際播放時通常被 `set_color`（派別色，P9-3）覆寫；這是未指定時的底色。
@export var fill_color: Color = Color(1.0, 0.95, 0.6)
## 圓環半徑（像素）與邊數。
@export var ring_radius: float = 10.0
@export var ring_segments: int = 16
@export_group("")

@export_group("節奏")
## 擴散＋淡出的時間（秒）。
@export var duration: float = 0.20
## 起始／結束縮放。
@export var scale_from: float = 0.3
@export var scale_to: float = 1.6
@export_group("")

var _ring: Polygon2D = null


func _ready() -> void:
	_ring = Polygon2D.new()
	_ring.name = "Ring"
	_ring.polygon = _circle(ring_radius, maxi(3, ring_segments))
	_ring.color = fill_color
	add_child(_ring)


# P9-3：設定命中特效顏色（派別色）。play 前呼叫。
func set_color(c: Color) -> void:
	fill_color = c
	if _ring != null:
		_ring.color = c


# 播放閃光。instant=true 時不演出、直接消失。
func play(instant: bool) -> void:
	if instant:
		queue_free()
		return
	scale = Vector2(scale_from, scale_from)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(scale_to, scale_to), duration)
	tw.tween_property(self, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(queue_free)


func _circle(radius: float, segments: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		out.append(Vector2(cos(a), sin(a)) * radius)
	return out
