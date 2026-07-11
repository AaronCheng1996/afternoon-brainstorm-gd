# P1-1 表現層事件（core 對外唯一輸出通道，見 docs/rebuild/04 §4、01 §10）。
# 注意：舊碼已有 class_name GameEvent（script/events/game_event.gd），
# 故 v2 版命名為 GameEventV2 以避免衝突（Phase 6 收編時再統一）。
class_name GameEventV2
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
	RESOURCE,  # {owner:String, kind:String, value:int}
}

var kind: int
var data: Dictionary


func _init(k: int, d: Dictionary = {}) -> void:
	kind = k
	data = d


static func attack(from: Vector2i, to: Vector2i, delay: float) -> GameEventV2:
	return GameEventV2.new(Kind.ATTACK, {"from": from, "to": to, "delay": delay})


static func hurt(at: Vector2i, delay: float, post_health: int) -> GameEventV2:
	return GameEventV2.new(Kind.HURT, {"at": at, "delay": delay, "post_health": post_health})


static func float_text(at: Vector2i, amount: int, delay: float) -> GameEventV2:
	return GameEventV2.new(Kind.FLOAT, {"at": at, "amount": amount, "delay": delay})


static func move(from: Vector2i, to: Vector2i) -> GameEventV2:
	return GameEventV2.new(Kind.MOVE, {"from": from, "to": to})


static func death(at: Vector2i, delay: float) -> GameEventV2:
	return GameEventV2.new(Kind.DEATH, {"at": at, "delay": delay})


static func spawn(at: Vector2i, card_id: String, owner: String) -> GameEventV2:
	return GameEventV2.new(Kind.SPAWN, {"at": at, "card_id": card_id, "owner": owner})


static func status(at: Vector2i, status_id: String, on: bool) -> GameEventV2:
	return GameEventV2.new(Kind.STATUS, {"at": at, "status_id": status_id, "on": on})


static func resource(owner: String, kind_str: String, value: int) -> GameEventV2:
	return GameEventV2.new(Kind.RESOURCE, {"owner": owner, "kind": kind_str, "value": value})
