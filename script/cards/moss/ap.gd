extends Piece
class_name MossAP

var moss = preload("res://script/cards/moss/moss.gd").new()
var buff_value : int = 5

func _init() -> void:
	show_name = Global.data.card.moss.ap.show_name
	description = Global.data.card.moss.ap.description.format([str(buff_value)])
	hint = Global.data.card.moss.ap.hint
	piece_type = Global.PieceType.AP

func refresh() -> void:
	moss.update_icon(self)

func _on_attack_component_on_hit(target: Piece) -> void:
	if not target.buff_component:
		return
	#給予暈眩
	if not target.buff_component.has_buff(Global.data.buff.stun.name): #不疊加
		target.add_buff(Global.get_stun_debuff())
	moss.add_rune(card_owner, buff_value)
