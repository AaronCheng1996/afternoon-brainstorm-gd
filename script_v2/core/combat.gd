# P1-3 傷害管線 + 攻擊佇列（見 docs/rebuild/01 §5–§7、§10）。
# 純靜態函式，操作傳入的 GameCore（保持 core 無 Node 依賴）。
# 翻譯自 cards/base.py：detection / damage_calculate / launch_attack / _launch_attack_impl。
# 能力鉤子透過 PieceState.abilities（AbilityComponentV2）依觸發點分派。
class_name CombatV2
extends RefCounted


# --- 目標判定（見 01 §5，cards/base.py detection）---
# targets：候選敵方棋子池（呼叫端已含 neutral）。回傳命中順序陣列。
static func detection(core: GameCore, attacker: PieceState, attack_types: String, targets: Array) -> Array:
	var alive: Array = targets.filter(func(c: PieceState) -> bool: return c.health > 0)
	var out: Array = []
	for at: String in attack_types.split(" ", false):
		match at:
			"small_cross":
				for c: PieceState in alive:
					if _is_small_cross(attacker, c):
						out.append(c)
			"large_cross":
				for c: PieceState in alive:
					if (c.board_x == attacker.board_x or c.board_y == attacker.board_y) \
							and not (c.board_x == attacker.board_x and c.board_y == attacker.board_y):
						out.append(c)
			"small_x":
				for c: PieceState in alive:
					if _is_small_x(attacker, c):
						out.append(c)
			"large_x":
				pass   # 空實作（Python 亦然）
			"nearest":
				var n: PieceState = _pick_by_distance(core, attacker, alive, false)
				if n != null:
					out.append(n)
			"farthest":
				var f: PieceState = _pick_by_distance(core, attacker, alive, true)
				if f != null:
					out.append(f)
	return out


static func _is_small_cross(a: PieceState, c: PieceState) -> bool:
	return (c.board_x == a.board_x - 1 and c.board_y == a.board_y) \
		or (c.board_x == a.board_x + 1 and c.board_y == a.board_y) \
		or (c.board_x == a.board_x and c.board_y == a.board_y - 1) \
		or (c.board_x == a.board_x and c.board_y == a.board_y + 1)


static func _is_small_x(a: PieceState, c: PieceState) -> bool:
	return (c.board_x == a.board_x + 1 and c.board_y == a.board_y + 1) \
		or (c.board_x == a.board_x - 1 and c.board_y == a.board_y + 1) \
		or (c.board_x == a.board_x - 1 and c.board_y == a.board_y - 1) \
		or (c.board_x == a.board_x + 1 and c.board_y == a.board_y - 1)


# 曼哈頓距離最近/最遠一個；並列以 rng 隨機挑 1（見 01 §5）。
static func _pick_by_distance(core: GameCore, attacker: PieceState, alive: Array, farthest: bool) -> PieceState:
	if alive.is_empty():
		return null
	var best: int = -1
	for c: PieceState in alive:
		var d: int = abs(c.board_x - attacker.board_x) + abs(c.board_y - attacker.board_y)
		# farthest=false 取最小；farthest=true 取最大。
		if best < 0 or (farthest and d > best) or (not farthest and d < best):
			best = d
	var ties: Array = alive.filter(func(c: PieceState) -> bool:
		return abs(c.board_x - attacker.board_x) + abs(c.board_y - attacker.board_y) == best)
	return core.rng.choice(ties)


# --- 攻擊入口（見 cards/base.py attack）---
static func attack(core: GameCore, attacker: PieceState) -> bool:
	var ok: bool = launch_attack(core, attacker, attacker.attack_types)
	attacker.hit_cards.clear()
	return ok


# 建立一個攻擊佇列請求（見 01 §7）。
static func make_request(attacker: PieceState, attack_types: Variant = null,
		custom_targets: Array = [], ignore_numbness: bool = false, use_ability: bool = true) -> Dictionary:
	return {
		"attacker": attacker,
		"attack_types": attack_types,
		"custom_targets": custom_targets,
		"ignore_numbness": ignore_numbness,
		"use_ability": use_ability,
	}


# 能力引發的追加攻擊：排入佇列（不在管線中同步遞迴，見 01 §7）。
static func enqueue_attack(core: GameCore, attacker: PieceState, attack_types: Variant = null,
		custom_targets: Array = [], ignore_numbness: bool = false, use_ability: bool = true) -> void:
	core.pending_attacks.append(make_request(attacker, attack_types, custom_targets, ignore_numbness, use_ability))


# 最外層攻擊：執行本體後負責 drain 佇列（見 01 §7，cards/base.py launch_attack）。
static func launch_attack(core: GameCore, attacker: PieceState, attack_types: String,
		custom_targets: Array = [], ignore_numbness: bool = false, use_ability: bool = true) -> bool:
	var is_outer: bool = not core._attack_draining
	if is_outer:
		core._attack_draining = true
	var result: bool = _launch_attack_impl(core, attacker, attack_types, custom_targets, ignore_numbness, use_ability)
	if is_outer:
		while not core.pending_attacks.is_empty():
			var req: Dictionary = core.pending_attacks.pop_front()
			var atk: PieceState = req["attacker"]
			if atk.health <= 0:
				continue
			var at: String = req["attack_types"] if req["attack_types"] != null else atk.attack_types
			if at == "":
				continue
			_launch_attack_impl(core, atk, at, req["custom_targets"], req["ignore_numbness"], req["use_ability"])
			atk.hit_cards.clear()
		core._attack_draining = false
	return result


static func _launch_attack_impl(core: GameCore, attacker: PieceState, attack_types: String,
		custom_targets: Array, ignore_numbness: bool, use_ability: bool) -> bool:
	# numbness 或無攻擊模式 → 直接無效（不消耗次數；見 01 §3）。
	if not ignore_numbness and (attacker.is_numb() or attack_types == ""):
		return false
	var enemies: Array = core.get_enemies_of(attacker.owner)
	var targets: Array = custom_targets if not custom_targets.is_empty() \
		else detection(core, attacker, attack_types, enemies)
	if targets.is_empty():
		return false

	var base_delay: float = core._attack_anim_cursor
	for i: int in targets.size():
		var target: PieceState = targets[i]
		var atk_delay: float = base_delay + i * GameConfig.ANIM_LUNGE_STEP
		var hurt_delay: float = atk_delay + GameConfig.ANIM_LUNGE_STEP * GameConfig.HIT_DELAY_RATIO
		core.event_sink.append(GameEventV2.attack(attacker.pos(), target.pos(), atk_delay))
		if damage_calculate(core, target, attacker.damage, attacker, use_ability, hurt_delay):
			# 成功結算後全場廣播（目前無卡用，保留鉤子）。
			for c: PieceState in core.get_both_player_pieces():
				if c.abilities != null:
					var bctx := AbilityContextV2.new(core, c, target, 0, {"attacker": attacker})
					c.abilities.run(TriggerV2.Type.ON_AFTER_ATTACK_BROADCAST, bctx)
		core._attack_anim_cursor = base_delay + targets.size() * GameConfig.ANIM_LUNGE_STEP
	return true


# --- 傷害管線（見 01 §6，cards/base.py damage_calculate；順序不可改）---
static func damage_calculate(core: GameCore, victim: PieceState, value: int, attacker: PieceState,
		use_ability: bool, anim_delay: float) -> bool:
	# 0. 已死 → 無效。
	if victim.health <= 0:
		return false
	# 1. 記入攻擊者命中清單。
	attacker.hit_cards.append(victim)
	# 2. damage_block：True → 整次攻擊無效。
	if victim.abilities != null:
		var block_ctx := AbilityContextV2.new(core, victim, attacker, value, {"attacker": attacker})
		if victim.abilities.any_true(TriggerV2.Type.BLOCK_DAMAGE, block_ctx):
			return false
	# 3. 攻擊附帶能力（attacker.ability）。
	if use_ability and attacker.abilities != null:
		var ab_ctx := AbilityContextV2.new(core, attacker, victim, value, {})
		if attacker.abilities.any_true(TriggerV2.Type.ON_ABILITY_HIT, ab_ctx):
			core.stats.increment(Statistics.StatType.ABILITY, attacker.uid(), 1)
			core.event_sink.append(GameEventV2.new(GameEventV2.Kind.CAST, {"at": attacker.pos(), "kind": "ability"}))
	# 4. damage_bonus：預設 value + attacker.extra_damage，再由能力修改。
	value = value + attacker.extra_damage
	if attacker.abilities != null:
		var bonus_ctx := AbilityContextV2.new(core, attacker, victim, value, {})
		value = attacker.abilities.dispatch_mod(TriggerV2.Type.MOD_DAMAGE_BONUS, bonus_ctx)
	# 5. damage_reduce。
	if victim.abilities != null:
		var red_ctx := AbilityContextV2.new(core, victim, attacker, value, {"attacker": attacker})
		value = victim.abilities.dispatch_mod(TriggerV2.Type.MOD_DAMAGE_REDUCE, red_ctx)
	# 6. 場地攔截（全場，含 priority + feedback）。
	value = _special_damage_interceptor(core, victim, value, attacker)

	# 7. 護盾結算（三分支，見 01 §6）。
	if victim.armor > 0 and victim.armor >= value:
		_record_damage(core, attacker, victim, value)
		victim.armor -= value
		_emit_hurt_float(core, victim, value, anim_delay)
		_after_hit(core, victim, attacker, value)
		_run_after_damage(core, attacker, victim, value)
		return true
	elif victim.armor > 0 and victim.armor < value:
		if victim.armor + victim.health > value:
			var overflow: int = value - victim.armor
			victim.armor = 0
			victim.health -= overflow
		else:
			value = victim.armor + victim.health
			victim.armor = 0
			victim.health = 0
		_record_damage(core, attacker, victim, value)
		_emit_hurt_float(core, victim, value, anim_delay)
		_after_hit(core, victim, attacker, value)
		# 注意：此分支 kill 判定在 after_damage 之前（照 Python 順序）。
		if victim.health == 0:
			_handle_kill(core, attacker, victim, anim_delay)
		_run_after_damage(core, attacker, victim, value)
		return true
	elif victim.armor == 0:
		if victim.health < value:
			value = victim.health
		_record_damage(core, attacker, victim, value)
		victim.health -= value
		_emit_hurt_float(core, victim, value, anim_delay)
		_after_hit(core, victim, attacker, value)
		# 注意：此分支 after_damage 在 kill 判定之前（照 Python 順序）。
		_run_after_damage(core, attacker, victim, value)
		if victim.health == 0:
			_handle_kill(core, attacker, victim, anim_delay)
		return true
	return false


# 步驟 6：收集全場 on_field_effect_trigger，依 priority 升冪套用（見 01 §6）。
static func _special_damage_interceptor(core: GameCore, victim: PieceState, value: int, attacker: PieceState) -> int:
	var modifiers: Array = []
	for src: PieceState in core.get_all_pieces():
		if src.abilities == null:
			continue
		var ctx := AbilityContextV2.new(core, src, victim, value, {"attacker": attacker})
		modifiers.append_array(src.abilities.collect_field(ctx))
	if modifiers.is_empty():
		return value
	modifiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) < int(b.get("priority", 0)))
	var final_value: int = value
	for m: Dictionary in modifiers:
		final_value = int(m.get("value", final_value))
		var fb: Variant = m.get("feedback", null)
		if fb is Callable and (fb as Callable).is_valid():
			(fb as Callable).call(victim, final_value, attacker, core)
	return final_value


# 統計：DAMAGE_DEALT(攻擊者) + DAMAGE_TAKEN/COUNT(受擊者)（見 game_statistics.add_damage_taken）。
static func _record_damage(core: GameCore, attacker: PieceState, victim: PieceState, value: int) -> void:
	core.stats.increment(Statistics.StatType.DAMAGE_DEALT, attacker.uid(), value)
	core.stats.increment(Statistics.StatType.DAMAGE_TAKEN, victim.uid(), value)
	core.stats.increment(Statistics.StatType.DAMAGE_TAKEN_COUNT, victim.uid(), 1)


static func _emit_hurt_float(core: GameCore, victim: PieceState, value: int, anim_delay: float) -> void:
	core.event_sink.append(GameEventV2.hurt(victim.pos(), anim_delay, victim.health))
	core.event_sink.append(GameEventV2.float_text(victim.pos(), value, anim_delay))


# 步驟 8：been_attacked 鉤子。
static func _after_hit(core: GameCore, victim: PieceState, attacker: PieceState, value: int) -> void:
	if victim.abilities != null:
		var ctx := AbilityContextV2.new(core, victim, attacker, value, {"attacker": attacker})
		victim.abilities.run(TriggerV2.Type.ON_BEEN_ATTACKED, ctx)


# 步驟 9：after_damage_calculated 鉤子。
static func _run_after_damage(core: GameCore, attacker: PieceState, victim: PieceState, value: int) -> void:
	if attacker.abilities != null:
		var ctx := AbilityContextV2.new(core, attacker, victim, value, {})
		attacker.abilities.run(TriggerV2.Type.ON_AFTER_DAMAGE, ctx)


# 步驟 10：擊殺結算（killed → been_killed → can_be_killed → pending_death + death 事件）。
static func _handle_kill(core: GameCore, attacker: PieceState, victim: PieceState, anim_delay: float) -> void:
	core.stats.increment(Statistics.StatType.KILLED, attacker.uid(), 1)
	core.stats.increment(Statistics.StatType.DEATH, victim.uid(), 1)
	if attacker.abilities != null:
		attacker.abilities.run(TriggerV2.Type.ON_KILLED, AbilityContextV2.new(core, attacker, victim, 0, {}))
	if victim.abilities != null:
		victim.abilities.run(TriggerV2.Type.ON_BEEN_KILLED, AbilityContextV2.new(core, victim, attacker, 0, {"attacker": attacker}))
	if core.can_be_killed(victim):
		victim.pending_death = true
		core.event_sink.append(GameEventV2.death(victim.pos(), anim_delay))
