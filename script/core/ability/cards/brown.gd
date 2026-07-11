# P1-12 Brown 全卡能力組裝（見 docs/rebuild/02 §Brown，Python 出處 cards/card_brown.py）。
# 棕色主題＝高數值高代價的「巨人」；**SPBR 攻擊後關閉我方其他 Brown 卡全部效果**——
# 這是內建沉默（silence）機制的第一個實際使用者（見 04 §5.5、D3）。
#
# 沉默模型：
#   * 每張 Brown 卡「受 effects_disabled 影響的能力」都掛 Tag.FACTION（可被沉默）。
#   * SPBR 攻擊命中時（ON_ABILITY_HIT）對我方其他 Brown 卡呼叫 silence_tag(FACTION)。
#   * 每張 Brown 卡都有一個「還原」能力（ON_REFRESH，Tag.PASSIVE 不受沉默）：
#     回合開始若場上已無我方 SPBR → clear_silence()，對齊 Python BrownCard.on_refresh。
#   * 不受 effects_off 影響的能力（SPBR 沉默本身、APTBR 佈署給敵護盾）不掛 FACTION。
#
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[Ability]）。
class_name BrownCards
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[Ability]）。
static func registrations() -> Dictionary:
	return {
		"ADCBR": Callable(BrownCards, "adcbr"),
		"APBR": Callable(BrownCards, "apbr"),
		"TANKBR": Callable(BrownCards, "tankbr"),
		"HFBR": Callable(BrownCards, "hfbr"),
		"LFBR": Callable(BrownCards, "lfbr"),
		"ASSBR": Callable(BrownCards, "assbr"),
		"APTBR": Callable(BrownCards, "aptbr"),
		"SPBR": Callable(BrownCards, "spbr"),
	}


# 每張 Brown 卡共用的「還原沉默」能力（不受沉默，優先權最低使其先於同觸發能力執行）。
static func _restore() -> Ability:
	var tags: Array[int] = [AbilityComponent.Tag.PASSIVE]
	return Ability.new("brown_restore", Trigger.Type.ON_REFRESH, [RestoreEffect.new()], tags, -100)


# ADCBR：攻擊後自身麻痺（effects_off 時失效 → 沉默即改回普通攻擊）。
static func adcbr() -> Array:
	var f: Array[int] = [AbilityComponent.Tag.FACTION]
	return [
		_restore(),
		Ability.new("brown_adc_attack", Trigger.Type.ATTACK_OVERRIDE, [AdcAttackEffect.new()], f),
	]


# APBR：造成傷害後對手抽 1（on_attack_enemy_draw）。
static func apbr() -> Array:
	var f: Array[int] = [AbilityComponent.Tag.FACTION]
	return [
		_restore(),
		Ability.new("brown_ap_draw", Trigger.Type.ON_ABILITY_HIT, [ApDrawEffect.new()], f),
	]


# TANKBR：被攻擊記旗標；回合開始若上回合沒被攻擊 → 自傷 turn_start_health_loss（B1 裁定=4）。
static func tankbr() -> Array:
	var f: Array[int] = [AbilityComponent.Tag.FACTION]
	return [
		_restore(),
		Ability.new("brown_tank_flag", Trigger.Type.ON_BEEN_ATTACKED, [TankFlagEffect.new()], f),
		Ability.new("brown_tank_decay", Trigger.Type.ON_REFRESH, [TankDecayEffect.new()], f),
	]


# HFBR：attack_uses=2（一次攻擊耗 2 次數）；沉默時退回 1。
# 用 ATTACK_OVERRIDE 包住普通攻擊、依沉默狀態設定 attack_uses（對齊 Python Hf.attack，該法不受 effects_off 早退）。
static func hfbr() -> Array:
	# 不掛 FACTION：沉默時仍需執行（設 attack_uses=1），內部自行判斷沉默。
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		_restore(),
		Ability.new("brown_hf_attack", Trigger.Type.ATTACK_OVERRIDE, [HfAttackEffect.new()], tags),
	]


# LFBR：斬殺後敵方得 on_kill_enemy_points（2）分。
static func lfbr() -> Array:
	var f: Array[int] = [AbilityComponent.Tag.FACTION]
	return [
		_restore(),
		Ability.new("brown_lf_kill", Trigger.Type.ON_KILLED, [LfKillEffect.new()], f),
	]


# ASSBR：斬殺後我方跳過下回合抽牌。
static func assbr() -> Array:
	var f: Array[int] = [AbilityComponent.Tag.FACTION]
	return [
		_restore(),
		Ability.new("brown_ass_kill", Trigger.Type.ON_KILLED, [AssKillEffect.new()], f),
	]


# APTBR：佈署時所有敵方棋子 +2 護盾（不受 effects_off）；攻擊時最近友方 +1/+1，若友方也是 Brown 再 +1/+1。
static func aptbr() -> Array:
	var passive: Array[int] = [AbilityComponent.Tag.PASSIVE]
	var f: Array[int] = [AbilityComponent.Tag.FACTION]
	return [
		_restore(),
		Ability.new("brown_apt_deploy", Trigger.Type.ON_DEPLOY, [AptDeployEffect.new()], passive),
		Ability.new("brown_apt_buff", Trigger.Type.ON_ABILITY_HIT, [AptBuffEffect.new()], f),
	]


# SPBR：攻擊命中時自己亮怒氣、沉默我方其他 Brown 卡（本身不受 effects_off，故不掛 FACTION）。
static func spbr() -> Array:
	var tags: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		_restore(),
		Ability.new("brown_sp_silence", Trigger.Type.ON_ABILITY_HIT, [SpSilenceEffect.new()], tags),
	]


# --- 共用輔助 ---

# 我方場上是否有 SPBR。
static func _has_spbr(core: GameCore, owner: String) -> bool:
	for c: PieceState in core.get_player(owner).on_board:
		if c.card_id == "SPBR":
			return true
	return false


# 我方場上其他 Brown 卡（排除自己）。
static func _other_browns(core: GameCore, src: PieceState) -> Array:
	return core.get_player(src.owner).on_board.filter(
		func(c: PieceState) -> bool: return c != src and c.color_code == "BR")


# 最近的我方友方（排除自己、health>0）。
static func _nearest_allies(core: GameCore, src: PieceState) -> Array:
	var allies: Array = core.get_player(src.owner).on_board.filter(
		func(c: PieceState) -> bool: return c != src and c.health > 0)
	return Combat.detection(core, src, "nearest", allies)


# --- 效果 ---

# 還原：回合開始若場上已無我方 SPBR → 解除自身沉默（對齊 Python BrownCard.on_refresh）。
class RestoreEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		if not BrownCards._has_spbr(core, src.owner):
			if src.abilities != null:
				src.abilities.clear_silence()
		return null


# ADCBR：普通攻擊後自身麻痺（沉默時本效果不執行 → 退回 Combat 普通攻擊、不自麻）。
class AdcAttackEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var ok: bool = Combat.launch_attack(core, src, src.attack_types)
		src.hit_cards.clear()
		if ok:
			src.set_numb(true)
		return ok


# APBR：造成傷害後對手抽 on_attack_enemy_draw 張。
class ApDrawEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var n: int = int(core.balance.param(src.card_id, "on_attack_enemy_draw", 0))
		core.card_to_draw[core.opponent_name(src.owner)] += n
		return true


# TANKBR：被攻擊 → 記旗標（供回合開始判斷）。
class TankFlagEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		ctx.source.counters["brown_tank_attacked"] = true
		return null


# TANKBR：回合開始若上回合沒被攻擊 → 自傷 turn_start_health_loss；最後清旗標（對齊 Python 順序）。
class TankDecayEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var was_attacked: bool = bool(src.counters.get("brown_tank_attacked", false))
		if not was_attacked:
			var loss: int = int(core.balance.param(src.card_id, "turn_start_health_loss", 0))
			# 自傷經傷害管線（護盾優先）。自身既是攻擊者又是受害者 → 清 hit_cards 斷循環參考（見 P1-9 註）。
			Combat.damage_calculate(core, src, loss, src, false, 0.0)
			src.hit_cards.clear()
		src.counters["brown_tank_attacked"] = false
		return null


# HFBR：ATTACK_OVERRIDE 包住普通攻擊；依沉默狀態設定 attack_uses（沉默=1，否則=2）。
class HfAttackEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var ok: bool = Combat.launch_attack(core, src, src.attack_types)
		src.hit_cards.clear()
		var silenced: bool = src.abilities != null \
			and src.abilities.silenced_tags.has(AbilityComponent.Tag.FACTION)
		src.attack_uses = 1 if silenced else 2
		return ok


# LFBR：斬殺後敵方得 on_kill_enemy_points 分（player1 擁有 → score 增＝對面得分）。
class LfKillEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var points: int = int(core.balance.param(src.card_id, "on_kill_enemy_points", 0))
		if src.owner == "player1":
			core.score += points
		else:
			core.score -= points
		return true


# ASSBR：斬殺後我方跳過下回合抽牌。
class AssKillEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		core.skip_turn_draw[ctx.source.owner] = true
		return true


# APTBR：佈署時所有敵方棋子（health>0）+on_play_enemy_shield 護盾（不受 effects_off）。
class AptDeployEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var shield: int = int(core.balance.param(src.card_id, "on_play_enemy_shield", 0))
		for c: PieceState in core.get_player(core.opponent_name(src.owner)).on_board:
			if c.health > 0:
				c.armor += shield
		return null


# APTBR：攻擊時最近友方 +buff（atk/armor），若該友方也是 Brown 巨人再 +bonus。
class AptBuffEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		var buff: Dictionary = core.balance.param(src.card_id, "on_attack_buff_nearest_ally", {})
		var bonus: Dictionary = core.balance.param(src.card_id, "bonus_if_giant", {})
		for ally: PieceState in BrownCards._nearest_allies(core, src):
			ally.damage += int(buff.get("atk", 0))
			ally.armor += int(buff.get("armor", 0))
			if ally.color_code == "BR":
				ally.damage += int(bonus.get("atk", 0))
				ally.armor += int(bonus.get("armor", 0))
		return true


# SPBR：攻擊命中 → 自己亮怒氣、沉默我方其他 Brown 卡（silence_tag FACTION）。
class SpSilenceEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var src: PieceState = ctx.source
		src.set_anger(true)
		for c: PieceState in BrownCards._other_browns(core, src):
			if c.abilities != null:
				c.abilities.silence_tag(AbilityComponent.Tag.FACTION)
		return true
