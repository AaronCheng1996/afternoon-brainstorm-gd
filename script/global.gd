extends Node

#region 基本參數
#規則
var deck_size : int = 12
const hand_size : int = 8
var piece_limit : int = 2
var hero_mode : bool = true
var spell_limit : int = 3
var first_turn : int = 1
var starter_hand_count : int = 3
#棋子
enum CardType {PIECE, SPELL, TOKEN}
enum PieceType {ADC, AP, APT, ASS, HF, LF, SP, TANK, HERO, OTHER}
enum TargetType {NONE, BOARD, PIECE}
const card_groups = {
	"white": [
		"res://scenes/cards/white/adc.tscn",
		"res://scenes/cards/white/ap.tscn",
		"res://scenes/cards/white/apt.tscn",
		"res://scenes/cards/white/ass.tscn",
		"res://scenes/cards/white/lf.tscn", 
		"res://scenes/cards/white/hf.tscn",
		"res://scenes/cards/white/sp.tscn", 
		"res://scenes/cards/white/tank.tscn",
		"res://scenes/cards/white/hero.tscn",
	],
	"red": [
		"res://scenes/cards/red/adc.tscn",
		"res://scenes/cards/red/ap.tscn",
		"res://scenes/cards/red/apt.tscn",
		"res://scenes/cards/red/ass.tscn",
		"res://scenes/cards/red/lf.tscn",
		"res://scenes/cards/red/hf.tscn",
		"res://scenes/cards/red/sp.tscn",
		"res://scenes/cards/red/tank.tscn",
		"res://scenes/cards/red/hero.tscn",
	],
	"green": [
		"res://scenes/cards/green/adc.tscn",
		"res://scenes/cards/green/ap.tscn",
		 "res://scenes/cards/green/apt.tscn",
		 "res://scenes/cards/green/ass.tscn",
		 "res://scenes/cards/green/lf.tscn",
		 "res://scenes/cards/green/hf.tscn", 
		"res://scenes/cards/green/sp.tscn", 
		"res://scenes/cards/green/tank.tscn",
		"res://scenes/cards/green/hero.tscn",
	],
	"blue": [
		"res://scenes/cards/blue/adc.tscn",
		"res://scenes/cards/blue/ap.tscn",
		 "res://scenes/cards/blue/apt.tscn",
		 "res://scenes/cards/blue/ass.tscn",
		 "res://scenes/cards/blue/lf.tscn",
		 "res://scenes/cards/blue/hf.tscn", 
		"res://scenes/cards/blue/sp.tscn", 
		"res://scenes/cards/blue/tank.tscn",
		"res://scenes/cards/blue/hero.tscn",
	],
	"orange": [
		"res://scenes/cards/orange/adc.tscn",
		"res://scenes/cards/orange/ap.tscn",
		"res://scenes/cards/orange/apt.tscn",
		"res://scenes/cards/orange/ass.tscn",
		"res://scenes/cards/orange/lf.tscn",
		"res://scenes/cards/orange/hf.tscn", 
		"res://scenes/cards/orange/sp.tscn", 
		"res://scenes/cards/orange/tank.tscn",
		"res://scenes/cards/orange/hero.tscn"
	],
	"moss": [
		"res://scenes/cards/moss/adc.tscn",
		"res://scenes/cards/moss/ap.tscn",
		 "res://scenes/cards/moss/apt.tscn",
		 "res://scenes/cards/moss/ass.tscn",
		 "res://scenes/cards/moss/lf.tscn",
		 "res://scenes/cards/moss/hf.tscn", 
		"res://scenes/cards/moss/sp.tscn", 
		"res://scenes/cards/moss/tank.tscn",
		"res://scenes/cards/moss/hero.tscn"
	],
	"purple": [
		"res://scenes/cards/purple/ap.tscn",
		"res://scenes/cards/purple/apt.tscn",
		"res://scenes/cards/purple/ass.tscn",
		"res://scenes/cards/purple/hf.tscn",
		"res://scenes/cards/purple/tank.tscn",
		
	],
	"spell_and_token": [
		"res://scenes/cards/spell/cubes.tscn",
		"res://scenes/cards/spell/heal.tscn",
		"res://scenes/cards/spell/move_spell.tscn"
	]
}
#攻擊
enum PatternNames {CROSS, CROSS_LARGE, X, X_LARGE, NEARBY, NEAREST, FAREST, ALL, NONE}
#buff
enum BuffTag {DEBUFF, BUFF, STUN, MOVE, RED, GREEN, ORANGE}
const buff_icon = {
	"stun": {
		"default": "res://img/UI/buff/stun.png",
		"mini": "res://img/UI/buff_mini/stun_mini.png"
	},
	"sleep": {
		"default": "res://img/UI/buff/sleep.png",
		"mini": "res://img/UI/buff_mini/sleep_mini.png"
	},
	"attack_buff": {
		"default": "res://img/UI/buff/attack_buff.png",
		"mini": "res://img/UI/buff_mini/attack_buff_mini.png"
	},
	"attack_debuff": {
		"default": "res://img/UI/buff/attack_debuff.png",
		"mini": "res://img/UI/buff_mini/attack_debuff_mini.png"
	},
	"health_buff": {
		"default": "res://img/UI/buff/health_buff.png",
		"mini": "res://img/UI/buff_mini/health_buff_mini.png"
	},
	"health_debuff": {
		"default": "res://img/UI/buff/health_debuff.png",
		"mini": "res://img/UI/buff_mini/health_debuff_mini.png"
	},
	"move": {
		"default": "res://img/UI/buff/move.png",
		"mini": "res://img/UI/buff_mini/move_mini.png"
	},
	"rage": {
		"default": "res://img/UI/buff/rage.png",
		"mini": "res://img/UI/buff_mini/rage_mini.png"
	},
	"blue_charge": {
		"default": "res://img/UI/buff/blue_charge.png",
		"mini": "res://img/UI/buff_mini/blue_charge_mini.png"
	},
	"rune": {
		"default": "res://img/UI/buff/rune.png",
		"mini": "res://img/UI/buff_mini/rune_mini.png"
	},
	"luck": {
		"default": "res://img/UI/buff/luck.png",
	},
	"bad_luck": {
		"default": "res://img/UI/buff/bad_luck.png",
	},
	"battle_fury": {
		"default": "res://img/UI/buff/battle_fury.png",
	},
	"death_door": {
		"default": "res://img/UI/buff/death_door.png",
		"mini": "res://img/UI/buff_mini/death_door_mini.png"
	}
}
#顯示
var default_score_color : Color = Color.WHITE
var player_color := [Color.RED, Color.BLUE]
var player_color_dark := [Color("#3c0004"), Color("#002b4c")]
var ready_color := Color.ORANGE
#endregion

#region 通用變數
#除錯模式：Debug Build 下自動開啟，也可手動設為 true
var DEBUG : bool = OS.is_debug_build()
#種子碼、隨機數產生器
var seed : int
var rng = RandomNumberGenerator.new()
#遊戲敘述
var data := {}
#玩家資訊
var player_list := []
var winner : int = -1
#棋盤資訊
var grid_size : int = 4
var board_dic := {}
#endregion

#region 通用函式
func _ready() -> void:
	var open_err = FileAccess.open("res://setting/description.json", FileAccess.READ)
	var json_object = JSON.new()
	var parse_err = json_object.parse(open_err.get_as_text())
	data = json_object.get_data()

#Fisher-Yates洗牌
func shuffle_deck(deck: Array) -> Array:
	var shuffled_deck = deck.duplicate()
	for i in range(shuffled_deck.size() - 1, 0, -1):
		#使用 rng 生成隨機索引
		var j = Global.rng.randi_range(0, i)
		var temp_piece = shuffled_deck[i]
		shuffled_deck[i] = shuffled_deck[j]
		shuffled_deck[j] = temp_piece
	return shuffled_deck
#region 場面
#取得對戰場景節點
func get_match_scene() -> Node:
	return get_tree().get_nodes_in_group("board")[0]
#取得對手資訊
func get_opponent(player: Player) -> Player:
	var player_list = get_tree().get_nodes_in_group("board")[0].player_list
	return player_list[(player.id + 1) % 2]
#取得場上所有棋子
func get_board_pieces() -> Array:
	var pieces = []
	for v in board_dic.values():
		if not v is int:
			pieces.append(v)
	return pieces
#取得顯示的牌
func get_show_pieces(player: Player) -> Array:
	var result = []
	result.append_array(player.hand)
	result.append_array(get_board_pieces().filter(func(element):
		if element.card_owner == null:
			return false
		return element.card_owner.id == player.id
	))
	return result
#是否有特定牌
func has_piece_on_board(piece_name: String, player: Player = null) -> bool:
	for piece: Card in get_board_pieces():
		if not piece.show_name == piece_name:
			continue
		if player == null:
			return true
		elif piece.card_owner == player:
			return true
	return false
#取得特定牌
func get_piece_on_board(piece_name: String, player: Player = null) -> Array:
	var result = []
	for piece: Card in get_board_pieces():
		if not piece.show_name == piece_name:
			continue
		if player == null:
			result.append(piece)
		elif piece.card_owner == player:
			result.append(piece)
	return result
#取得所有牌
func get_all_pieces(player: Player) -> Array:
	var result = []
	result.append_array(player.deck)
	result.append_array(player.grave)
	result.append_array(player.hand)
	result.append_array(get_board_pieces().filter(func(element):
		if element.card_owner == null:
			return false
		return element.card_owner.id == player.id
	))
	return result
#取得空格
func get_empty_slots() -> Array:
	var result = []
	for location: Vector2i in board_dic.keys():
		if board_dic[location] is int:
			result.append(location)
	return result
#取得隨機空格
func get_random_empty_slot() -> Vector2i:
	var empty_slots = get_empty_slots()
	if empty_slots.size() > 0:
		var random_index = rng.randi_range(0, empty_slots.size() - 1)
		return empty_slots[random_index]
	return Vector2i(0, 0)
#endregion

#region 通用
#取得暈眩buff
func get_stun_debuff() -> Stun:
	var stun_debuff = Stun.new()
	stun_debuff.show_name = data.buff.stun.name
	stun_debuff.description = data.buff.stun.description
	stun_debuff.tag.append_array([BuffTag.DEBUFF, BuffTag.STUN])
	stun_debuff.icon_path = buff_icon.stun
	stun_debuff.duration = 1
	return stun_debuff

#取得移動buff
func get_move_buff() -> Move:
	var move_buff: Move = Move.new()
	move_buff.show_name = data.buff.move.name
	move_buff.description = data.buff.move.description
	move_buff.tag.append_array([BuffTag.BUFF, BuffTag.MOVE])
	move_buff.duration = 1
	return move_buff

#取得狂暴buff
func get_rage_buff() -> Rage:
	var rage_buff: Rage = Rage.new()
	rage_buff.show_name = data.buff.rage.name
	rage_buff.description = data.buff.rage.description
	rage_buff.tag.append_array([BuffTag.BUFF])
	rage_buff.duration = 1
	return rage_buff

#取得消逝的移動牌
func get_move_spell(player: Player) -> void:
	var move = load("res://scenes/cards/spell/move_spell_expire.tscn").instantiate()
	move.card_owner = player
	move.is_on_board = false
	player.get_card(move)

#有人移動
func piece_moved(piece_moved: Piece) -> void:
	#觸發友方橘色效果
	var trigger_list = [
		Global.data.card.orange.apt.show_name, 
		Global.data.card.orange.sp.show_name,
		Global.data.card.orange.hero.show_name
	]
	for piece: Card in get_all_pieces(piece_moved.card_owner):
		if trigger_list.has(piece.show_name):
			piece.trigger_effect(piece_moved)
	#觸發敵方效果
	var trigger_list_2 = [
		Global.data.card.purple.tank.show_name
	]
	for piece: Card in get_show_pieces(get_opponent(piece_moved.card_owner)):
		if trigger_list_2.has(piece.show_name):
			piece.trigger_effect(piece_moved)
#endregion
#region 文字特效
#置中文字
func set_font_center(text: String) -> String:
	return "[center]{0}[/center]".format([text])
#文字大小
func set_font_size(text: String, size: int) -> String:
	return "[font_size={0}]{1}[/font_size]".format([str(size), text])
#文字顏色
func set_font_color(text: String, color: Color) -> String:
	return "[color={0}]{1}[/color]".format([color.to_html(), text])
#根據數值選擇文字顏色
func get_font_color(value: int, default_value: int) -> Color:
	if value > default_value:
		return Color.GREEN
	elif value < default_value:
		return Color.RED
	return Color.WHITE
func get_attack_icon(size = null) -> String:
	if size:
		return "[img=" + size + "]res://img/UI/sword.png[/img]"
	return "[img]res://img/UI/sword.png[/img]"
func get_health_icon(size = null) -> String:
	if size:
		return "[img=" + size + "]res://img/UI/heart.png[/img]"
	return "[img]res://img/UI/heart.png[/img]"
#endregion
#region 圖片特效
func change_color(picture: Sprite2D, origin: Color, new_color: Color) -> void:
	var image: Image = picture.texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) == origin:
				image.set_pixel(x, y, new_color)
	var new_texture = ImageTexture.create_from_image(image)
	picture.texture = new_texture
#endregion
#endregion
