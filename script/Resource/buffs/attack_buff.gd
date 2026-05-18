extends Buff
class_name AttackBuff

func apply_buff(target):
	if value > 0:
		icon_path = Global.buff_icon.attack_buff
	else:
		icon_path = Global.buff_icon.attack_debuff
	var atk = target.get("attack_component")
	if atk:
		atk.atk += value

func remove_buff(target):
	var atk = target.get("attack_component")
	if atk:
		atk.atk -= value

func add_value(target, add):
	super.add_value(target, add)
	var atk = target.get("attack_component")
	if atk:
		atk.atk += add
