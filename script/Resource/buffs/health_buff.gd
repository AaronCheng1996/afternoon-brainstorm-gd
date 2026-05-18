extends Buff
class_name HealthBuff

func apply_buff(target):
	if value > 0:
		icon_path = Global.buff_icon.health_buff
	else:
		icon_path = Global.buff_icon.health_debuff
	var hp = target.get("health_component")
	if hp:
		hp.max_health += value
		hp.health += value

func remove_buff(target):
	var hp = target.get("health_component")
	if hp:
		hp.max_health -= value
		if hp.health <= hp.max_health:
			return
		hp.health = hp.max_health

func add_value(target, add):
	super.add_value(target, add)
	var hp = target.get("health_component")
	if hp:
		hp.max_health += add
		hp.health += add
