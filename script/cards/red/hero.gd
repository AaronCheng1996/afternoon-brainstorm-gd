extends Piece
class_name RedHero

var red: Red = preload("res://script/cards/red/red.gd").new()
var kill_count : int = 0

func _init() -> void:
	show_name = Global.data.card.red.hero.show_name
	description = Global.data.card.red.hero.description.format([red.battle_fury_count])
	hint = Global.data.card.red.hero.hint
	piece_type = Global.PieceType.HERO

#棋子放置時
func on_piece_set() -> void:
	#清除手牌
	var n : int = card_owner.hand.size()
	for i in range(n):
		if card_owner.hand[n - 1 - i].card_type != Global.CardType.SPELL:
			card_owner.discard(card_owner.hand[n - 1 - i])
	#清除場上
	var allys = Global.get_board_pieces().filter(filter_ally_piece)
	for ally: Piece in allys:
		ally.die(true)
	#獲得增益
	for buff: Buff in card_owner.buff_component.active_buffs:
		if buff.tag.has(Global.BuffTag.RED):
			var buff_apply: Buff = buff.duplicate()
			if buff_apply.show_name == Global.data.state.shield.name:
				buff_apply.icon_path = {}
				buff_apply.duration = 1
			buff_apply.show_value = false
			buff_apply.show_name = buff.show_name
			buff_apply.description = buff.description
			buff_apply.value = buff.value
			add_buff(buff_apply)
	refresh()

func attack() -> void:
	kill_count = 0
	super.attack()
	for i in range(kill_count):
		attack_component.hit(get_random_enemy())

func _on_attack_component_on_kill(target: Piece) -> void:
	kill_count += 1
