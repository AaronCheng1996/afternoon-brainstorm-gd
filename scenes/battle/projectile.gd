# P2-2 投射物（佔位）：三角形箭矢，從槍口飛向目標，命中時回呼 on_hit。見 04 §7.2/7.3。
# 之後換美術：替換 _build 的幾何或改用 AnimatedSprite2D，飛行/命中介面不變。
class_name Projectile
extends Node2D

const FILL := Color(1.0, 0.85, 0.3)

var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var body := Polygon2D.new()
	body.name = "Body"
	# 指向 +x 的箭矢（launch 時以 look_at 對準目標）。
	body.polygon = PackedVector2Array([
		Vector2(13, 0), Vector2(-7, -6), Vector2(-2, 0), Vector2(-7, 6)])
	body.color = FILL
	add_child(body)


# 從 from_pos 飛到 to_pos。instant=true 時瞬間抵達並立即命中。
func launch(from_pos: Vector2, to_pos: Vector2, duration: float, on_hit: Callable, instant: bool) -> void:
	_build()
	global_position = from_pos
	if from_pos.distance_to(to_pos) > 0.01:
		look_at(to_pos)
	if instant or duration <= 0.0:
		global_position = to_pos
		if on_hit.is_valid():
			on_hit.call()
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "global_position", to_pos, duration)
	tw.finished.connect(func() -> void:
		if on_hit.is_valid():
			on_hit.call()
		queue_free())
