# P10-4 CPU AI 控制器（翻譯自 Python `campaign/ai_controller.py` + `boss_config.py`，見 docs/rebuild/03 §1、§5）。
# 每幀 `tick(core, now_ms, renderer_busy)` 被呼叫，回傳 0 或 1 個 GameAction（節奏用累積 msec，可 headless 測）。
# 決策層委派 AIStrategy(P10-3) / AIEvaluator(P10-2) / AIQuery(P10-1)；純邏輯、零 Node 依賴（RefCounted）。
# 所有節奏/門檻/治療/panic/關卡 buff 常數全讀 campaign_setting.json（`core.balance.ai(...)`），不寫死。
#
# GameState→GameCore 對照：
#   `gs.pending_combat_events`（未播完戰鬥事件）→ `core.event_sink`（未被表現層取走的事件）；
#   `gs.pending_attacks`→`core.pending_attacks`；`gs.paused`→ tick 的 `paused` 參數（core 無此狀態）；
#   `gs.turn_number/score`→`core.turn_number/score`；`gs.players_coin/luck`→`core.players_coin/players_luck`；
#   `gs.number_of_*`→`core.number_of_*`；`card.job_and_color`→`card.card_id`；
#   `card.numbness/moving/anger/mouse_selected`→`is_numb()/is_moving()/is_angry()/has_status("selected")`；
#   `card.instance_id`→`piece.instance_id`；`gs.board_config.is_valid_position`→`core.board.in_bounds`；
#   `gs.board_dict[x,y].occupy`→`core.board.occupy[Vector2i]`。
class_name AIController
extends RefCounted

const KNOWN_STAGES := ["white", "red", "blue", "green", "orange", "boss"]


static func is_known_stage(stage: String) -> bool:
	return KNOWN_STAGES.has(stage)


var stage: String
var player_name: String
var strategy: AIStrategy
var valid: bool = true

# AI 目標圈顯示（表現層讀取；has_focus 為 false 時無目標，見 03 §1）。
var focus_position: Vector2i = Vector2i(-1, -1)
var has_focus: bool = false

var _next_release_ms: int = 0
var _last_turn_seen: int = -1
var _initialized: bool = false
var _buffed_unit_ids: Dictionary = {}          # instance_id -> true（防重複 buff）
var _pending_upgrade_play: Array = []           # 空＝無；[hand_index, x, y]（Cyan 升級二段）

# --- 節奏（ai_delay_ms）---
var _action_delay_ms: int
var _attack_delay_ms: int
var _turn_start_delay_ms: int
var _busy_recheck_ms: int

# --- 門檻 / panic / heal ---
var _lethal_score_threshold: float
var _min_panic_threshold: float
var _panic_no_drop_below: int
var _panic_drop_per_step: float
var _heal_amount: int
var _heal_min_amount: int
var _heal_min_score: float
var _heal_low_ratio: float
var _heal_low_ratio_bonus: float
var _heal_save_base: float
var _heal_save_dmg_mult: float
var _heal_income_mult: float
var _heal_damage_mult: float


# stage：關卡色（見 KNOWN_STAGES）；balance：BalanceDB 實例（讀節奏/門檻並建 Strategy）。
func _init(stage_name: String, balance: Object, who: String = "player2") -> void:
	stage = stage_name
	player_name = who
	valid = is_known_stage(stage_name)
	if not valid:
		push_error("AIController：未知關卡 " + stage_name)
	strategy = AIStrategy.create(stage_name, balance)
	_load_settings(balance)


func _load_settings(balance: Object) -> void:
	var delays: Dictionary = balance.ai("ai_delay_ms")
	_turn_start_delay_ms = int(delays["turn_start"])
	_action_delay_ms = int(delays["action"])
	_attack_delay_ms = int(delays["attack"])
	_busy_recheck_ms = int(delays["busy_recheck"])

	_lethal_score_threshold = float(balance.ai("thresholds/lethal_score_threshold"))

	var panic: Dictionary = balance.ai("panic")
	_min_panic_threshold = float(panic["min_panic_threshold"])
	_panic_no_drop_below = int(panic["deficit_no_drop_below"])
	_panic_drop_per_step = float(panic["deficit_drop_per_step"])

	var heal: Dictionary = balance.ai("heal")
	_heal_amount = int(heal["amount"])
	_heal_min_amount = int(heal["min_amount"])
	_heal_min_score = float(heal["min_score"])
	_heal_low_ratio = float(heal["low_ratio_threshold"])
	_heal_low_ratio_bonus = float(heal["low_ratio_bonus"])
	_heal_save_base = float(heal["save_from_lethal_base"])
	_heal_save_dmg_mult = float(heal["save_from_lethal_damage_mult"])
	_heal_income_mult = float(heal["score_income_mult"])
	_heal_damage_mult = float(heal["damage_mult"])


# 主入口：回傳本幀要送出的行動陣列（0 或 1 個）。renderer_busy＝表現層動畫忙碌（scheduler.is_busy）。
func tick(core: GameCore, now_ms: int, renderer_busy: bool = false, paused: bool = false) -> Array:
	_ensure_initialized(core)
	_maintain_units(core)

	var current: String = "player1" if core.turn_number % 2 == 0 else "player2"
	if current != player_name:
		_last_turn_seen = -1
		return []
	if paused:
		return []

	if _last_turn_seen != core.turn_number:
		_last_turn_seen = core.turn_number
		_next_release_ms = now_ms + _turn_start_delay_ms
		_per_turn(core)
		return []

	if now_ms < _next_release_ms:
		return []

	if not core.event_sink.is_empty() or not core.pending_attacks.is_empty() or renderer_busy:
		_next_release_ms = now_ms + _busy_recheck_ms
		return []

	var action: GameAction = _decide_next(core)
	if action == null:
		_clear_focus()
		return []

	if action.action_type in ["play_card", "attack"] and action.board_x >= 0 and action.board_y >= 0:
		focus_position = Vector2i(action.board_x, action.board_y)
		has_focus = true
	else:
		_clear_focus()

	var delay: int = _attack_delay_ms if action.action_type == "attack" else _action_delay_ms
	_next_release_ms = now_ms + delay
	return [action]


func _clear_focus() -> void:
	has_focus = false
	focus_position = Vector2i(-1, -1)


# --- 初始化與關卡 buff（翻譯自 boss_config.py，見 03 §5、§6 stage_buffs）---

func _ensure_initialized(core: GameCore) -> void:
	if _initialized:
		return
	var p2: PlayerState = core.player2
	if p2.hand.is_empty() and p2.draw_pile.is_empty() and p2.discard_pile.is_empty():
		return
	_apply_stage_one_shots(core)
	_apply_initial_buffs(core)
	_initialized = true


func _stage_buffs(core: GameCore) -> Dictionary:
	var sb: Variant = core.balance.ai("stage_buffs")
	if typeof(sb) == TYPE_DICTIONARY and sb.has(stage):
		return sb[stage]
	return {}


# 一次性關卡環境 buff（green：AI 起始運氣 65）。
func _apply_stage_one_shots(core: GameCore) -> void:
	var buffs: Dictionary = _stage_buffs(core)
	if buffs.has("initial_luck"):
		core.players_luck["player2"] = int(buffs["initial_luck"])


# 起手手牌 buff（boss：起手補到 4 張）。
func _apply_initial_buffs(core: GameCore) -> void:
	var buffs: Dictionary = _stage_buffs(core)
	var extra_hand: int = int(buffs.get("initial_hand_size", 0))
	var p2: PlayerState = core.player2
	if extra_hand > p2.hand.size():
		var deficit: int = extra_hand - p2.hand.size()
		for _i in deficit:
			p2.draw_card(core.rng)


# 持續維護：boss 關每個新上場 AI 單位 +1 HP（記 instance_id 防重複）。
func _maintain_units(core: GameCore) -> void:
	var hp_plus: int = int(_stage_buffs(core).get("unit_hp_plus", 0))
	if hp_plus == 0:
		return
	for c: PieceState in core.player2.on_board:
		if _buffed_unit_ids.has(c.instance_id):
			continue
		c.health += hp_plus
		c.max_health += hp_plus
		_buffed_unit_ids[c.instance_id] = true


# AI 回合開始的 per-turn buff（orange：每 3 回合 +1 移動；boss：每 5 回合 +1 治療）。
func _per_turn(core: GameCore) -> void:
	if core.turn_number <= 0 or core.turn_number % 2 == 0:
		return
	var buffs: Dictionary = _stage_buffs(core)
	var ai_turn: int = (core.turn_number + 1) / 2

	var free_move_n: int = int(buffs.get("free_moving_every_n_turns", 0))
	if free_move_n != 0 and ai_turn % free_move_n == 0:
		core.number_of_movings["player2"] = int(core.number_of_movings.get("player2", 0)) + 1

	var free_heal_n: int = int(buffs.get("free_heal_every_n_turns", 0))
	if free_heal_n != 0 and ai_turn % free_heal_n == 0:
		core.number_of_heals["player2"] = int(core.number_of_heals.get("player2", 0)) + 1


# --- 有效攻擊門檻（panic 機制，見 03 §1）---

func _effective_attack_min(core: GameCore) -> float:
	var base: float = float(strategy.attack_min_score)
	var deficit: int = -core.score if player_name == "player2" else core.score
	if deficit <= _panic_no_drop_below:
		return base
	return maxf(_min_panic_threshold, base - (deficit - _panic_no_drop_below) * _panic_drop_per_step)


# --- 單步決策（嚴格優先序，見 03 §1）---

func _decide_next(core: GameCore) -> GameAction:
	if not _pending_upgrade_play.is_empty():
		var pending: Array = _pending_upgrade_play
		_pending_upgrade_play = []
		var finish: GameAction = _finish_upgrade_play(core, pending)
		if finish != null:
			return finish

	var move: GameAction = _best_move_action(core)
	if move != null:
		return move
	var start: GameAction = _start_unit_move(core)
	if start != null:
		return start
	var moveo: GameAction = _play_moveo(core)
	if moveo != null:
		return moveo

	var attack: AIStrategy.Attack = strategy.best_attack(core, player_name)
	var play: AIStrategy.Placement = strategy.best_placement(core, player_name)

	var effective_min: float = _effective_attack_min(core)
	var attack_action: GameAction = null
	if attack != null and attack.score >= effective_min:
		attack_action = GameAction.new("attack", player_name)
		attack_action.board_x = attack.x
		attack_action.board_y = attack.y

	var play_action: GameAction = null
	if play != null and play.score >= strategy.placement_min_score:
		play_action = GameAction.new("play_card", player_name)
		play_action.board_x = play.x
		play_action.board_y = play.y
		play_action.hand_index = play.hand_index

	if attack != null and attack.score >= _lethal_score_threshold and attack_action != null:
		return attack_action

	var heal_action: GameAction = _best_heal(core)
	if heal_action != null:
		return heal_action

	if play_action != null and play != null:
		var toggle: GameAction = _maybe_toggle_upgrade(core, play)
		if toggle != null:
			return toggle
		return play_action

	if attack_action != null:
		return attack_action

	return GameAction.new("end_turn", player_name)


# --- Cyan 升級二段流程（見 03 §5）---

func _maybe_toggle_upgrade(core: GameCore, play: AIStrategy.Placement) -> GameAction:
	var hand: Array = core.get_player(player_name).hand
	if not (play.hand_index >= 0 and play.hand_index < hand.size()):
		return null
	var name: String = hand[play.hand_index]
	if name.ends_with(" (+)") or not name.ends_with("C"):
		return null
	if core.balance.color_code_of(name) != "C":
		return null
	if int(core.players_coin.get(player_name, 0)) < _cyan_upgrade_price(core, name):
		return null
	_pending_upgrade_play = [play.hand_index, play.x, play.y]
	var toggle := GameAction.new("toggle_upgrade", player_name)
	toggle.hand_index = play.hand_index
	return toggle


func _finish_upgrade_play(core: GameCore, pending: Array) -> GameAction:
	var idx: int = pending[0]
	var x: int = pending[1]
	var y: int = pending[2]
	var hand: Array = core.get_player(player_name).hand
	if not (idx >= 0 and idx < hand.size() and String(hand[idx]).ends_with(" (+)")):
		return null
	var pos := Vector2i(x, y)
	if not core.board.in_bounds(pos) or core.board.occupy[pos]:
		var toggle := GameAction.new("toggle_upgrade", player_name)
		toggle.hand_index = idx
		return toggle
	var play := GameAction.new("play_card", player_name)
	play.board_x = x
	play.board_y = y
	play.hand_index = idx
	return play


# Cyan 升級版價格（見 game_core._cyan_price_check）：cost − cost_reduction × 我方升級版 SPC 張數。
func _cyan_upgrade_price(core: GameCore, card_name: String) -> int:
	var reduction: int = int(core.balance.param("SPC", "cost_reduction", 0))
	var upgraded_sp: int = 0
	for c: PieceState in core.get_player(player_name).on_board:
		if c.card_id == "SPC" and c.upgrade:
			upgraded_sp += 1
	return int(core.balance.param(card_name, "cost", 0)) - reduction * upgraded_sp


# --- 治療（見 03 §5）---

func _best_heal(core: GameCore) -> GameAction:
	if int(core.number_of_heals.get(player_name, 0)) <= 0:
		return null

	var best_score: float = _heal_min_score
	var best_target: PieceState = null
	for c: PieceState in core.get_player(player_name).on_board:
		if c.health <= 0:
			continue
		var deficit: int = c.max_health - c.health
		var heal_amount: int = mini(_heal_amount, deficit)
		if heal_amount < _heal_min_amount:
			continue

		var score: float = heal_amount * 2.0
		score += AIEvaluator.estimate_score_per_turn(c.card_id, core.balance) * _heal_income_mult
		score += c.damage * _heal_damage_mult

		var ratio: float = float(c.health) / float(maxi(1, c.max_health))
		if ratio < _heal_low_ratio:
			score += _heal_low_ratio_bonus

		var incoming: int = AIQuery.incoming_damage_at_position(core, player_name, c.board_x, c.board_y)
		if incoming >= c.health and incoming < c.health + heal_amount:
			score += _heal_save_base + c.damage * _heal_save_dmg_mult

		if score > best_score:
			best_score = score
			best_target = c

	if best_target == null:
		return null
	var action := GameAction.new("heal", player_name)
	action.board_x = best_target.board_x
	action.board_y = best_target.board_y
	return action


# --- 移動（見 03 §1、§5）---

# 場上尚無 moving 棋子時：選「最佳目的地分數 > 0」的最佳棋子 → 點它啟動移動。
func _start_unit_move(core: GameCore) -> GameAction:
	if int(core.number_of_movings.get(player_name, 0)) <= 0:
		return null
	var on_board: Array = core.get_player(player_name).on_board
	for c: PieceState in on_board:
		if c.is_moving():
			return null

	var candidates: Array = []
	for c: PieceState in on_board:
		if not c.is_numb() and c.health > 0:
			candidates.append(c)
	if candidates.is_empty():
		return null

	var best_unit: PieceState = null
	var best_val: float = -INF
	for unit: PieceState in candidates:
		var v: float = _best_dest_score(core, unit)
		if best_unit == null or v > best_val:
			best_unit = unit
			best_val = v
	if best_val <= 0:
		return null

	var action := GameAction.new("move_to", player_name)
	action.board_x = best_unit.board_x
	action.board_y = best_unit.board_y
	return action


func _best_dest_score(core: GameCore, unit: PieceState) -> float:
	var dests: Array = AIQuery.move_destinations_for(core, unit)
	if dests.is_empty():
		return -INF
	var best: float = -INF
	for d: Vector2i in dests:
		best = maxf(best, AIEvaluator.score_move_destination(unit, d, core))
	return best


# 手牌有 MOVEO 且存在可移動棋子 → 打出（board 參數隨便，效果是 movings+1）。
func _play_moveo(core: GameCore) -> GameAction:
	var hand: Array = core.get_player(player_name).hand
	var idx: int = hand.find("MOVEO")
	if idx < 0:
		return null

	var movable: bool = false
	for c: PieceState in core.get_player(player_name).on_board:
		if not c.is_numb() and c.health > 0 and not AIQuery.move_destinations_for(core, c).is_empty():
			movable = true
			break
	if not movable:
		return null
	var action := GameAction.new("play_card", player_name)
	action.board_x = 0
	action.board_y = 0
	action.hand_index = idx
	return action


# 已有 moving 棋子 → 幫它選最佳目的地（若已 selected 則直接送目的地；否則先點它）。
func _best_move_action(core: GameCore) -> GameAction:
	var movers: Array = AIQuery.units_with_pending_move(core, player_name)
	if movers.is_empty():
		return null

	var selected: Array = []
	for m: PieceState in movers:
		if m.has_status("selected"):
			selected.append(m)

	if not selected.is_empty():
		var unit: PieceState = selected[0]
		var dests: Array = AIQuery.move_destinations_for(core, unit)
		if dests.is_empty():
			return null
		var best_dest: Vector2i = dests[0]
		var best_score: float = -INF
		for d: Vector2i in dests:
			var sc: float = AIEvaluator.score_move_destination(unit, d, core)
			if sc > best_score:
				best_score = sc
				best_dest = d
		var action := GameAction.new("move_to", player_name)
		action.board_x = best_dest.x
		action.board_y = best_dest.y
		return action

	var best_unit: PieceState = null
	var best_val: float = -INF
	for unit: PieceState in movers:
		var v: float = _best_dest_score(core, unit)
		if best_unit == null or v > best_val:
			best_unit = unit
			best_val = v
	if best_val == -INF:
		return null
	var start_action := GameAction.new("move_to", player_name)
	start_action.board_x = best_unit.board_x
	start_action.board_y = best_unit.board_y
	return start_action
