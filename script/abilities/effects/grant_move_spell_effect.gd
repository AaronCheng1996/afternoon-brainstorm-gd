class_name GrantMoveSpellEffect
extends AbilityEffect


func execute(ctx: GameEvent) -> void:
	var source := ctx.source as Piece
	if source == null or source.card_owner == null:
		return
	if not source.is_on_board or source.is_dead:
		return
	var current_turn: int = ctx.extra.get("current_turn", -1)
	if current_turn != source.card_owner.id:
		return
	Global.get_move_spell(source.card_owner)
