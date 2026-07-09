class_name StealAttackEffect
extends AbilityEffect


func execute(ctx: GameEvent) -> void:
	var source := ctx.source as Piece
	var target := ctx.primary_target as Piece
	if source == null or target == null:
		return
	if not target.attack_component or not target.buff_component:
		return
	if target.attack_component.atk == 0:
		return
	var stolen := target.attack_component.atk
	var attack_debuff := AttackBuff.new()
	attack_debuff.show_name = Global.data.buff.attack_stolen.name
	attack_debuff.description = Global.data.buff.attack_stolen.description
	attack_debuff.tag.append_array([Global.BuffTag.DEBUFF])
	attack_debuff.value = -stolen
	target.add_buff(attack_debuff)
	var red := preload("res://script/cards/red/red.gd").new()
	red.attack_buff(stolen, source)
