extends Node
class_name Red

var hero_name : String = Global.data.card.red.hero.show_name
var battle_fury_count = 6

#生成增益
func create_buff(buff_name: String, value: int) -> Buff:
	match buff_name:
		#攻擊
		Global.data.buff.attack_buff.name:
			var attack_buff = AttackBuff.new()
			attack_buff.show_name = Global.data.buff.attack_buff.name
			attack_buff.description = Global.data.buff.attack_buff.description.format([str(value)])
			attack_buff.tag.append_array([Global.BuffTag.BUFF, Global.BuffTag.RED])
			attack_buff.value = value
			return attack_buff
		#最大生命
		Global.data.buff.health_buff.name:
			var health_buff = HealthBuff.new()
			health_buff.show_name = Global.data.buff.health_buff.name
			health_buff.description = Global.data.buff.health_buff.description.format([str(value)])
			health_buff.tag.append_array([Global.BuffTag.BUFF, Global.BuffTag.RED])
			health_buff.value = value
			return health_buff
		#護甲
		Global.data.state.shield.name:
			var shield_buff = Shielded.new()
			shield_buff.show_name = Global.data.state.shield.name
			shield_buff.tag.append_array([Global.BuffTag.BUFF, Global.BuffTag.RED])
			shield_buff.duration = 1
			shield_buff.value = value
			return shield_buff
	return null

#給予增益
func add_buff(buff_name: String, value: int, piece: Piece) -> void:
	if not piece.buff_component:
		return
	var buff = piece.buff_component.get_buff(buff_name, [Global.BuffTag.RED])
	if buff == null:
		piece.add_buff(create_buff(buff_name, value))
	else:
		buff.add_value(piece, value)
	add_to_history(buff_name, value, piece.card_owner)
	return

#取得紅鑽石
func get_redsp(player: Player) -> Array:
	return Global.get_piece_on_board(Global.data.card.red.sp.show_name, player)

#給紅鑽石增益
func buff_redsp(buff_name: String, value: int, player: Player) -> void:
	for piece: Piece in get_redsp(player):
		add_buff(buff_name, value, piece)

#紀錄增益歷史資訊
func add_to_history(buff_name: String, value: int, player: Player) -> void:
	#加入增益欄
	var added_buff: Buff = player.buff_component.get_buff(buff_name, [Global.BuffTag.RED])
	if added_buff == null:
		added_buff = create_buff(buff_name, value)
		added_buff.show_value = true
		added_buff.duration = INF
		if added_buff.show_name == Global.data.state.shield.name:
			added_buff.icon_path = {"default": "res://img/UI/shield.png"}
		player.buff_component.add_buff(added_buff)
	else:
		added_buff.add_value(player, value)
	player.buff_component.show_buff()
	#戰鬥狂熱
	if not player.has_card(hero_name): #沒有英雄
		return
	var battle_buff: Buff = player.buff_component.get_buff(Global.data.buff.battle_fury.name)
	if battle_buff == null:
		battle_buff = BattleFury.new()
		battle_buff.show_name = Global.data.buff.battle_fury.name
		battle_buff.description = Global.data.buff.battle_fury.description.format([hero_name])
		battle_buff.value = 1
		battle_buff.show_value = true
		battle_buff.duration = INF
		player.buff_component.add_buff(battle_buff)
	else:
		battle_buff.add_value(player, 1)
	if not player.has_card_unseen(hero_name): #已在場上或手上則不累積
		battle_buff.value = 0
		player.buff_component.show_buff()
		return
	if battle_buff.value >= battle_fury_count:
		battle_buff.value = 0
		player.search_and_draw_card(hero_name)
		player.buff_component.show_buff()

func attack_buff(value: int, piece: Piece) -> void:
	add_buff(Global.data.buff.attack_buff.name, value, piece)
	buff_redsp(Global.data.buff.attack_buff.name, value, piece.card_owner)
	return

func buff_health(value: int, piece: Piece) -> void:
	add_buff(Global.data.buff.health_buff.name, value, piece)
	buff_redsp(Global.data.buff.health_buff.name, value, piece.card_owner)
	return

func shield_buff(value: int, piece: Piece) -> void:
	add_buff(Global.data.state.shield.name, value, piece)
	buff_redsp(Global.data.state.shield.name, value, piece.card_owner)
	return
