extends Control

const PLAYER = preload("res://scenes/Resource/player.tscn")
const CARD_DETAIL = preload("res://scenes/UI/card_detail.tscn")
const GROUP_BUTTON = preload("res://scenes/UI/group_button.tscn")
const CARD_ICON = preload("res://scenes/UI/card_icon.tscn")

@onready var players: Control = $Players
@onready var cards: Node2D = $CardList/Cards
@onready var temp: Node2D = $Decks/Temp
@onready var card_grid: GridContainer = $CardList/background/scroll_container/card_grid

@onready var btn_start: Button = $btn_start
@onready var message: Label = $Message
@onready var card_group: GridContainer = $CardList/card_group

@onready var select_highlight: ColorRect = $Decks/select_highlight
@onready var highlight := [$highlight_0, $highlight_1]
@onready var decks := [$Decks/deck_background_0, $Decks/deck_background_1, $Decks/full_deck_background_0, $Decks/full_deck_background_1]
@onready var btn_show_all_0: Button = $Decks/deck_background_0/btn_show_all_0
@onready var btn_show_all_1: Button = $Decks/deck_background_1/btn_show_all_1

var player_list := []
var current_turn : int = 1
var deck_show : int = 6
var select_highlight_offset : Vector2 = Vector2(-5, -5)
var player_offset : Vector2 = Vector2(52, 64)
var deck_col : int = 2
var icon_size : Vector2 = Vector2(62, 62)
var selected_group : GroupButton = null

#開始遊戲
func _ready() -> void:
	#建立玩家資料
	for i in range(2):
		var new_player = PLAYER.instantiate()
		new_player.id = i
		player_list.append(new_player)
		players.add_child(new_player)
		new_player.position = Vector2(0, 560 * i) + player_offset
		highlight[i].color = Global.player_color[i]
	#初始化牌組
	Global.board_dic = {}
	#建立選牌派別群組
	set_groups()
	refresh()

#建立派別分頁資訊
func set_groups() -> void:
	var group_all := []
	#取得各個派別
	for group in Global.card_groups:
		group_all.append_array(Global.card_groups[group])
		var group_data = Global.data.card[group]
		var new_group_button = GROUP_BUTTON.instantiate()
		card_group.add_child(new_group_button)
		#設定按鈕
		new_group_button.group = Global.card_groups[group]
		new_group_button.label_font_color = Color(group_data.color)
		new_group_button.set_text(group_data.name)
		new_group_button.group_selected.connect(_on_group_button_group_selected)
		if not selected_group:
			selected_group = new_group_button
			new_group_button.selected()
	#顯示所有派別
	var all_group_button = GROUP_BUTTON.instantiate()
	card_group.add_child(all_group_button)
	all_group_button.group = group_all
	all_group_button.label_font_color = Color.GRAY
	all_group_button.set_text("全部")
	all_group_button.group_selected.connect(_on_group_button_group_selected)

#切換派別頁面
func _on_group_button_group_selected(group: GroupButton) -> void:
	selected_group.unselected()
	load_card_grid(group.group)
	selected_group = group
	group.selected()

#刷新畫面資訊
func refresh() -> void:
	#選卡順序 先手玩家挑6張 -> 後首玩家挑12張 -> 先手玩家挑6張
	select_highlight.show()
	if player_list[1].deck.size() < Global.deck_size / 2:
		current_turn = 1
	elif player_list[0].deck.size() < Global.deck_size:
		current_turn = 0
	elif player_list[1].deck.size() < Global.deck_size:
		current_turn = 1
	else:
		select_highlight.hide()
		current_turn = -1
	#當前選牌玩家特效
	select_highlight.position = decks[current_turn].position + select_highlight_offset
	#當雙方選完牌組後才能開始遊戲
	if player_list[0].deck.size() == Global.deck_size and player_list[1].deck.size() == Global.deck_size:
		btn_start.disabled = false
	else:
		btn_start.disabled = true
	load_card_grid(selected_group.group)

#載入棋子選單
func load_card_grid(card_group: Array) -> void:
	#移除先前版面
	for child in cards.get_children():
		child.queue_free()
	for child in card_grid.get_children():
		child.queue_free()
	#列出每種棋子
	for card in card_group:
		#建立棋子
		var card_scene = load(card)
		var new_card : Card = card_scene.instantiate()
		cards.add_child(new_card)
		#建立棋子資料顯示
		var new_card_detail : CardDetail = CARD_DETAIL.instantiate()
		card_grid.add_child(new_card_detail)
		new_card_detail.show_card_detail(new_card)
		new_card_detail.card_selected.connect(_on_card_selected)
		#超過上限或已挑完排組
		if current_turn == -1:
			new_card_detail.show_shader()
			continue
		if not player_list[current_turn].deck_card_type.has(new_card.show_name): #紀錄玩家持有該棋子數量
			player_list[current_turn].deck_card_type[new_card.show_name] = 0
		if is_limit(player_list[current_turn], new_card):
			new_card_detail.show_shader()
		else:
			new_card_detail.hide_shader()
		

#開始遊戲
func _on_start_button_pressed() -> void:
	#生成該局種子碼
	Global.rng.randomize()
	Global.seed = Global.rng.randi_range(0, 999999)
	Global.rng.seed = Global.seed
	#洗牌
	for i in range(2):
		player_list[i].deck = Global.shuffle_deck(player_list[i].deck)
	#加載並切換到新場景
	var match_scene = preload("res://scenes/match.tscn").instantiate()
	match_scene.set_player(player_list)
	get_parent().add_child(match_scene)
	get_parent().remove_child(self)

#玩家選牌
func _on_card_selected(card: Card) -> void:
	if player_list[0].deck.size() >= Global.deck_size and player_list[1].deck.size() >= Global.deck_size: #雙方玩家手牌已滿
		message.pop_message(Global.data.pop_message.deck_full)
		return
	if not player_list[current_turn].deck_card_type.has(card.show_name): #紀錄玩家持有該棋子數量
		player_list[current_turn].deck_card_type[card.show_name] = 0
	if is_limit(player_list[current_turn], card): #該棋子數量已達上限
		message.pop_message(Global.data.pop_message.card_limit)
		return
	#將棋子新增至玩家牌組
	var new_card = card.duplicate()
	new_card.card_owner = player_list[current_turn]
	new_card.is_on_board = false
	player_list[current_turn].deck.append(new_card)
	player_list[current_turn].deck_card_type[card.show_name] += 1
	show_deck()

#是否已拿該牌種類的上限
func is_limit(player: Player, card: Card) -> bool:
	if card.card_type == Global.CardType.SPELL: #魔法牌
		return player.deck_card_type[card.show_name] >= Global.spell_limit
	if not card.piece_type == Global.PieceType.HERO: #非英雄牌
		return player.deck_card_type[card.show_name] >= Global.piece_limit
	if not Global.hero_mode:
		return true
	for card_in_deck: Card in player.deck: #英雄牌
		if card_in_deck.piece_type == Global.PieceType.HERO:
			return true
	return false

#顯示牌組
func show_deck() -> void:
	#清除原先內容
	for card in temp.get_children():
		card.queue_free()
	for deck in decks:
		for object in deck.get_children():
			if object is CardIcon:
				object.queue_free()
	#建立新牌圖示
	for player in range(player_list.size()): #每個玩家
		for i in range(player_list[player].deck.size()): #牌庫
			#產生臨時的棋子實體
			var temp_card: Card = player_list[player].deck[i].duplicate()
			temp.add_child(temp_card)
			#新增至牌組顯示
			var icon : CardIcon = CARD_ICON.instantiate()
			icon.player_num = player
			icon.index = i
			icon.show_name = temp_card.show_name
			#根據目前持有人進入哪個牌庫顯示
			if i < deck_show:
				icon.position = Vector2( icon_size.x * (i % deck_col), icon_size.y * (i / deck_col))
				decks[player].add_child(icon)
			else:
				icon.position = Vector2( icon_size.x * ((i - deck_show) % deck_col), icon_size.y * ((i - deck_show) / deck_col))
				decks[player + 2].add_child(icon)
			icon.icon.texture = temp_card.outfit_component.icon.texture
			icon.icon.hframes = temp_card.outfit_component.icon.hframes
			icon.icon.vframes = temp_card.outfit_component.icon.vframes
			icon.icon.frame = temp_card.outfit_component.icon.frame
			icon.remove.connect(on_icon_remove)
	refresh()

#移除棋子
func on_icon_remove(icon: CardIcon) -> void:
	player_list[icon.player_num].deck.pop_at(icon.index)
	player_list[icon.player_num].deck_card_type[icon.show_name] -= 1
	show_deck()

#展開/縮小牌組
func _on_show_all_1_pressed() -> void:
	if decks[3].visible:
		btn_show_all_1.text = ">"
		decks[3].hide()
	else:
		btn_show_all_1.text = "<"
		decks[3].show()
func _on_show_all_0_pressed() -> void:
	if decks[2].visible:
		btn_show_all_0.text = ">"
		decks[2].hide()
	else:
		btn_show_all_0.text = "<"
		decks[2].show()
