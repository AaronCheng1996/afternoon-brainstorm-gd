extends Piece
class_name MossAPT

var moss = preload("res://script/cards/moss/moss.gd").new()
var rate : int = 50
var buff_value_sum : int = 0

func _init() -> void:
	show_name = Global.data.card.moss.apt.show_name
	description = Global.data.card.moss.apt.description.format([str(0), str(0), str(0)])
	hint = Global.data.card.moss.apt.hint.format([str(53)])
	piece_type = Global.PieceType.APT

func refresh() -> void:
	#更改圖示
	var power = moss.get_rune_count(card_owner)
	moss.update_icon(self)
	#更改說明
	var text1 = str(power * rate / 100)
	var text2 = str(health_component.shield * rate / 100)
	var text3 = str((power * rate / 100 + attack_component.atk) * rate / 100)
	text1 = Global.set_font_color(text1, Global.get_font_color(power * rate / 100, 0))
	text2 = Global.set_font_color(text2, Global.get_font_color(health_component.shield * rate / 100, 0))
	text3 = Global.set_font_color(text3, Global.get_font_color((power * rate / 100 + attack_component.atk) * rate / 100, attack_component.DEFAULT_ATK))
	description = Global.data.card.moss.apt.description.format([text1, text2, text3])
	var text4 = str(power)
	if power == 0:
		text4 = str(53)
	hint = Global.data.card.moss.apt.hint.format([text4])
	super.refresh()
	
func attack() -> void:
	buff_value_sum = 0
	#額外傷害
	attack_component.attack(Global.get_board_pieces().filter(filter_opponent_piece), moss.get_rune_count(card_owner) * rate / 100)
	#獲得符文
	moss.add_rune(card_owner, health_component.shield * rate / 100)
	#獲得護甲
	shielded(buff_value_sum, self)
	refresh()

func _on_attack_component_on_hit(target: Piece) -> void:
	buff_value_sum += (attack_component.atk + moss.get_rune_count(card_owner) * rate / 100) * rate / 100
