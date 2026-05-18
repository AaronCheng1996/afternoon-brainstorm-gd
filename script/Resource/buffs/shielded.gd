extends Buff
class_name Shielded

func apply_buff(target):
	var hp = target.get("health_component")
	if hp:
		hp.shield += value
