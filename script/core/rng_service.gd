# P1-1 隨機服務：一局一顆種子，所有隨機經由它（決定性可測）。
# 見 docs/rebuild/00 決策 D4：不追求與 Python 跨引擎序列一致，規則層對齊即可。
class_name RngService
extends RefCounted

var seed_value: int = 0
var _rng := RandomNumberGenerator.new()


func _init(seed_val: int = 0) -> void:
	seed_value = seed_val
	_rng.seed = seed_val


# 含端點的整數亂數。
func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


# [0,1) 浮點亂數。
func randf() -> float:
	return _rng.randf()


# 從陣列隨機取一元素（空陣列回 null）。
func choice(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]


# 原地洗牌（Fisher-Yates，使用注入的種子）。
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
