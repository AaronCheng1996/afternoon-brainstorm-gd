extends Control

@onready var board: ColorRect = $Board
@onready var tilemap: TileMap = $Board/TileMap
@onready var pieces_in_hand: Node2D = $Pieces
@onready var pieces_on_board: Node2D = $Board/Pieces
@onready var p0_end_button: Button = $Board/btn_turn_end_0
@onready var p1_end_button: Button = $Board/btn_turn_end_1
@onready var highlight := [$Board/highlight_0, $Board/highlight_1]
@onready var score_label: RichTextLabel = $Board/score_label
@onready var score_predict:= [$Board/score_predict_0, $Board/score_predict_1]
@onready var card_detail: CardDetail = %CardDetail
@onready var message: Label = $Message
@onready var players: Control = $Players
@onready var btn_show_all: CheckButton = $btn_show_all

"""
#note1：player0遊戲中顯示為player2，為上方玩家；player1遊戲中顯示為player1，下方玩家。
#note2：由player1先手。
"""

var player_list := []
#選定的棋子
var card_selected : Card = null
var mouse_on_attack : bool = false
var mouse_in_icon : Card = null
#當前回合
var current_turn : int = Global.first_turn
var current_player : int = Global.first_turn
#分數
var score_size : int = 60
var score_predict_size : int = 40
var score_color : Color = Global.default_score_color
var score : int = 0
#顯示所有棋子資訊
var always_show : bool = false
#移動模式
var move_mode_on : bool = false

#region 流程
#起始設定
func _ready() -> void:
	if not player_list.size() == 2: #確認玩家是否正常載入，若無則回到主頁
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	setup_player() #設定玩家資訊
	game_start_effect() #遊戲開始能力
	draw_starter_hand() #抽起手牌
	create_board_dic()
	start_turn(player_list[current_player]) #開始回合

#時刻執行
func _process(delta: float) -> void:
	detail_display() #棋子資訊顯示
	tilemap_display() #棋盤格子顯示
	score_display() #計分板顯示

#回合開始
func start_turn(player: Player) -> void:
	tilemap.current_player = player.id 
	turn_change_display() #切換回合特效
	piece_turn_start_effect() #棋子回合開始效果
	player.draw_card() #抽牌
	player.add_attack_count(1) #獲得一次攻擊次數

#回合結束
func end_turn() -> void:
	count_score() #計分
	if abs(score) >= 10: #得分超過 10 則獲勝
		deal_win()
		return
	piece_turn_end_effect() #棋子回合結束效果
	deal_card_expire() #處理手牌消逝
	select_piece(null) #解除所有鎖定
	#換邊開始回合
	current_turn += 1
	current_player = current_turn % 2
	start_turn(player_list[current_player])
#endregion

#region 流程工具
#(給deck_build時外部呼叫)設定雙方牌組
func set_player(new_player_list: Array) -> void:
	player_list = new_player_list

func setup_player() -> void:
	for player: Player in player_list:
		player.get_parent().remove_child(player)
		players.add_child(player)
		player.player_draw_card.connect(on_draw_card)
		player.player_discard_card.connect(_on_discard)
		player.player_win.connect(win)

func game_start_effect() -> void:
	for player: Player in player_list:
		for card: Card in player.deck:
			card.on_game_start()

#抽起手牌
func draw_starter_hand() -> void:
	#抽上起手牌
	for i in range(Global.starter_hand_count):
		for player in player_list:
			player.draw_card()
	#後手額外一張
	player_list[(current_player + 1) % 2].draw_card()
	
#生成棋盤陣列
func create_board_dic() -> void:
	for x in Global.grid_size:
		for y in Global.grid_size:
			Global.board_dic[Vector2i(x + 2, y + 2)] = 0
	tilemap.tile_selected.connect(_on_tile_clicked)

#顯示被選取的詳細資料
func detail_display() -> void:
	if mouse_in_icon == null:
		card_detail.show_card_detail(card_selected)
	else:
		card_detail.show_card_detail(mouse_in_icon)

#網格顯示處理
func tilemap_display() -> void:
	tilemap.reset(1)
	if card_selected:
		if move_mode_on: #移動模式
			tilemap.highlight_valid_tiles(card_selected.get_move_location())
		if mouse_on_attack: #滑鼠在攻擊上
			tilemap.highlight_attack_tiles(card_selected.get_target_location())
		if card_selected.card_type == Global.CardType.SPELL: #選定魔法牌
			if card_selected.card_owner.id == current_player:
				tilemap.highlight_valid_tiles(card_selected.get_valid_location())

#得分預測處理
func score_display() -> void:
	for player in range(player_list.size()):
		var score : int = 0
		for piece: Piece in Global.get_board_pieces():
			score += piece.get_score(player)
		var color : Color
		if player == current_player:
			color = Global.player_color[player]
		else:
			color = Global.player_color_dark[player]
		score_predict[player].text = Global.set_font_center(Global.set_font_color(Global.set_font_size("(+{0})".format([str(abs(score))]), score_predict_size), color))

#抽牌
func on_draw_card(player: Player, card: Card) -> void:
	pieces_in_hand.add_child(card)
	#設定外觀與連結
	if card.outfit_component:
		card.outfit_component.set_player_effect(player.id)
		card.outfit_component.card_selected.connect(_on_card_selected)
		card.outfit_component.piece_attack.connect(_on_piece_attack)
		card.outfit_component.piece_move_pressed.connect(_on_piece_move_pressed)
		card.outfit_component.mouse_in_icon.connect(_on_mouse_in_icon)
		card.outfit_component.mouse_out_icon.connect(_on_mouse_out_icon)
		card.outfit_component.mouse_in_attack.connect(_on_mouse_in_attack)
		card.outfit_component.mouse_out_attack.connect(_on_mouse_out_attack)
		card.outfit_component.spell_cast.connect(_on_spell_cast)
	if card.card_type == Global.CardType.SPELL:
		card.add_piece_to_board.connect(add_piece_to_board)
		card.leave_hand.connect(show_hand)
	else:
		card.piece_die.connect(_on_piece_die)
	card.on_draw()
	card.refresh()
	show_hand(player)

#顯示手牌
func show_hand(player: Player) -> void:
	if not card_selected == null:
		if not is_on_board(card_selected.location):
			select_piece(null)
	for i in range(player.hand.size()):
		player.hand[i]
		var location = Vector2(i, player.id * 7)
		player.hand[i].position = tilemap.map_to_local(location)
		player.hand[i].location = location

#切換回合時的特效
func turn_change_display() -> void:
	highlight[current_player].color = Global.player_color[current_player]
	highlight[(current_player + 1) % 2].color = Global.player_color_dark[(current_player + 1) % 2]
	p0_end_button.disabled = current_player == 1
	p1_end_button.disabled = current_player == 0

#執行棋子回合開始效果
func piece_turn_start_effect() -> void:
	var temp_pieces = pieces_on_board.get_children()
	for piece in temp_pieces:
		if not piece: #有些棋子執行期間可能死亡
			continue
		piece.on_turn_start(current_player)

#執行棋子回合結束效果
func piece_turn_end_effect() -> void:
	var temp_pieces = pieces_on_board.get_children()
	for piece in temp_pieces:
		if not piece: #有些棋子執行期間可能死亡
			continue
		#棋子執行回合結束效果
		piece.on_turn_end(current_player)

#處理手上棋子消逝
func deal_card_expire() -> void:
	var n : int = player_list[current_player].hand.size()
	for i in range(n):
		var card = player_list[current_player].hand[n - 1 - i]
		if not card.card_type == Global.CardType.SPELL:
			continue
		if card.expirable:
			card.expire()

#計分
func count_score() -> void:
	var temp_pieces = pieces_on_board.get_children()
	for piece in temp_pieces:
		score += piece.get_score(current_player)
	#計分板顏色
	if score < 0:
		score_color = Global.player_color[0]
	elif score > 0:
		score_color = Global.player_color[1]
	else:
		score_color = Global.default_score_color
	score_label.text = Global.set_font_center(Global.set_font_color(Global.set_font_size(str(abs(score)), score_size), score_color))

#勝利
func deal_win() -> void:
	var winner = -1
	if score > 0:
		winner = 0
	else:
		winner = 1
	win(winner)
	

func win(winner: int) -> void:
	#加載並切換到新場景
	var end_scene = preload("res://scenes/end.tscn").instantiate()
	end_scene.set_winner(winner)
	get_parent().add_child(end_scene)
	get_parent().remove_child(self)
#endregion

#region 觸發
#選取棋子
func _on_card_selected(card: Card) -> void:
	if move_mode_on:
		move_mode_on = false
	if card_selected == null: #沒選定
		select_piece(card)
		return
	if card_selected == card: #點選已選定棋子 = 取消選定
		select_piece(null)
		return
	if card_selected.card_type == Global.CardType.SPELL: #選定的是魔法
		if card_selected.card_owner.id == current_player: #自己的魔法
			if not is_on_board(card.location): #選擇另一張手牌
				select_piece(card)
				return
			if not card_selected.cast(card.location): #施放
				message.pop_message(Global.data.pop_message.invalid_cast) #施放失敗
			select_piece(null)
			return
	#選定棋子或衍生物，改成選定目標
	select_piece(card)

#選取格子
func _on_tile_clicked(location: Vector2i) -> void:
	if not card_selected: #沒有先選定棋子
		return
	if card_selected.location == location: #原地
		return
	if card_selected.card_type == Global.CardType.SPELL: #魔法牌
		if not card_selected.cast(location):
			message.pop_message(Global.data.pop_message.invalid_cast) #施放失敗
		return
	if not is_on_board(card_selected.location): #從手上
		if is_on_board(location): #到場上
			move_piece_to_board(card_selected, location)
	if move_mode_on: #移動模式
		move_piece(card_selected, location)
	#點空地：解除選定
	card_selected.hide_select_effect()
	card_selected = null
	tilemap.card_select = null

#棋子發動攻擊
func _on_piece_attack(piece: Piece) -> void:
	if piece.card_owner.attack_count <= 0: #檢查是否有
		message.pop_message(Global.data.pop_message.no_attack)
		return
	piece.card_owner.add_attack_count(-1) #消耗一次攻擊次數
	#發動攻擊
	piece.attack()

#施放魔法 (僅限無目標)
func _on_spell_cast(card: Card) -> void:
	if not card.cast(Vector2i(-100, -100)):
		message.pop_message(Global.data.pop_message.invalid_cast)

#棋子按下移動鍵
func _on_piece_move_pressed(piece: Piece) -> void:
	move_mode_on = !move_mode_on

#滑鼠在棋子圖示上，顯示詳細資料
func _on_mouse_in_icon(card: Card) -> void:
	mouse_in_icon = card

#滑鼠離開棋子圖示上，不再顯示詳細資料
func _on_mouse_out_icon(card: Card) -> void:
	mouse_in_icon = null

#滑鼠在攻擊鍵上，顯示攻擊範圍
func _on_mouse_in_attack(piece: Piece) -> void:
	if piece.outfit_component.attack_button.disabled:
		return
	mouse_on_attack = true

#滑鼠離開攻擊鍵上，不再顯示攻擊範圍
func _on_mouse_out_attack(piece: Piece) -> void:
	mouse_on_attack = false
	tilemap.reset(1)

#棋子死亡時將其從場上移除
func _on_piece_die(piece: Piece) -> void:
	pieces_on_board.remove_child(piece)

#棋子死亡時將其從場上移除
func _on_discard(card: Card) -> void:
	pieces_in_hand.remove_child(card)

#切換回合按鍵
func _on_btn_turn_end_pressed() -> void:
	end_turn()

#顯示全部資訊
func _on_btn_show_all_toggled(toggled_on: bool) -> void:
	always_show = toggled_on
	for piece: Piece in pieces_on_board.get_children():
		var hp = piece.get("health_component")
		if hp:
			hp.always_show = toggled_on
			hp.health_display.visible = toggled_on
		var outfit = piece.get("outfit_component")
		if outfit:
			outfit.txt_value.visible = toggled_on
#endregion

#region 選定/移動
#選定/取消選定棋子時
func select_piece(card: Card) -> void:
	if card != null: #選定
		if card_selected != null: #若原本有其他選定的目標，清除選定特效
			card_selected.hide_select_effect()
			tilemap.card_select = null
		#選定目標，並為格子加上選定特效
		card_selected = card
		if card_selected.card_owner == null:
			card_selected.hide_select_effect()
		elif card_selected.card_owner.id == current_player:
			card_selected.show_select_effect()
		tilemap.card_select = card
	else: #取消選定
		if card_selected == null:
			return
		card_selected.hide_select_effect()
		card_selected = null
		tilemap.card_select = null

#將手上的棋子放置到場上
func move_piece_to_board(piece: Piece, location: Vector2i) -> void:
	if not is_on_board(location): #目標位置不在場上
		return
	if not piece.card_owner.id == current_player: #不能移動對手的棋子
		return
	if Global.board_dic[location] is not int: #該格子已有棋子
		return
	#上場
	Global.board_dic[location] = piece
	piece.card_owner.hand.pop_at(piece.location.x)
	#棋子設定
	pieces_in_hand.remove_child(piece)
	pieces_on_board.add_child(piece)
	piece.position = tilemap.map_to_local(location)
	piece.location = location
	piece.is_on_board = true
	piece.on_piece_set() #觸發上場效果
	piece_on_board_set(piece) #棋子上場外觀處理
	show_hand(piece.card_owner) #重新整理手牌

#將衍生物放置到場上
func add_piece_to_board(piece: Piece, location: Vector2i) -> bool:
	if not is_on_board(location): #目標位置不在場上
		return false
	if Global.board_dic[location] is not int: #該格子已有棋子
		return false
	#上場
	Global.board_dic[location] = piece
	pieces_on_board.add_child(piece)
	#棋子設定
	piece.position = tilemap.map_to_local(location)
	piece.location = location
	piece.is_on_board = true
	#設定外觀與連結
	if piece.outfit_component:
		piece.outfit_component.card_selected.connect(_on_card_selected)
		piece.outfit_component.mouse_in_icon.connect(_on_mouse_in_icon)
		piece.outfit_component.mouse_out_icon.connect(_on_mouse_out_icon)
		piece.piece_die.connect(_on_piece_die)
	piece.on_piece_set() #觸發上場效果
	piece_on_board_set(piece) #棋子上場外觀處理
	return true

#移動場上棋子
func move_piece(piece: Piece, location: Vector2i) -> void:
	if not move_mode_on: #移動模式
		return
	if not piece.buff_component.has_buff(Global.data.buff.move.name): #該棋子沒有移動buff(理論上不可能，但以防萬一)
		return
	if not piece.card_owner.id == current_player: #不能移動對手的棋子
		return
	if not piece.get_move_location().has(location): #不在移動範圍內
		return
	#移動棋子
	Global.board_dic[piece.location] = 0
	Global.board_dic[location] = piece
	piece.position = tilemap.map_to_local(location)
	piece.location = location
	#移除移動buff並離開移動模式
	piece.remove_buff(piece.buff_component.get_buff(Global.data.buff.move.name))
	move_mode_on = false
	#觸發移動後效果
	piece.after_move()
#endregion

#region 選定/移動工具
#棋子上場外觀處理
func piece_on_board_set(piece: Piece) -> void:
	if piece.outfit_component:
		if not piece.card_owner == null:
			piece.outfit_component.player_effect.show()
	if always_show:
		var hp = piece.get("health_component")
		if hp:
			hp.always_show = true
			hp.health_display.show()
		if piece.outfit_component:
			piece.outfit_component.txt_value.show()
#endregion

#region 判斷
#判斷棋子是否在棋盤上
func is_on_board(location: Vector2i) -> bool:
	if location.x >= 2 and location.x <= 5:
		if location.y >= 2 and location.y <= 5:
			return true
	return false

#取得所有棋子
func get_all_pieces() -> Array:
	var pieces := []
	pieces.append_array(pieces_in_hand.get_children())
	pieces.append_array(pieces_on_board.get_children())
	return pieces
#endregion
