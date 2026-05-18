extends Node
class_name Green

"""
#Note1：只有有效觸發的效果會進入觸發的佇列
#Note2：觸發好運/壞運預設會造成幸運值+1/-1
"""
#事件
enum EVENTS { SHIELD, DOUBLE_ATK, TRIGGER_ATTACK, MOVE, LUCKY_BOX, BLESSED, SHIELD_BREAK, HALF_HEALTH, HALF_ATK, STUNED, DOOMED }
#幸運
const lucky_events_weight := {
	EVENTS.SHIELD : 20,
	EVENTS.DOUBLE_ATK : 20,
	EVENTS.TRIGGER_ATTACK : 10,
	EVENTS.MOVE : 20,
	EVENTS.LUCKY_BOX : 10,
	EVENTS.BLESSED : 1,
}
#不幸
const unlucky_events_weight := {
	EVENTS.SHIELD_BREAK : 20,
	EVENTS.HALF_HEALTH : 20,
	EVENTS.HALF_ATK : 20,
	EVENTS.STUNED : 20,
	EVENTS.DOOMED : 1,
}
const LUCKY_BOX = preload("res://scenes/cards/token/lucky_box.tscn")
var shield_value : int = 4

func is_lucky(player: Player) -> bool:
	return Global.has_piece_on_board(Global.data.card.green.hero.show_name, player)

#幸運效果
func lucky_event(target: Piece, force: bool = false) -> void:
	if target.card_owner == null:
		return
	if not luck_is_trigger(target.card_owner) and not force:
		return
	do_event(target, lucky_events_weight)
	add_luck_buff(target.card_owner, 1)
	print("好運")

#不幸效果
func unlucky_event(target: Piece, force: bool = false) -> void:
	if target.card_owner == null:
		return
	if luck_is_trigger(target.card_owner) and not force:
		return
	do_event(target, unlucky_events_weight)
	add_luck_buff(target.card_owner, -1)
	print("不幸")

#隨機效果
func random_event(target: Piece) -> void:
	if target.card_owner == null:
		return
	if luck_is_trigger(target.card_owner):
		do_event(target, lucky_events_weight)
		add_luck_buff(target.card_owner, 1)
		print("好運")
	else:
		do_event(target, unlucky_events_weight)
		add_luck_buff(target.card_owner, -1)
		print("不幸")

#執行事件
func do_event(target: Piece, events_weight: Dictionary) -> void:
	var events: Dictionary = {}
	var total_weight: int = 0
	#篩選可能發生的事件並計算總權重
	for event: EVENTS in events_weight.keys():
		if is_valid_event(target, event):
			events[event] = events_weight[event]
			total_weight += events_weight[event]
	#在權重範圍內生成隨機數
	var random_value: int = Global.rng.randi_range(0, total_weight - 1)
	#根據隨機數找到對應的事件
	var cumulative_weight: int = 0
	for event: EVENTS in events.keys():
		cumulative_weight += events[event]
		if random_value < cumulative_weight:
			event_effect(target, event) #執行效果
			return
	return

#幸運buff
func get_luck_buff() -> Luck:
	var luck_buff: Luck = Luck.new()
	luck_buff.show_name = Global.data.buff.luck.name
	luck_buff.description = Global.data.buff.luck.description
	luck_buff.value = 50
	luck_buff.show_value = true
	return luck_buff

#增減幸運值
func add_luck_buff(player: Player, value: int) -> void:
	check_luck(player)
	var buff: Buff = player.buff_component.get_buff(Global.data.buff.luck.name)
	if buff.has_method("add_value"):
		buff.add_value(player, value)
		player.buff_component.show_buff()

#檢查對象幸運值
func check_luck(target: Player) -> int:
	if target == null:
		return 0
	if not target.buff_component:
		return 0
	if not target.buff_component.has_buff(Global.data.buff.luck.name):
		target.buff_component.add_buff(get_luck_buff())
	target.buff_component.show_buff()
	return target.buff_component.get_buff(Global.data.buff.luck.name).value

#確認是否觸發效果
func luck_is_trigger(player: Player, divided: int = 1) -> bool:
	var luck_value = Global.rng.randi_range(0, 100)
	if is_lucky(player):
		var new_luck_value = Global.rng.randi_range(0, 100)
		if new_luck_value < luck_value:
			luck_value = new_luck_value
	return luck_value < check_luck(player) / divided

#取得可觸發的事件
func is_valid_event(target: Piece, event: EVENTS) -> bool:
	match event:
		#護盾
		EVENTS.SHIELD:
			if target.get("health_component"):
				return true
		#攻擊力雙倍
		EVENTS.DOUBLE_ATK:
			if not target.attack_component or not target.buff_component:
				return false
			return target.attack_component.atk > 0
		#自動攻擊
		EVENTS.TRIGGER_ATTACK: 
			if not target.attack_component:
				return false
			return target.attack_component.atk > 0
		#移動
		EVENTS.MOVE:
			if not target.buff_component:
				return false
			return not target.buff_component.has_buff(Global.data.buff.move.name)
		#幸運箱
		EVENTS.LUCKY_BOX:
			return not target.piece_type == Global.PieceType.AP
		#祝福
		EVENTS.BLESSED:
			return true
		#破甲
		EVENTS.SHIELD_BREAK:
			var hp_break = target.get("health_component")
			if not hp_break:
				return false
			return hp_break.shield > 0
		#血量減半
		EVENTS.HALF_HEALTH:
			var hp_half = target.get("health_component")
			if not hp_half:
				return false
			return hp_half.health > 1
		#攻擊減半
		EVENTS.HALF_ATK:
			if not target.attack_component or not target.buff_component:
				return false
			return target.attack_component.atk > 0
		#暈眩
		EVENTS.STUNED:
			if not target.buff_component:
				return false
			return not target.buff_component.has_buff(Global.data.buff.stun.name)
		#災厄
		EVENTS.DOOMED:
			return true
	return false

#執行事件效果
func event_effect(target: Piece, event: EVENTS) -> void:
	match event:
		#護盾
		EVENTS.SHIELD:
			print("+護盾")
			target.shielded(shield_value, null)
		#攻擊力雙倍
		EVENTS.DOUBLE_ATK:
			print("+攻擊力雙倍")
			var attack_buff = AttackBuff.new()
			attack_buff.show_name = Global.data.buff.attack_buff.name
			attack_buff.description = Global.data.buff.attack_buff.description.format([str(target.attack_component.atk)])
			attack_buff.tag.append_array([Global.BuffTag.BUFF, Global.BuffTag.GREEN])
			attack_buff.value = target.attack_component.atk
			target.add_buff(attack_buff)
		#自動攻擊
		EVENTS.TRIGGER_ATTACK: 
			print("+自動攻擊")
			target.auto_attack()
		#移動
		EVENTS.MOVE:
			print("+移動")
			target.add_buff(Global.get_move_buff())
		#幸運箱
		EVENTS.LUCKY_BOX:
			print("+幸運箱")
			var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for i: Vector2i in directions:
				create_lucky_box(target.location + i)
		#祝福
		EVENTS.BLESSED:
			print("++祝福++")
			target.shielded(shield_value, null)
			var attack_buff = AttackBuff.new()
			attack_buff.show_name = Global.data.buff.attack_buff.name
			attack_buff.description = Global.data.buff.attack_buff.description.format([str(target.attack_component.atk)])
			attack_buff.tag.append_array([Global.BuffTag.BUFF, Global.BuffTag.GREEN])
			attack_buff.value = target.attack_component.atk
			target.add_buff(attack_buff)
			var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			for i: Vector2i in directions:
				create_lucky_box(target.location + i)
			target.auto_attack()
			target.add_buff(Global.get_move_buff())
		#破甲
		EVENTS.SHIELD_BREAK:
			print("-破甲")
			var hp_break = target.get("health_component")
			if hp_break:
				hp_break.shield = 0
		#血量減半
		EVENTS.HALF_HEALTH:
			print("-血量減半")
			var hp_half = target.get("health_component")
			if hp_half:
				hp_half.health -= hp_half.health / 2
		#攻擊減半
		EVENTS.HALF_ATK:
			print("-攻擊減半")
			var attack_debuff = AttackBuff.new()
			attack_debuff.show_name = Global.data.buff.attack_debuff.name
			attack_debuff.description = Global.data.buff.attack_debuff.description.format([str(target.attack_component.atk / 2)])
			attack_debuff.tag.append_array([Global.BuffTag.DEBUFF, Global.BuffTag.GREEN])
			attack_debuff.value = -target.attack_component.atk / 2
			target.add_buff(attack_debuff)
		#暈眩
		EVENTS.STUNED:
			print("-暈眩")
			target.add_buff(Global.get_stun_debuff())
		#災厄
		EVENTS.DOOMED:
			print("--災厄--")
			var attack_debuff = AttackBuff.new()
			attack_debuff.show_name = Global.data.buff.attack_debuff.name
			attack_debuff.description = Global.data.buff.attack_debuff.description.format([str(target.attack_component.atk / 2)])
			attack_debuff.tag.append_array([Global.BuffTag.DEBUFF, Global.BuffTag.GREEN])
			attack_debuff.value = -target.attack_component.atk / 2
			target.add_buff(attack_debuff)
			var hp_doom = target.get("health_component")
			if hp_doom:
				hp_doom.shield = 0
				hp_doom.health -= hp_doom.health / 2
			target.add_buff(Global.get_stun_debuff())

#生成幸運箱
func create_lucky_box(location: Vector2i) -> void:
	var box = LUCKY_BOX.instantiate()
	box.card_owner = null
	if Global.get_match_scene().add_piece_to_board(box, location):
		#給法坦盾
		for piece in Global.get_piece_on_board(Global.data.card.green.apt.show_name):
			piece.shielded(piece.buff_value, piece.buff_value)
