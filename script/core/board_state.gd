# P1-1 棋盤狀態：4x4 格子佔用（見 docs/rebuild/01 §1，座標 (0,0)–(3,3)）。
class_name BoardState
extends RefCounted

const SIZE: int = 4

var occupy: Dictionary = {}   # Vector2i -> bool


func _init() -> void:
	for x in SIZE:
		for y in SIZE:
			occupy[Vector2i(x, y)] = false


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < SIZE and p.y >= 0 and p.y < SIZE


func is_free(p: Vector2i) -> bool:
	return in_bounds(p) and not occupy[p]


func set_occupied(p: Vector2i, value: bool) -> void:
	if in_bounds(p):
		occupy[p] = value
