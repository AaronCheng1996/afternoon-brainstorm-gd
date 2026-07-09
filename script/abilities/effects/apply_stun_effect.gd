class_name ApplyStunEffect
extends AbilityEffect


func execute(ctx: GameEvent) -> void:
	var target := ctx.primary_target as Piece
	if target == null:
		return
	if not target.buff_component:
		return
	if target.buff_component.has_buff(Global.data.buff.stun.name):
		return
	target.add_buff(Global.get_stun_debuff())
