# P10-3 CPU AI 策略層（翻譯自 Python `campaign/ai_strategies/*`，見 docs/rebuild/03 §6）。
# Strategy 基底 + white（純基底）+ red/blue/green/orange 5 色 + boss 子策略。
# best_placement / best_attack 走 AIEvaluator(P10-2) + AIQuery(P10-1)；各色加成常數全讀
# campaign_setting.json 的 strategy_bonuses（`core.balance.ai("strategy_bonuses/<color>...")`），不寫死。
# 純邏輯、零 Node 依賴（RefCounted）。faction_overrides（attack_min_score）於工廠 `create()` 套用
# （對齊 Python AIController 建構時 setattr override）。GameState→GameCore 對照：
#   `.job_and_color`→`.card_id`、`.numbness/anger/moving`→`is_numb()/is_angry()/is_moving()`、
#   `gs.players_token/players_luck`→`core.players_token/players_luck`、
#   `gs.how_many_token_to_draw_a_card`→`TokenEngine.threshold(core)`、
#   `gs.neutral.on_board`→`core.neutral_pieces`、`gs.board_dict[x,y].occupy`→`core.board.occupy[Vector2i]`、
#   `gs.get_opponent_name`→`core.opponent_name`、`gs.score`→`core.score`。
class_name AIStrategy
extends RefCounted


# 佈署選擇（對齊 Python PlacementChoice dataclass）。
class Placement extends RefCounted:
	var hand_index: int
	var card_name: String
	var x: int
	var y: int
	var score: float
	func _init(hi: int, cn: String, px: int, py: int, sc: float) -> void:
		hand_index = hi
		card_name = cn
		x = px
		y = py
		score = sc


# 攻擊選擇（對齊 Python AttackChoice dataclass）。
class Attack extends RefCounted:
	var x: int
	var y: int
	var score: float
	func _init(px: int, py: int, sc: float) -> void:
		x = px
		y = py
		score = sc


# 門檻（預設對齊 campaign_setting.json thresholds；faction_overrides 於 create() 覆寫 attack_min_score）。
var placement_min_score: float = 1.0
var attack_min_score: float = 15.0


# --- 工廠：依關卡建立策略並套用 faction_overrides（見 03 §1、§6）---
static func create(stage: String, balance: Object) -> AIStrategy:
	var strat: AIStrategy
	match stage:
		"red":
			strat = RedStrategy.new()
		"blue":
			strat = BlueStrategy.new()
		"green":
			strat = GreenStrategy.new()
		"orange":
			strat = OrangeStrategy.new()
		"boss":
			strat = BossStrategy.new()
		_:
			strat = WhiteStrategy.new()

	if balance != null:
		# 先以 JSON thresholds 為基準，再套關卡 faction_overrides（僅覆寫存在的鍵）。
		var thresholds: Variant = balance.ai("thresholds")
		if typeof(thresholds) == TYPE_DICTIONARY:
			strat.placement_min_score = float(thresholds.get("placement_min_score", strat.placement_min_score))
			strat.attack_min_score = float(thresholds.get("attack_min_score", strat.attack_min_score))
		var overrides: Variant = balance.ai("faction_overrides")
		if typeof(overrides) == TYPE_DICTIONARY and overrides.has(stage):
			var ov: Dictionary = overrides[stage]
			if ov.has("attack_min_score"):
				strat.attack_min_score = float(ov["attack_min_score"])
			if ov.has("placement_min_score"):
				strat.placement_min_score = float(ov["placement_min_score"])
	return strat


# --- 基底決策（對齊 Python base.Strategy）---

# 最佳佈署：對每張可打手牌 × 每個空格跑 evaluate_placement 再加 placement_bonus，取最高。
func best_placement(core: GameCore, owner: String) -> Placement:
	var empties := AIQuery.empty_positions(core)
	if empties.is_empty():
		return null
	var player := core.get_player(owner)
	var best: Placement = null
	for hi in player.hand.size():
		var card_name: String = player.hand[hi]
		if not AIQuery.is_playable_unit_card(card_name):
			continue
		var real_name: String = card_name.substr(0, card_name.length() - 4) if card_name.ends_with(" (+)") else card_name
		for p: Vector2i in empties:
			var score: float = AIEvaluator.evaluate_placement(real_name, p, core, owner)
			score = placement_bonus(real_name, p, core, owner, score)
			if best == null or score > best.score:
				best = Placement.new(hi, card_name, p.x, p.y, score)
	return best


# 最佳攻擊：對每個我方棋子跑 evaluate_attack 再加 attack_bonus，取最高（負分/加成後 ≤0 者跳過）。
func best_attack(core: GameCore, owner: String) -> Attack:
	if int(core.number_of_attacks.get(owner, 0)) <= 0:
		return null
	var best: Attack = null
	for card: PieceState in AIQuery.friendly_cards(core, owner):
		var r := AIEvaluator.evaluate_attack(card, core)
		var score: float = r[0]
		if score < 0:
			continue
		score = attack_bonus(card, core, score)
		if score <= 0:
			continue
		if best == null or score > best.score:
			best = Attack.new(card.board_x, card.board_y, score)
	return best


# 覆寫點：預設不加成（White 即為純基底）。
func placement_bonus(_card_name: String, _position: Vector2i, _core: GameCore, _owner: String, base_score: float) -> float:
	return base_score


func attack_bonus(_attacker: PieceState, _core: GameCore, base_score: float) -> float:
	return base_score


# ===============================================================
# 各色策略子類（加成常數讀 strategy_bonuses/<color>）
# ===============================================================

class WhiteStrategy extends AIStrategy:
	pass


class RedStrategy extends AIStrategy:

	func attack_bonus(attacker: PieceState, core: GameCore, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/red")
		var bonus: float = 0.0

		var grown: int = maxi(0, attacker.damage - attacker.original_damage)
		if grown > 0:
			bonus += grown * float(b["damage_grown_per_stack"])

		if attacker.card_id == "HFR":
			bonus += float(b["hfr_baseline"])
			if attacker.is_angry():
				bonus += float(b["hfr_anger_bonus"])

		if attacker.card_id == "ADCR":
			bonus += float(b["adcr_baseline"])

		if attacker.card_id == "APR":
			bonus += float(b["apr_baseline"])
			var targets := AIQuery.attack_targets_at(core, attacker)
			if not targets.is_empty():
				var max_dmg: int = 0
				for t: PieceState in targets:
					max_dmg = maxi(max_dmg, t.damage)
				bonus += max_dmg * float(b["apr_target_damage_mult"])

		return base_score + bonus

	func placement_bonus(card_name: String, _position: Vector2i, core: GameCore, _owner: String, base_score: float) -> float:
		var p: Dictionary = core.balance.ai("strategy_bonuses/red/placement")
		return base_score + float(p.get(card_name, 0.0))


class BlueStrategy extends AIStrategy:

	# 本次攻擊預估產球數（對齊 Python expected_tokens_from_attack）。
	static func expected_tokens_from_attack(attacker: PieceState, core: GameCore) -> int:
		var targets := AIQuery.attack_targets_at(core, attacker)
		if targets.is_empty():
			return 0
		var name: String = attacker.card_id
		if name == "APB":
			return targets.size() * 2
		if name == "LFB":
			return targets.size()
		var effective: int = attacker.damage + attacker.extra_damage
		if name == "ADCB":
			var c1: int = 0
			for t: PieceState in targets:
				if t.health <= effective - maxi(0, t.armor):
					c1 += 1
			return c1
		if name == "ASSB":
			var c2: int = 0
			for t: PieceState in targets:
				if t.health <= effective - maxi(0, t.armor):
					c2 += 2
			return c2
		return 0

	func attack_bonus(attacker: PieceState, core: GameCore, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/blue")
		var tokens: int = int(core.players_token.get(attacker.owner, 0))
		var bonus: float = 0.0

		if tokens == 2:
			bonus += float(b["tokens_at_2"])
		elif tokens == 1:
			bonus += float(b["tokens_at_1"])

		if attacker.card_id == "SPB":
			bonus += float(b["spb_baseline"])

		if attacker.card_id == "HFB" and tokens >= 1:
			var targets := AIQuery.attack_targets_at(core, attacker)
			for t: PieceState in targets:
				var effective: int = (attacker.damage + tokens) - maxi(0, t.armor)
				if effective > 0 and t.health <= effective:
					bonus += float(b["hfb_kill_bonus"])
					break
				bonus += mini(effective, t.health) * float(b["hfb_chip_mult"])
			bonus = minf(bonus, float(b["hfb_cap"]))

		if attacker.card_id == "LFB":
			var lfb_targets := AIQuery.attack_targets_at(core, attacker)
			bonus += lfb_targets.size() * float(b["lfb_per_target"])

		if attacker.card_id == "ADCB" or attacker.card_id == "ASSB":
			bonus += float(b["adcb_assb_baseline"])

		var expected: int = expected_tokens_from_attack(attacker, core)
		bonus += expected * float(b["token_value"])

		var threshold: int = TokenEngine.threshold(core)
		if tokens + expected >= threshold:
			var has_armed_adcb: bool = false
			for c: PieceState in core.get_player(attacker.owner).on_board:
				if c.card_id == "ADCB" and not c.is_numb() and c.health > 0:
					has_armed_adcb = true
					break
			if has_armed_adcb:
				bonus += float(b["token_draw_chain"])

		return base_score + bonus

	func placement_bonus(card_name: String, position: Vector2i, core: GameCore, owner: String, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/blue")
		var p: Dictionary = b["placement"]
		var tokens: int = int(core.players_token.get(owner, 0))
		var x: int = position.x
		var y: int = position.y
		var bonus: float = 0.0

		if card_name == "TANKB":
			var dist: int = AIQuery.nearest_enemy_distance(core, owner, x, y)
			if dist <= 1:
				bonus += float(p["tankb_close"])
			elif dist <= 2:
				bonus += float(p["tankb_mid"])

		if card_name == "SPB":
			var my_units: int = core.get_player(owner).on_board.size() + core.get_player(owner).discard_pile.size()
			var enemies := AIQuery.enemy_cards(core, owner)
			if enemies.is_empty():
				bonus += float(p["spb_no_enemy_penalty"])
			else:
				var effective_hits: int = mini(my_units, enemies.size() * 2)
				bonus += effective_hits * float(p["spb_hit_value"])
				if enemies.size() >= 3:
					bonus += float(p["spb_mass_clear"])
				var other_unit_playables: int = 0
				for c: String in core.get_player(owner).hand:
					if c != "SPB" and AIQuery.is_playable_unit_card(c):
						other_unit_playables += 1
				bonus -= other_unit_playables * float(p["spb_other_unit_discount"])

		if card_name == "ADCB":
			if tokens == 2:
				bonus += float(p["adcb_token_2"])
			elif tokens == 1:
				bonus += float(p["adcb_token_1"])
			var engines: int = 0
			for c: PieceState in core.get_player(owner).on_board:
				if c.health > 0 and c.card_id in ["APB", "LFB", "ASSB", "TANKB", "APTB"]:
					engines += 1
			bonus += engines * float(p["adcb_per_engine"])

		if card_name == "HFB":
			if tokens == 0:
				bonus += float(p["hfb_no_token_penalty"])
			elif tokens >= 2:
				bonus += float(p["hfb_high_token"])

		if card_name == "APB":
			bonus += float(p["apb"])

		if card_name == "LFB":
			var enemies2 := AIQuery.enemy_cards(core, owner)
			var in_range_targets := AIQuery.attack_targets_from_pos(core, owner, x, y, "small_cross")
			if in_range_targets.size() >= 2:
				bonus += float(p["lfb_multi_target"])
			elif enemies2.size() >= 2:
				bonus += float(p["lfb_target_rich"])
			else:
				bonus += float(p["lfb_sparse_penalty"])

		if card_name == "APTB":
			bonus += float(p["aptb"])

		return base_score + bonus


class GreenStrategy extends AIStrategy:

	static func _lucky_blocks(core: GameCore) -> Array:
		var out: Array = []
		for c: PieceState in core.neutral_pieces:
			if c.card_id == "LUCKYBLOCK":
				out.append(c)
		return out

	static func _adjacent_empty_cells(core: GameCore, x: int, y: int) -> int:
		var count: int = 0
		for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n := Vector2i(x + d.x, y + d.y)
			if core.board.in_bounds(n) and not core.board.occupy[n]:
				count += 1
		return count

	func attack_bonus(attacker: PieceState, core: GameCore, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/green")
		var blocks := _lucky_blocks(core)

		if attacker.card_id == "LFG":
			var ax: int = attacker.board_x
			var ay: int = attacker.board_y
			var in_range: int = 0
			for bl: PieceState in blocks:
				if absi(bl.board_x - ax) + absi(bl.board_y - ay) == 1:
					in_range += 1
			if in_range > 0:
				return base_score + float(b["lfg_per_block"]) * in_range

		if attacker.card_id == "HFG":
			var ax2: int = attacker.board_x
			var ay2: int = attacker.board_y
			var in_range2: int = 0
			for bl: PieceState in blocks:
				if maxi(absi(bl.board_x - ax2), absi(bl.board_y - ay2)) == 1:
					in_range2 += 1
			if in_range2 > 0:
				return base_score + float(b["hfg_per_block"]) * in_range2

		if attacker.card_id == "ADCG":
			var row_col_empties: int = 0
			for x in BoardState.SIZE:
				for y in BoardState.SIZE:
					if (x == attacker.board_x or y == attacker.board_y) \
							and not (x == attacker.board_x and y == attacker.board_y) \
							and not core.board.occupy[Vector2i(x, y)]:
						row_col_empties += 1
			if row_col_empties > 0:
				return base_score + minf(float(b["adcg_cap"]), row_col_empties * float(b["adcg_per_empty_cell"]))

		return base_score

	func placement_bonus(card_name: String, position: Vector2i, core: GameCore, owner: String, base_score: float) -> float:
		var p: Dictionary = core.balance.ai("strategy_bonuses/green/placement")
		var x: int = position.x
		var y: int = position.y
		var blocks := _lucky_blocks(core)

		if card_name == "APTG":
			var yield_per_turn: int = _adjacent_empty_cells(core, x, y)
			return base_score + yield_per_turn * float(p["aptg_yield_mult"]) + float(p["aptg_baseline"])

		if card_name == "LFG":
			var adj_block: int = 0
			for bl: PieceState in blocks:
				if absi(bl.board_x - x) + absi(bl.board_y - y) == 1:
					adj_block += 1
			var adj_apt: int = 0
			for c: PieceState in core.get_player(owner).on_board:
				if c.card_id == "APTG" and absi(c.board_x - x) + absi(c.board_y - y) == 1:
					adj_apt += 1
			return base_score + adj_block * float(p["lfg_adj_block"]) + adj_apt * float(p["lfg_adj_apt"])

		if card_name == "HFG":
			var adj_block2: int = 0
			for bl: PieceState in blocks:
				if maxi(absi(bl.board_x - x), absi(bl.board_y - y)) == 1:
					adj_block2 += 1
			var adj_apt2: int = 0
			for c: PieceState in core.get_player(owner).on_board:
				if c.card_id == "APTG" and maxi(absi(c.board_x - x), absi(c.board_y - y)) == 1:
					adj_apt2 += 1
			return base_score + adj_block2 * float(p["hfg_adj_block"]) + adj_apt2 * float(p["hfg_adj_apt"])

		if card_name == "SPG":
			var luck: int = int(core.players_luck.get(owner, 0))
			return base_score + minf(float(p["spg_cap"]), luck * float(p["spg_luck_mult"]))

		return base_score


class OrangeStrategy extends AIStrategy:

	static func _move_reach_targets(card: PieceState, core: GameCore) -> int:
		var best: int = 0
		var dests := AIQuery.move_destinations_for(core, card)
		dests.append(Vector2i(card.board_x, card.board_y))
		for d: Vector2i in dests:
			var hits := AIQuery.attack_targets_from_pos(core, card.owner, d.x, d.y, card.attack_types)
			if hits.size() > best:
				best = hits.size()
		return best

	func attack_bonus(attacker: PieceState, core: GameCore, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/orange")
		var bonus: float = 0.0
		if attacker.card_id == "ADCO":
			bonus += base_score * float(b["adco_score_mult"])
			bonus += _move_reach_targets(attacker, core) * float(b["adco_reach_mult"])
		elif attacker.card_id == "LFO":
			bonus += float(b["lfo_baseline"])
		elif attacker.card_id == "HFO":
			bonus += float(b["hfo_baseline"])
			if attacker.extra_damage > 0:
				bonus += attacker.extra_damage * float(b["hfo_extra_damage_mult"])
			var targets := AIQuery.attack_targets_at(core, attacker)
			if targets.size() > 1:
				bonus += (targets.size() - 1) * float(b["hfo_multi_target_bonus"])
		elif attacker.card_id == "ASSO":
			if attacker.is_angry():
				bonus += float(b["asso_anger_bonus"])
			else:
				bonus += float(b["asso_setup_bonus"])
		return base_score + bonus

	func placement_bonus(card_name: String, position: Vector2i, core: GameCore, owner: String, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/orange")
		var p: Dictionary = b["placement"]
		var x: int = position.x
		var y: int = position.y
		var bonus: float = 0.0

		if card_name in ["ADCO", "LFO", "HFO", "ASSO"]:
			var w: int = BoardState.SIZE
			var h: int = BoardState.SIZE
			var cx: float = (w - 1) / 2.0
			var cy: float = (h - 1) / 2.0
			var openness: float = 4.0 - (absf(x - cx) + absf(y - cy))
			bonus += maxf(0.0, openness) * float(p["mover_openness_mult"])

		if card_name == "TANKO":
			var dist: int = AIQuery.nearest_enemy_distance(core, owner, x, y)
			if dist <= 1:
				bonus += float(p["tanko_front_line"])

		if card_name == "SPO":
			var friendly_movers: int = 0
			for c: PieceState in core.get_player(owner).on_board:
				if c.card_id in ["ADCO", "LFO", "HFO", "ASSO", "APTO"] \
						and absi(c.board_x - x) + absi(c.board_y - y) <= 2:
					friendly_movers += 1
			bonus += friendly_movers * float(p["spo_per_mover"])

		if card_name == "APTO":
			var friendly_count: int = 0
			for c: PieceState in core.get_player(owner).on_board:
				if c.health > 0:
					friendly_count += 1
			bonus += minf(friendly_count * float(p["apto_per_friendly"]), float(p["apto_cap"]))

		return base_score + bonus


class BossStrategy extends AIStrategy:

	func placement_bonus(card_name: String, _position: Vector2i, core: GameCore, owner: String, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/boss")
		var opp: String = core.opponent_name(owner)
		var opp_cards: Array = []
		for c: PieceState in core.get_player(opp).on_board:
			if c.health > 0:
				opp_cards.append(c)
		if opp_cards.is_empty():
			return base_score

		var sum_dmg: float = 0.0
		var sum_hp: float = 0.0
		for c: PieceState in opp_cards:
			sum_dmg += c.damage + c.extra_damage
			sum_hp += c.health
		var avg_dmg: float = sum_dmg / opp_cards.size()
		var avg_hp: float = sum_hp / opp_cards.size()

		var bonus: float = 0.0
		if avg_dmg >= float(b["heavy_dmg_threshold"]) and card_name.begins_with("TANK"):
			bonus += float(b["tank_vs_heavy_dmg"])
		if avg_hp >= float(b["beefy_hp_threshold"]) and card_name.begins_with("ASS"):
			bonus += float(b["ass_vs_beefy"])
		return base_score + bonus

	func attack_bonus(_attacker: PieceState, core: GameCore, base_score: float) -> float:
		var b: Dictionary = core.balance.ai("strategy_bonuses/boss")
		if core.score < int(b["trailing_threshold"]):
			return base_score + float(b["trailing_attack_bonus"])
		return base_score
