extends TileMap

signal tile_selected(tile)
var grid_size = 4
var hand_size = 8
var dic = {}
var card_select : Card = null
var current_player : int = -1


func _ready() -> void:
	#生成棋盤
	for x in grid_size:
		for y in grid_size:
			dic[str(Vector2i(x + 2, y + 2))] = "board"
	#生成手上空間
	for x in hand_size:
		dic[str(Vector2i(x, 0))] = "hand"
		dic[str(Vector2i(x, 7))] = "hand"


func _process(delta: float) -> void:
	reset(2)
	if card_select: #有選定棋子，顯示可動目標
		set_cell(2, card_select.location, 2, Vector2i(0, 0), 0)
		var tile = local_to_map(get_local_mouse_position())
		if tile == card_select.location: #排除自己
			return
		if card_select.card_owner == null: #排除無主
			return
		if card_select.card_owner.id != current_player: #排除對方棋子
			return
		if card_select.outfit_component: #排除在場上且不能移動時
			if card_select.outfit_component.move_button.disabled and is_on_board(card_select.location):
				return
		#顯示可動目標
		if dic.has(str(tile)) and (tile.y == card_select.card_owner.id * 7 or (tile.y != 0 and tile.y != 7)):
			set_cell(2, tile, 2, Vector2i(0, 0), 0)

#顯示攻擊對象
func highlight_attack_tiles(targets: Array) -> void:
	for target in targets:
		set_cell(1, target, 2, Vector2i(2, 0), 0)

#顯示可使用對象
func highlight_valid_tiles(targets: Array) -> void:
	for target in targets:
		set_cell(1, target, 2, Vector2i(1, 0), 0)

#清除特定圖層
func reset(layer: int) -> void:
	for x in grid_size:
		for y in grid_size:
			erase_cell(layer, Vector2i(x + 2, y + 2))
	for x in hand_size:
		erase_cell(layer, Vector2i(x, 0))
		erase_cell(layer, Vector2i(x, 7))

#點擊時
func _on_board_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse_left"):
		var tile = local_to_map(get_local_mouse_position())
		if dic.has(str(tile)):
			tile_selected.emit(tile)

#判斷是否在棋盤上
func is_on_board(location: Vector2i) -> bool:
	if location.x >= 2 and location.x <= 5:
		if location.y >= 2 and location.y <= 5:
			return true
	return false
