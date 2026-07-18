# P10-2 CPU AI 佈署/攻擊評分層（翻譯自 Python `campaign/ai_evaluator.py`，見 docs/rebuild/03 §3–§5）。
# 全部為純函式（static），吃 GameCore/BalanceDB 狀態、不碰 Node；幾何查詢委派 AIQuery（P10-1）。
# 可調常數（scoring / threat_model）全由 campaign_setting.json 讀取，不寫死（見 03 §8）；
# Python 端本就硬編碼的評分係數（0.5 / 1.5 / 100 …）與 WASTED_CHIP_PENALTY 同樣以字面值對齊原始碼。
# 顏色以 Godot canonical 的「色碼」回傳（"W"）而非 Python 的「色名」（"White"）——本專案 job_of/
# color_code_of 皆用色碼，評分邏輯只讀職業碼、不比較色名，故等價。
class_name AIEvaluator
extends RefCounted


const NON_ATTACKING_CARDS := ["APTG"]        # 不主動攻擊的卡（評分直接判 -1）
const JOBS_ATTACK_ON_DEPLOY := ["ASS"]       # 入場不暈眩、可同回合攻擊
const PRIORITY_TARGET_JOBS := ["ADC", "SP"]  # 優先擊殺目標
const SQUISHY_DPS_JOBS := ["ADC", "AP", "SP"]  # 需前排保護的脆皮輸出
const WASTED_CHIP_PENALTY := 18.0            # 浪費削血懲罰（Python 端硬編碼）
const AOE_DETERMINISTIC_TAGS := ["small_cross", "small_x", "large_cross"]  # 確定性 AOE 攻擊模式


# --- 名稱解析與基礎數值 ---

# 回傳 [職業碼, 色碼]（如 ["ADC","W"]）；未知/特殊卡回 ["", ""]（對齊 Python parse_card_name 空回傳）。
static func parse_card_name(card_name: String, balance: Object) -> Array:
	return [balance.job_of(card_name), balance.color_code_of(card_name)]


# 回傳 [health, damage]（基礎數值，來自 BalanceDB）；未知回 [0, 0]。
static func card_base_stats(card_name: String, balance: Object) -> Array:
	var s: Dictionary = balance.stats(card_name)
	if s.is_empty():
		return [0, 0]
	return [int(s.get("health", 0)), int(s.get("damage", 0))]


# 每回合預估得分：中立/魔法卡 0；SP 為 1 + extra_score；一般單位 1。
static func estimate_score_per_turn(card_name: String, balance: Object) -> int:
	var job: String = balance.job_of(card_name)
	if job == "":
		return 0
	if job in ["CUBE", "CUBES", "HEAL", "MOVE", "MOVEO", "LUCKYBLOCK"]:
		return 0
	if job == "SP":
		return 1 + int(balance.param(card_name, "extra_score", 0))
	return 1


static func score_income_bonus(card_name: String, balance: Object) -> float:
	return estimate_score_per_turn(card_name, balance) * float(balance.ai("scoring/score_income_multiplier"))


# 擊殺該目標可否認對手的每回合得分（＝以目標得分力換算的收益）。
static func attack_denial_bonus(target: PieceState, balance: Object) -> float:
	return score_income_bonus(target.card_id, balance)


static func target_priority_bonus(target: PieceState) -> float:
	return 5.0 if target.job in PRIORITY_TARGET_JOBS else 0.0


# 怒氣中的 HFR＝不死身（斬殺判定視為殺不掉）。
static func _is_anger_immortal(card: PieceState) -> bool:
	return card.card_id == "HFR" and card.is_angry()


static func _is_deterministic_aoe(attack_types: String) -> bool:
	if attack_types == "":
		return false
	for at in attack_types.split(" ", false):
		if not (at in AOE_DETERMINISTIC_TAGS):
			return false
	return true


# --- 佈署評分子項（見 03 §3）---

# 補刀獎勵：我方尚有第二次攻擊、且另一單位能收掉這口血後的殘血 → +15 + 目標ATK×2。
static func followup_kill_bonus(attacker: PieceState, target: PieceState, core: GameCore, chip_damage: int) -> float:
	if int(core.number_of_attacks.get(attacker.owner, 0)) < 2:
		return 0.0
	var remaining: int = target.health - chip_damage
	if remaining <= 0:
		return 0.0
	var armor: int = maxi(0, target.armor)
	for other: PieceState in core.get_player(attacker.owner).on_board:
		if other == attacker or other.is_numb() or other.health <= 0:
			continue
		if other.card_id in NON_ATTACKING_CARDS:
			continue
		if not AIQuery.attack_targets_at(core, other).has(target):
			continue
		var other_dmg: int = other.damage + other.extra_damage
		if remaining + armor <= other_dmg:
			return 15.0 + target.damage * 2.0
	return 0.0


# 防禦佈署：佔住「能斜角威脅到我方脆皮的空格」→ 每保住一隻 + 該友方 ATK×6 + HP×1.5。
static func defensive_placement_bonus(_card_name: String, position: Vector2i, core: GameCore, owner: String) -> float:
	var saved: Array = []
	for friendly: PieceState in AIQuery.friendly_cards(core, owner):
		if AIQuery.cells_threatening_card(core, friendly).has(position):
			saved.append(friendly)
	if saved.is_empty():
		return 0.0
	var total: float = 0.0
	for f: PieceState in saved:
		total += f.damage * 6.0 + f.health * 1.5
	return total


# 威脅投射：從該位置可打到的目標 → Σ(min(ATK,目標HP)×0.3 + 目標ATK×0.5)；非入場攻擊職業再 ×0.6。
static func threat_placement_bonus(card_name: String, position: Vector2i, core: GameCore, owner: String) -> float:
	var job: String = core.balance.job_of(card_name)
	var attack_types: String = core.balance.attack_types(job)
	if attack_types == "" or attack_types == "None":
		return 0.0
	var damage: int = card_base_stats(card_name, core.balance)[1]
	if damage <= 0:
		return 0.0
	var targets := AIQuery.attack_targets_from_pos(core, owner, position.x, position.y, attack_types)
	if targets.is_empty():
		return 0.0
	var total: float = 0.0
	for t: PieceState in targets:
		total += mini(damage, t.health) * 0.3 + t.damage * 0.5
	if not (job in JOBS_ATTACK_ON_DEPLOY):
		total *= 0.6
	return total


# 被打風險：該格預估承傷 ≥ 自身 HP → 大扣；否則按承傷線性扣。
static func incoming_damage_penalty(card_name: String, position: Vector2i, core: GameCore, owner: String) -> float:
	var incoming: int = AIQuery.incoming_damage_at_position(core, owner, position.x, position.y)
	if incoming <= 0:
		return 0.0
	var health: int = card_base_stats(card_name, core.balance)[0]
	if health <= 0:
		return 0.0
	if incoming >= health:
		return -float(core.balance.ai("threat_model/incoming_kill_penalty"))
	return -incoming * float(core.balance.ai("threat_model/incoming_chip_penalty_per_damage"))


# 手牌保留懲罰：某些卡（ASS）留手上當威脅更值錢，打出時扣分。
static func hand_threat_penalty(card_name: String, balance: Object) -> float:
	var job: String = balance.job_of(card_name)
	var htv: Dictionary = balance.ai("scoring/hand_threat_value")
	return -float(htv.get(job, 0.0))


# 怕刺客：脆皮（HP ≤ ASS_THREAT_DAMAGE）周圍每個空的斜角格＝對手可佈署 ASS 秒殺的位置，扣分。
static func future_ass_threat_penalty(card_name: String, position: Vector2i, core: GameCore) -> float:
	var health: int = card_base_stats(card_name, core.balance)[0]
	var ass_threat: int = int(core.balance.ai("threat_model/ass_threat_damage"))
	if health <= 0 or health > ass_threat:
		return 0.0
	var vulnerable: int = 0
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
		var n := Vector2i(position.x + d.x, position.y + d.y)
		if core.board.in_bounds(n) and not core.board.occupy[n]:
			vulnerable += 1
	if vulnerable == 0:
		return 0.0
	var score_per_turn: int = estimate_score_per_turn(card_name, core.balance)
	return -float(vulnerable) * (3.0 + score_per_turn * 1.5)


# 保護需求：脆皮輸出（ADC/AP/SP）——我方有夠肉的前排 → +4；沒有 → −12。
static func protection_bonus(card_name: String, core: GameCore, owner: String) -> float:
	var job: String = core.balance.job_of(card_name)
	if not (job in SQUISHY_DPS_JOBS):
		return 0.0
	var ass_threat: int = int(core.balance.ai("threat_model/ass_threat_damage"))
	var has_front_line: bool = false
	for c: PieceState in core.get_player(owner).on_board:
		if c.health > ass_threat:
			has_front_line = true
			break
	return 4.0 if has_front_line else -12.0


# 覆蓋範圍：可打到的格數 × 0.8（nearest/farthest 依敵而定 → 0）。
static func reach_bonus(card_name: String, position: Vector2i, core: GameCore) -> float:
	var job: String = core.balance.job_of(card_name)
	if job == "":
		return 0.0
	var attack_types: String = core.balance.attack_types(job)
	if attack_types == "" or attack_types == "None":
		return 0.0
	var cells: int = AIQuery.attack_coverage_cells(core, position.x, position.y, attack_types)
	return cells * 0.8


# 斬殺佈署：僅 ASS（入場先攻）——從該位置能一擊斬殺的最佳目標 → +100 + 目標ATK×10 + 得分否認 + 優先加成。
static func lethal_placement_bonus(card_name: String, position: Vector2i, core: GameCore, owner: String) -> float:
	var job: String = core.balance.job_of(card_name)
	if not (job in JOBS_ATTACK_ON_DEPLOY):
		return 0.0
	var damage: int = card_base_stats(card_name, core.balance)[1]
	if damage <= 0:
		return 0.0
	var attack_types: String = core.balance.attack_types(job)
	if attack_types == "":
		return 0.0
	var kill_base: float = float(core.balance.ai("scoring/kill_bonus_base"))
	var kill_per_threat: float = float(core.balance.ai("scoring/kill_bonus_per_threat"))
	var targets := AIQuery.attack_targets_from_pos(core, owner, position.x, position.y, attack_types)
	var best_bonus: float = 0.0
	for target: PieceState in targets:
		if _is_anger_immortal(target):
			continue
		var effective_damage: int = damage - maxi(0, target.armor)
		if effective_damage <= 0:
			continue
		if target.health <= effective_damage:
			var bonus: float = (
				kill_base
				+ target.damage * kill_per_threat
				+ attack_denial_bonus(target, core.balance)
				+ target_priority_bonus(target)
			)
			if bonus > best_bonus:
				best_bonus = bonus
	return best_bonus


# --- 佈署評分主入口（見 03 §3）---

static func evaluate_placement(card_name: String, position: Vector2i, core: GameCore, owner: String) -> float:
	if not core.board.in_bounds(position):
		return -1000.0
	if core.board.occupy[position]:
		return -1000.0

	var stats := card_base_stats(card_name, core.balance)
	var health: int = stats[0]
	var damage: int = stats[1]
	var score: float = 0.0

	score += health * 0.5 + damage * 1.5

	var safety: float = AIQuery.position_safety(position.x, position.y)
	var job: String = core.balance.job_of(card_name)
	if job == "SP":
		score += safety * 4.0
	elif job == "TANK" or job == "HF":
		score += safety * 1.0
	elif job == "ASS":
		score += safety * 0.5
	else:
		score += safety * 2.0

	var dist: int = AIQuery.nearest_enemy_distance(core, owner, position.x, position.y)
	if (job == "ASS" or job == "LF") and dist <= 2:
		score += 2.0
	if (job == "TANK" or job == "HF") and dist <= 1:
		score += 3.0
	if job == "SP" and dist <= 2:
		score -= 5.0

	score += lethal_placement_bonus(card_name, position, core, owner)
	score += defensive_placement_bonus(card_name, position, core, owner)
	score += threat_placement_bonus(card_name, position, core, owner)
	score += incoming_damage_penalty(card_name, position, core, owner)
	score += hand_threat_penalty(card_name, core.balance)
	score += score_income_bonus(card_name, core.balance)
	score += reach_bonus(card_name, position, core)
	score += future_ass_threat_penalty(card_name, position, core)
	score += protection_bonus(card_name, core, owner)

	return score


# --- 移動目的地評分（見 03 §5）---

static func score_move_destination(card: PieceState, dest: Vector2i, core: GameCore) -> float:
	var targets := AIQuery.attack_targets_from_pos(core, card.owner, dest.x, dest.y, card.attack_types)

	if card.card_id == "ADCO":
		var s: float = 0.0
		for t: PieceState in targets:
			s += mini(card.damage, t.health) * 2.0
		return s

	if card.card_id == "LFO":
		var enemies := AIQuery.enemy_cards(core, card.owner)
		if enemies.is_empty():
			return 0.0
		var nearest: int = -1
		for e: PieceState in enemies:
			var d: int = AIQuery.manhattan(dest, e.pos())
			nearest = d if nearest < 0 else mini(nearest, d)
		return 6.0 - nearest

	if card.card_id == "HFO":
		var projected_damage: int = card.damage + card.extra_damage + 1
		return AIQuery.position_safety(dest.x, dest.y) + targets.size() * projected_damage * 0.6

	if card.card_id == "ASSO":
		for t: PieceState in targets:
			var effective: int = card.damage - maxi(0, t.armor)
			if effective > 0 and t.health <= effective:
				return 20.0 + t.damage * 2.0
		return float(targets.size() * 2.0)

	return float(targets.size() * 1.5)


# --- 攻擊評分主入口（見 03 §4）---
# 回傳 [best_score: float, best_target: PieceState | null]。
static func evaluate_attack(attacker: PieceState, core: GameCore) -> Array:
	if attacker.is_numb():
		return [-1.0, null]
	if attacker.card_id in NON_ATTACKING_CARDS:
		return [-1.0, null]

	var targets := AIQuery.attack_targets_at(core, attacker)
	if targets.is_empty():
		return [-1.0, null]

	var best_score: float = -INF
	var best_target: PieceState = null
	var attacker_immortal: bool = _is_anger_immortal(attacker)
	var projected: int = AIQuery.projected_incoming_damage(core, attacker.owner, attacker.board_x, attacker.board_y)
	var attacker_doomed: bool = not attacker_immortal and attacker.health <= projected
	var deterministic_aoe: bool = _is_deterministic_aoe(attacker.attack_types)
	var aggregate_score: float = 0.0

	for target: PieceState in targets:
		var s: float = 0.0
		var effective_damage: int = attacker.damage + attacker.extra_damage

		if target.armor >= effective_damage:
			s += 5.0
		elif target.health <= effective_damage - maxi(0, target.armor) and not _is_anger_immortal(target):
			s += 100.0 + target.damage * 10.0 + attack_denial_bonus(target, core.balance)
		else:
			s += mini(effective_damage, target.health) * 2.0
			var followup: float = followup_kill_bonus(attacker, target, core, effective_damage)
			s += followup
			if followup == 0.0 and not attacker_doomed:
				s -= WASTED_CHIP_PENALTY

		s += target.damage * 3.0
		s += target_priority_bonus(target)

		if target.damage >= attacker.health and not target.is_numb() and not attacker_immortal and not attacker_doomed:
			s -= 50.0

		if target.is_numb():
			s -= 20.0

		if s > best_score:
			best_score = s
			best_target = target

		if deterministic_aoe:
			aggregate_score += s

	if deterministic_aoe and aggregate_score > best_score:
		best_score = aggregate_score

	return [best_score, best_target]
