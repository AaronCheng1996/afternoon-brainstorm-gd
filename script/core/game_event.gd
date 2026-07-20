# P1-1 表現層事件（core 對外唯一輸出通道，見 docs/rebuild/04 §4、01 §10）。
class_name GameEvent
extends RefCounted

enum Kind {
	ATTACK,    # {from:Vector2i, to:Vector2i, delay:float}
	HURT,      # {at:Vector2i, delay:float, post_health:int}
	FLOAT,     # {at:Vector2i, amount:int, delay:float}
	MOVE,      # {from:Vector2i, to:Vector2i}
	DEATH,     # {at:Vector2i, delay:float}
	SPAWN,     # {at:Vector2i, card_id:String, owner:String}
	CAST,      # {at:Vector2i, kind:String}
	STATUS,    # {at:Vector2i, status_id:String, on:bool}
}

var kind: int
var data: Dictionary


func _init(k: int, d: Dictionary = {}) -> void:
	kind = k
	data = d


static func attack(from: Vector2i, to: Vector2i, delay: float) -> GameEvent:
	return GameEvent.new(Kind.ATTACK, {"from": from, "to": to, "delay": delay})


static func hurt(at: Vector2i, delay: float, post_health: int) -> GameEvent:
	return GameEvent.new(Kind.HURT, {"at": at, "delay": delay, "post_health": post_health})


static func float_text(at: Vector2i, amount: int, delay: float) -> GameEvent:
	return GameEvent.new(Kind.FLOAT, {"at": at, "amount": amount, "delay": delay})


static func move(from: Vector2i, to: Vector2i) -> GameEvent:
	return GameEvent.new(Kind.MOVE, {"from": from, "to": to})


static func death(at: Vector2i, delay: float) -> GameEvent:
	return GameEvent.new(Kind.DEATH, {"at": at, "delay": delay})


static func spawn(at: Vector2i, card_id: String, owner: String) -> GameEvent:
	return GameEvent.new(Kind.SPAWN, {"at": at, "card_id": card_id, "owner": owner})


static func status(at: Vector2i, status_id: String, on: bool) -> GameEvent:
	return GameEvent.new(Kind.STATUS, {"at": at, "status_id": status_id, "on": on})
