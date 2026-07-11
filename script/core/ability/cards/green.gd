# P1-7 Green 全卡能力組裝 + LuckEngine（見 docs/rebuild/02 §Green，Python 出處 cards/card_green.py）。
# 綠色主題：運氣值（players_luck）機制。共用 lucky_effects：擲 1–100 ≤ 擁有者運氣 → 好運，否則壞運。
# 變體旗標：ap（自己：壞運跳過、好運不生方塊）、ap_target（必走壞運分支，見 R §B2）、tank（好運分支跳過）。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[Ability]）。
class_name GreenCards
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[Ability]）。
static func registrations() -> Dictionary:
	return {
		"LUCKYBLOCK": Callable(GreenCards, "luckyblock"),
		"ADCG": Callable(GreenCards, "adcg"),
		"APG": Callable(GreenCards, "apg"),
		"TANKG": Callable(GreenCards, "tankg"),
		"HFG": Callable(GreenCards, "hfg"),
		"LFG": Callable(GreenCards, "lfg"),
		"ASSG": Callable(GreenCards, "assg"),
		"APTG": Callable(GreenCards, "aptg"),
		"SPG": Callable(GreenCards, "spg"),
	}


# LUCKYBLOCK：中立方塊。被擊殺 → 對攻擊者發動 lucky_effects；攻擊者方每張 APTG +1 護盾（Python LuckyBlock.been_killed）。
static func luckyblock() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_lb_been_killed", Trigger.Type.ON_BEEN_KILLED, [LuckyBlockBeenKilledEffect.new()], trig)]


# ADCG：攻擊時 自身同行同列每個空格 luckyblock_spawn_chance% 生成 LUCKYBLOCK（Python Adc.ability）。
static func adcg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_adc_spawn", Trigger.Type.ON_ABILITY_HIT, [AdcAbilityEffect.new()], trig)]


# APG：攻擊附帶麻痺；目標必吃一個壞運（ap_target）；自己擲好運（不會被懲罰，ap）（Python Ap.ability）。
static func apg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_ap_luck", Trigger.Type.ON_ABILITY_HIT, [ApAbilityEffect.new()], trig)]


# TANKG：被攻擊後 攻擊者依其運氣可能吃壞運（TANK 變體）（Python Tank.been_attacked）。
static func tankg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_tank_jinx", Trigger.Type.ON_BEEN_ATTACKED, [TankBeenAttackedEffect.new()], trig)]


# HFG：若攻擊目標是 LUCKYBLOCK → 自方運氣 +luck_increase，隨機空格再生 1 個 LUCKYBLOCK（Python Hf.ability）。
static func hfg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_hf_lb_luck", Trigger.Type.ON_ABILITY_HIT, [HfAbilityEffect.new()], trig)]


# LFG：斬殺 LUCKYBLOCK 後 對最近敵方造成自身 ATK 傷害（不觸發攻擊附帶）；attack_gain_chance% 攻擊次數 +1（Python Lf.killed）。
static func lfg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_lf_lb_kill", Trigger.Type.ON_KILLED, [LfKilledEffect.new()], trig)]


# ASSG：斬殺後 自方運氣 +5、敵方運氣 -enemy_luck_loss（Python Ass.killed）。
static func assg() -> Array:
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [Ability.new("green_ass_kill_luck", Trigger.Type.ON_KILLED, [AssKilledEffect.new()], trig)]


# APTG：不能攻擊（attack 恆 False）；回合開始 小十字內每個空格生成 LUCKYBLOCK（Python Apt.attack / on_refresh）。
static func aptg() -> Array:
	var passive: Array[int] = [AbilityComponent.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponent.Tag.TRIGGERED]
	return [
		Ability.new("green_apt_cannot_attack", Trigger.Type.ATTACK_OVERRIDE, [AptCannotAttackEffect.new()], passive),
		Ability.new("green_apt_refresh_spawn", Trigger.Type.ON_REFRESH, [AptRefreshEffect.new()], trig),
	]


# SPG：佈署時 運氣 +luck_increase；若運氣 > min_luck_to_spawn，每超出 10 點在隨機空格放 1 個 LUCKYBLOCK（Python Sp.deploy）。
static func spg() -> Array:
	var enter: Array[int] = [AbilityComponent.Tag.ON_ENTER]
	return [Ability.new("green_sp_deploy_luck", Trigger.Type.ON_DEPLOY, [SpDeployEffect.new()], enter)]


# --- 共用輔助 ---

# 生成一個中立 LUCKYBLOCK（經 GameCore._spawn_card：檢查空格、佔格、發 spawn 事件）。回傳是否成功。
static func _spawn_luckyblock(core: GameCore, x: int, y: int) -> bool:
	return core._spawn_card(x, y, "LUCKYBLOCK", "neutral", core.neutral_pieces)


# 幸運/厄運效果（Python GreenCard.lucky_effects，完整翻譯，順序不可改）。
# target：受效果的棋子；運氣以 target.owner 計。
static func lucky_effects(core: GameCore, target: PieceState, ap: bool = false,
		ap_target: bool = false, tank: bool = false) -> void:
	var owner: String = target.owner
	if not ap_target and core.rng.randi_range(1, 100) <= int(core.players_luck[owner]):
		# 好運分支。ap_target 恆不進此分支；tank 進來立即返回（好運跳過）。
		if ap_target or tank:
			return
		core.players_luck[owner] += 1
		match core.rng.randi_range(1, 5):
			1:
				target.armor += 4
			2:
				target.damage *= 2
			3:
				Combat.enqueue_attack(core, target)
			4:
				target.set_moving(true)
			5:
				if ap:
					return   # AP 自己不生方塊
				var offsets: Array = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
				for d: Vector2i in offsets:
					var np: Vector2i = Vector2i(target.board_x + d.x, target.board_y + d.y)
					if core.board.is_free(np):
						_spawn_luckyblock(core, np.x, np.y)
	else:
		# 壞運分支。AP 自己不受懲罰、直接返回（不扣運氣）。
		if ap:
			return
		core.players_luck[owner] -= 1
		match core.rng.randi_range(1, 5):
			1:
				target.armor = 0
			2:
				target.set_numb(true)
			3:
				target.health = target.health / 2
				core.event_sink.append(GameEvent.hurt(target.pos(), 0.0, target.health))
			4:
				target.damage = target.damage / 2
			5:
				if target.health >= 2:
					target.health -= 2
					core.event_sink.append(GameEvent.hurt(target.pos(), 0.0, target.health))


# --- 效果 ---

# LUCKYBLOCK 被擊殺：對攻擊者發動 lucky_effects；攻擊者方每張 APTG +1 護盾。
# ON_BEEN_KILLED：ctx.source=被殺者(LUCKYBLOCK)、ctx.target=攻擊者。
class LuckyBlockBeenKilledEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var core: GameCore = ctx.core
		var attacker: PieceState = ctx.target
		if attacker == null:
			return true
		GreenCards.lucky_effects(core, attacker)
		for c: PieceState in core.get_player(attacker.owner).on_board:
			if c.card_id == "APTG":
				c.armor += 1
		return true


# ADCG：自身同行同列每個空格 luckyblock_spawn_chance% 生成 LUCKYBLOCK。
class AdcAbilityEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var chance: int = int(core.balance.param(src.card_id, "luckyblock_spawn_chance", 0))
		for pos: Vector2i in core.board.occupy:
			if (pos.x == src.board_x or pos.y == src.board_y) and core.board.is_free(pos):
				if core.rng.randi_range(1, 100) <= chance:
					GreenCards._spawn_luckyblock(core, pos.x, pos.y)
		return true


# APG：目標麻痺 + 必吃壞運（ap_target）；自己擲好運（ap，不受懲罰）。
class ApAbilityEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		if ctx.target != null:
			ctx.target.set_numb(true)
			GreenCards.lucky_effects(core, ctx.target, false, true, false)
		GreenCards.lucky_effects(core, src, true, false, false)
		return true


# TANKG：被攻擊後 攻擊者擲運氣（TANK 變體，好運跳過）。
# ON_BEEN_ATTACKED：ctx.source=受擊者(TANKG)、ctx.target=攻擊者。
class TankBeenAttackedEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var attacker: PieceState = ctx.target
		if attacker != null:
			GreenCards.lucky_effects(ctx.core, attacker, false, false, true)
		return true


# HFG：若目標是 LUCKYBLOCK → 自方運氣 +luck_increase，隨機空格再生 1 個 LUCKYBLOCK。
class HfAbilityEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		if ctx.target != null and ctx.target.card_id == "LUCKYBLOCK":
			core.players_luck[src.owner] += int(core.balance.param(src.card_id, "luck_increase", 0))
			var free: Array = []
			for pos: Vector2i in core.board.occupy:
				if core.board.is_free(pos):
					free.append(pos)
			if not free.is_empty():
				var pick: Vector2i = core.rng.choice(free)
				GreenCards._spawn_luckyblock(core, pick.x, pick.y)
		return true


# LFG：斬殺 LUCKYBLOCK 後 對最近敵方（不含中立）造成自身 ATK 傷害（無附帶）；attack_gain_chance% 攻擊次數 +N。
# ON_KILLED：ctx.source=攻擊者(LFG)、ctx.target=被殺者。
class LfKilledEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var victim: PieceState = ctx.target
		var core: GameCore = ctx.core
		if victim != null and victim.card_id == "LUCKYBLOCK":
			var opp: String = core.opponent_name(src.owner)
			for c: PieceState in Combat.detection(core, src, "nearest", core.get_player(opp).on_board):
				Combat.damage_calculate(core, c, src.damage, src, false, 0.0)
			if core.rng.randi_range(1, 100) <= int(core.balance.param(src.card_id, "attack_gain_chance", 0)):
				core.number_of_attacks[src.owner] += int(core.balance.param(src.card_id, "attack_gain_per_luckyblock_kill", 0))
		return true


# ASSG：斬殺後 自方運氣 +5、敵方運氣 -enemy_luck_loss。
class AssKilledEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		core.players_luck[src.owner] += 5
		core.players_luck[core.opponent_name(src.owner)] -= int(core.balance.param(src.card_id, "enemy_luck_loss", 0))
		return true


# APTG：完全禁止攻擊（Python attack 恆回傳 False）。
class AptCannotAttackEffect extends AbilityEffect:
	func execute(_ctx: AbilityContext) -> Variant:
		return false


# APTG：回合開始，小十字內每個空格生成 LUCKYBLOCK。
class AptRefreshEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var offsets: Array = [
			Vector2i(src.board_x - 1, src.board_y), Vector2i(src.board_x + 1, src.board_y),
			Vector2i(src.board_x, src.board_y - 1), Vector2i(src.board_x, src.board_y + 1),
		]
		for pos: Vector2i in offsets:
			if core.board.is_free(pos):
				GreenCards._spawn_luckyblock(core, pos.x, pos.y)
		return true


# SPG：佈署時 運氣 +luck_increase；運氣 > min 時每超出 10 點在隨機空格放 1 個 LUCKYBLOCK。
# 佈署在「本子佔格之前」執行（對齊 Python），故需手動排除自身格。
class SpDeployEffect extends AbilityEffect:
	func execute(ctx: AbilityContext) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var owner: String = src.owner
		core.players_luck[owner] += int(core.balance.param(src.card_id, "luck_increase", 0))
		var min_luck: int = int(core.balance.param(src.card_id, "min_luck_to_spawn", 50))
		var free: Array = []
		for pos: Vector2i in core.board.occupy:
			if core.board.is_free(pos) and pos != src.pos():
				free.append(pos)
		if free.is_empty():
			return true
		core.rng.shuffle(free)
		if int(core.players_luck[owner]) > min_luck:
			var n: int = mini((int(core.players_luck[owner]) - min_luck) / 10, free.size())
			for i: int in n:
				GreenCards._spawn_luckyblock(core, free[i].x, free[i].y)
		return true
