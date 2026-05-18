extends Piece
class_name MossLF

var moss = preload("res://script/cards/moss/moss.gd").new()
var rate : int = 25
var buff_value : int = 2

func _init() -> void:
	show_name = Global.data.card.moss.lf.show_name
	description = Global.data.card.moss.lf.description.format([str(0), str(rate), str(buff_value)])
	hint = Global.data.card.moss.lf.hint
	piece_type = Global.PieceType.LF

func refresh() -> void:
	#更改圖示
	var power = moss.get_rune_count(card_owner)
	moss.update_icon(self)
	var text = str(power * rate / 100)
	text = Global.set_font_color(text, Global.get_font_color(power * rate / 100, 0))
	description = Global.data.card.moss.lf.description.format([text, str(rate), str(buff_value)])
	super.refresh()

func on_piece_set() -> void:
	var temp = attack_component.atk
	attack_component.atk = 0
	attack_component.attack(Global.get_board_pieces().filter(filter_opponent_piece), moss.get_rune_count(card_owner) * rate / 100)
	attack_component.atk = temp
	super.on_piece_set()

func _on_attack_component_on_kill(target: Piece) -> void:
	moss.add_rune(card_owner, buff_value)
