class_name OrangeAPAbilities


static func create() -> Array[Ability]:
	var stun_on_hit := Ability.new()
	stun_on_hit.id = "orange_ap_stun_on_hit"
	stun_on_hit.trigger = GameTrigger.Type.ON_ATTACK_HIT
	stun_on_hit.tags = [Ability.Tag.TRIGGERED]
	stun_on_hit.effects = [ApplyStunEffect.new()]

	var move_spell_on_turn := Ability.new()
	move_spell_on_turn.id = "orange_ap_grant_move_spell"
	move_spell_on_turn.trigger = GameTrigger.Type.ON_TURN_START
	move_spell_on_turn.tags = [Ability.Tag.TRIGGERED]
	move_spell_on_turn.effects = [GrantMoveSpellEffect.new()]

	return [stun_on_hit, move_spell_on_turn]
