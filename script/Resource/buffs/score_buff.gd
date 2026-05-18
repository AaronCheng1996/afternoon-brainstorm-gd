extends Buff
class_name ScoreBuff

func apply_buff(target):
	var score = target.get("score_component")
	if score:
		score.score += value

func remove_buff(target):
	var score = target.get("score_component")
	if score:
		score.score -= value

func add_value(target, add):
	super.add_value(target, add)
	var score = target.get("score_component")
	if score:
		score.score += add
