extends Node2D
class_name AttackComponent

signal on_hit(target: Piece)
signal on_kill(target: Piece)

#基礎攻擊與攻擊方式
@export var DEFAULT_ATK := 5
var atk : int
@export var ATK_PATTERN : Global.PatternNames

var grid_size = 4

func _ready() -> void:
	atk = DEFAULT_ATK

#發動攻擊
func hit(target: Piece, additonal_damage: int = 0) -> void:
	if target == null:
		return
	if target.is_dead:
		return
	if not target.targeted(): #對方被鎖定時的效果，可能無效此次攻擊
		return
	emit_signal("on_hit", target)
	if atk + additonal_damage > 0:
		if target.take_damaged(atk + additonal_damage, get_parent()):
			emit_signal("on_kill", target)

#發動攻擊
func attack(pieces: Array, additonal_damage: int = 0) -> void:
	if not pieces: #是否為null
		return
	pieces = pieces.filter(func(element: Piece): return !element.is_dead)
	if pieces.size() == 0: #是否存在敵方棋子
		return
	var attacker = get_parent()
	#最近/最遠
	var targets = []
	if ATK_PATTERN == Global.PatternNames.NEAREST:
		targets = find_nearest_target(attacker.location, pieces)
	elif ATK_PATTERN == Global.PatternNames.FAREST:
		targets = find_farest_target(attacker.location, pieces)
	#處理最近/最遠傷害
	if targets.size() > 0:
		var random_index = Global.rng.randi_range(0, targets.size() - 1)
		hit(targets[random_index], additonal_damage)
		return
	#AOE
	for piece: Piece in pieces:
		if in_attack_range(attacker.location, piece.location):
			hit(piece, additonal_damage)

#取得目標區域
func get_target_location(pieces: Array) -> Array:
	var target_location = []
	var attacker = get_parent()
	#最近/最遠
	var targets = []
	if ATK_PATTERN == Global.PatternNames.NEAREST:
		targets = find_nearest_target(attacker.location, pieces)
	elif ATK_PATTERN == Global.PatternNames.FAREST:
		targets = find_farest_target(attacker.location, pieces)
	if targets.size() > 0:
		for piece: Piece in targets:
			target_location.append(piece.location)
		return target_location
	#AOE
	for x in grid_size:
		for y in grid_size:
			if in_attack_range(attacker.location, Vector2i(x + 2, y + 2)):
				target_location.append(Vector2i(x + 2, y + 2))
	
	return target_location

#判斷是否在AOE範圍內
func in_attack_range(location, target_location) -> bool:
	var x = target_location.x
	var y = target_location.y
	match ATK_PATTERN:
		Global.PatternNames.CROSS: #十字
			return abs(x - location.x) + abs(y - location.y) == 1
		Global.PatternNames.CROSS_LARGE: #大十字
			return x == location.x or y == location.y
		Global.PatternNames.X: #X型
			return abs(x - location.x) == 1 and abs(y - location.y) == 1
		Global.PatternNames.X_LARGE: #大X型
			return abs(x - location.x) == abs(y - location.y)
		Global.PatternNames.NEARBY: #九宮格內
			return abs(x - location.x) <= 1 and abs(y - location.y) <= 1
		Global.PatternNames.ALL: #全圖
			return true
		Global.PatternNames.NONE: #無
			return false
	return false

#尋找目標最近單位
func find_nearest_target(location, pieces: Array) -> Array:
	var target = INF
	var distances = []
	distances.resize(pieces.size())
	distances.fill(0)
	#找出最小值
	for i in range(pieces.size()):
		var distance = abs(pieces[i].location.x - location.x) + abs(pieces[i].location.y - location.y)
		distances[i] = distance #紀錄每個目標的距離
		#找出最小值
		if distance < target:
			target = distance
	#選出最小等距的目標
	var result = []
	for i in range(pieces.size()):
		if distances[i] == target:
			result.append(pieces[i])
	return result
#尋找目標最遠單位
func find_farest_target(location, pieces: Array) -> Array:
	var target = 0
	var distances = []
	distances.resize(pieces.size())
	distances.fill(0)
	#找出最大值
	for i in range(pieces.size()):
		var distance = abs(pieces[i].location.x - location.x) + abs(pieces[i].location.y - location.y)
		distances[i] = distance #紀錄每個目標的距離
		#找出大值
		if distance > target:
			target = distance
	#選出最大等距的目標
	var result = []
	for i in range(pieces.size()):
		if distances[i] == target:
			result.append(pieces[i])
	return result
