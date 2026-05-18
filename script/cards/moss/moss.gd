extends Node
class_name Moss

#獲得符文
func add_rune(player: Player, value: int = 1) -> void:
	if player == null:
		return
	if not player.buff_component:
		return
	if value == 0:
		return
	if not player.buff_component.has_buff(Global.data.buff.rune.name):
		player.buff_component.add_buff(get_rune_buff())
	var rune_buff = player.buff_component.get_buff(Global.data.buff.rune.name)
	for i in range(get_sp_count(player)):
		value *= 2
	rune_buff.value += value
	refresh(player)

#取得符文數
func get_rune_count(player: Player) -> int:
	if player == null:
		return 0
	if not player.buff_component:
		return 0
	if not player.buff_component.has_buff(Global.data.buff.rune.name):
		player.buff_component.add_buff(get_rune_buff())
	return player.buff_component.get_buff(Global.data.buff.rune.name).value

#取得墨綠sp數
func get_sp_count(player: Player) -> int:
	return Global.get_piece_on_board(Global.data.card.moss.sp.show_name, player).size()

func on_sp_set(player: Player) -> void:
	if not player.buff_component.has_buff(Global.data.buff.rune.name):
		return
	player.buff_component.get_buff(Global.data.buff.rune.name).value *= 2
	refresh(player)

func on_sp_die(player: Player) -> void:
	if not player.buff_component.has_buff(Global.data.buff.rune.name):
		return
	player.buff_component.get_buff(Global.data.buff.rune.name).value /= 2
	refresh(player)

#取得符文buff
func get_rune_buff() -> Buff:
	var rune_buff: Rune = Rune.new()
	rune_buff.show_name = Global.data.buff.rune.name
	rune_buff.description = Global.data.buff.rune.description
	rune_buff.value = 0
	rune_buff.show_value = true
	return rune_buff

var default_icon = preload("res://img/piece/standerd/dark_green.png")
var half_power_icon = preload("res://img/piece/standerd/dark_green_half_powered.png")
var empower_icon = preload("res://img/piece/standerd/dark_green_empowered.png")

#更改圖示
func update_icon(piece: Piece) -> void:
	var power = get_rune_count(piece.card_owner)
	if power < 20 and piece.outfit_component.icon.texture != default_icon:
		piece.outfit_component.icon.texture = default_icon
	if power >= 20 and power < 50 and piece.outfit_component.icon.texture != half_power_icon:
		piece.outfit_component.icon.texture = half_power_icon
	if power >= 50 and piece.outfit_component.icon.texture != empower_icon:
		piece.outfit_component.icon.texture = empower_icon

#重新整理
func refresh(player: Player) -> void:
	player.buff_component.show_buff()
	var trigger_list = [
		Global.data.card.moss.adc.show_name,
		Global.data.card.moss.ap.show_name,
		Global.data.card.moss.apt.show_name,
		Global.data.card.moss.ass.show_name,
		Global.data.card.moss.hf.show_name,
		Global.data.card.moss.lf.show_name,
		Global.data.card.moss.sp.show_name,
		Global.data.card.moss.tank.show_name,
		Global.data.card.moss.hero.show_name,
	]
	for piece: Card in Global.get_show_pieces(player):
		if not trigger_list.has(piece.show_name):
			continue
		piece.refresh()
