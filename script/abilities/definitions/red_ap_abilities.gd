class_name RedAPAbilities


static func create() -> Array[Ability]:
	var on_hit := Ability.new()
	on_hit.id = "red_ap_on_hit"
	on_hit.trigger = GameTrigger.Type.ON_ATTACK_HIT
	on_hit.tags = [Ability.Tag.TRIGGERED]
	on_hit.effects = [ApplyStunEffect.new(), StealAttackEffect.new()]
	return [on_hit]
