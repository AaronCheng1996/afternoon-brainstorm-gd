extends Node
class_name Blue

var discharge_count = 3

#獲得藍球
func add_blue_charge(player: Player, value: int = 1) -> void:
	if player == null:
		return
	if not player.buff_component:
		return
	if value == 0:
		return
	if not player.buff_component.has_buff(Global.data.buff.blue_charge.name):
		player.buff_component.add_buff(get_blue_charge_buff())
	var blue_charge_buff = player.buff_component.get_buff(Global.data.buff.blue_charge.name)
	blue_charge_buff.value += value
	if blue_charge_buff.value >= discharge_count:
		blue_charge_release(player, blue_charge_buff)
	player.buff_component.show_buff()
	#藍APT獲得護盾、更新HF數值
	var trigger_list = [
		Global.data.card.blue.apt.show_name, 
		Global.data.card.blue.hf.show_name
	]
	for piece: Card in Global.get_show_pieces(player):
		if trigger_list.has(piece.show_name):
			piece.trigger_effect(value)
#取得藍球數
func get_blue_charge_count(player: Player) -> int:
	if player == null:
		return 0
	if not player.buff_component:
		return 0
	if not player.buff_component.has_buff(Global.data.buff.blue_charge.name):
		player.buff_component.add_buff(get_blue_charge_buff())
	return player.buff_component.get_buff(Global.data.buff.blue_charge.name).value

#取得藍球buff
func get_blue_charge_buff() -> Buff:
	var blue_charge_buff: BlueCharge = BlueCharge.new()
	blue_charge_buff.show_name = Global.data.buff.blue_charge.name
	blue_charge_buff.description = Global.data.buff.blue_charge.description
	blue_charge_buff.value = 0
	blue_charge_buff.show_value = true
	return blue_charge_buff

#釋放
func blue_charge_release(player: Player, blue_charge_buff: BlueCharge) -> void:
	if blue_charge_buff.value < discharge_count:
		return
	if Global.DEBUG:
		print("[DEBUG] 藍球：release")
	blue_charge_buff.value -= discharge_count
	player.draw_card()
	#藍ADC自動攻擊、更新HF數值
	var trigger_list = [
		Global.data.card.blue.adc.show_name, 
		Global.data.card.blue.hf.show_name,
		Global.data.card.blue.hero.show_name
	]
	for piece: Card in Global.get_show_pieces(player):
		if trigger_list.has(piece.show_name):
			piece.trigger_effect(blue_charge_buff.value)
	#藍球若依然超過 3 顆就繼續遞迴
	if blue_charge_buff.value >= discharge_count:
		blue_charge_release(player, blue_charge_buff)
