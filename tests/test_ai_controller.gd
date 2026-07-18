# P10-4 驗收：CPU AI 控制器（翻譯自 Python tests/test_ai_controller.py）。
# 對應 script/ai/ai_controller.gd 與 docs/rebuild/03 §1、§5。
# GameState→GameCore 對照見 ai_controller.gd 檔頭。節奏門檻由 campaign_setting.json 讀出，避免與 JSON 漂移。
extends RefCounted

var _db: Object = null

# 節奏常數（讀自 campaign_setting.json）。
var _ts: int = 0   # turn_start
var _ac: int = 0   # action
var _br: int = 0   # busy_recheck

const _P2_DECK := ["ADCW", "ADCW", "TANKW", "TANKW", "HFW", "HFW", "LFW", "ASSW", "ASSW", "APW", "APTW", "SPW"]


func _make_core() -> GameCore:
	var core := GameCore.new()
	core.setup(["ADCW"], _P2_DECK, 42, _db)
	core.turn_number = 1   # AI（player2）回合
	return core


func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func run(t: Object) -> void:
	_db = load("res://script/data/balance_db.gd").new()
	_ts = int(_db.ai("ai_delay_ms/turn_start"))
	_ac = int(_db.ai("ai_delay_ms/action"))
	_br = int(_db.ai("ai_delay_ms/busy_recheck"))

	_test_unknown_stage(t)
	_test_tick_empty_when_not_ais_turn(t)
	_test_first_observation_then_emits_after_delay(t)
	_test_ends_turn_when_no_actions(t)
	_test_throttles_between_actions(t)
	_test_paused_returns_empty(t)
	_test_waits_for_pending_events(t)
	_test_waits_for_renderer_busy(t)
	_test_prefers_lethal_attack_over_placement(t)
	_test_hoards_when_no_kill_even_when_trailing(t)
	_test_attacks_when_chip_chains_into_kill(t)
	_test_saves_attacks_when_only_low_value_chips(t)
	_test_holds_ass_in_hand(t)
	_test_prefers_ass_lethal_placement(t)
	_test_heal_not_emitted_when_no_counter(t)
	_test_heal_targets_wounded_friendly(t)
	_test_heal_skipped_when_deficit_too_small(t)
	_test_heal_picks_critical_over_lightly_chipped(t)
	_test_heal_runs_after_lethal_attack_priority(t)
	_test_focus_position_tracks_action(t)
	_test_stage_one_shot_and_per_turn_buffs(t)

	_db.free()
	_db = null


# ---------- 建構與節奏 ----------

func _test_unknown_stage(t: Object) -> void:
	# Python 端未知關卡 raise ValueError；Godot 無例外，改以 is_known_stage 判定 + valid 旗標。
	# （不在此構造未知關卡的 controller，避免 push_error 污染 runner 輸出。）
	t.ok(not AIController.is_known_stage("nonexistent_stage"), "未知關卡不被視為合法")
	t.ok(AIController.is_known_stage("white"), "white 為合法關卡")
	t.ok(AIController.new("white", _db).valid, "white 建構後 valid=true")


func _test_tick_empty_when_not_ais_turn(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.turn_number = 0   # player1 回合
	t.eq(ai.tick(core, 0), [], "非 AI 回合回傳空陣列")


func _test_first_observation_then_emits_after_delay(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.player2.hand.assign(["ADCW"])

	t.eq(ai.tick(core, 0), [], "首次觀測回傳空")
	t.eq(ai.tick(core, _ts - 1), [], "延遲未到回傳空")
	var ready: Array = ai.tick(core, _ts + 1)
	t.eq(ready.size(), 1, "延遲後送出一個行動")
	t.eq(ready[0].player, "player2", "行動屬 player2")


func _test_ends_turn_when_no_actions(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.player2.hand.clear()
	core.player2.draw_pile.clear()
	core.player2.discard_pile.clear()

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "無可用行動時送出一個")
	t.eq(actions[0].action_type, "end_turn", "無可用行動時結束回合")


func _test_throttles_between_actions(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.player2.hand.assign(["ADCW"])

	ai.tick(core, 0)
	var first: Array = ai.tick(core, _ts + 1)
	t.eq(first.size(), 1, "首個行動送出")
	t.eq(ai.tick(core, _ts + 2), [], "行動間隔內不再出手")
	var later: Array = ai.tick(core, _ts + _ac + 2)
	t.eq(later.size(), 1, "間隔後再次出手")


func _test_paused_returns_empty(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	t.eq(ai.tick(core, _ts + 10, false, true), [], "暫停時回傳空")


func _test_waits_for_pending_events(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.event_sink.append(GameEvent.move(Vector2i(0, 0), Vector2i(0, 0)))
	ai.tick(core, 0)
	t.eq(ai.tick(core, _ts + 1), [], "有未播完事件時等待")


func _test_waits_for_renderer_busy(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.player2.hand.assign(["ADCW"])
	ai.tick(core, 0, true)
	t.eq(ai.tick(core, _ts + 1, true), [], "渲染忙碌時等待")
	var after: Array = ai.tick(core, _ts + 1 + _br + 5, false)
	t.eq(after.size(), 1, "忙碌解除後出手")


# ---------- 攻擊 / 佈署決策優先序 ----------

func _test_prefers_lethal_attack_over_placement(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 1
	var attacker := _place(core, "ADCW", "player2", 1, 1)
	attacker.set_numb(false)
	var victim := _place(core, "ASSW", "player1", 1, 2)
	victim.set_numb(false)
	victim.health = 1
	core.player2.hand.assign(["TANKW"])

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "attack", "斬殺攻擊優先於佈署")
	t.eq(Vector2i(actions[0].board_x, actions[0].board_y), Vector2i(1, 1), "攻擊者座標正確")


func _test_hoards_when_no_kill_even_when_trailing(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 1
	core.player2.hand.clear()
	core.score = -7
	var attacker := _place(core, "ADCW", "player2", 0, 0)
	attacker.set_numb(false)
	var chump := _place(core, "ADCW", "player1", 1, 0)
	chump.set_numb(false)

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "end_turn", "無收頭時即使落後也存攻擊")


func _test_attacks_when_chip_chains_into_kill(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 2
	core.player2.hand.clear()
	core.score = -7
	var chipper := _place(core, "TANKW", "player2", 0, 0)
	chipper.set_numb(false)
	var finisher := _place(core, "ADCW", "player2", 3, 0)
	finisher.set_numb(false)
	var victim := _place(core, "ASSW", "player1", 1, 0)
	victim.set_numb(false)
	victim.health = 3

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "attack", "落後且削血能連段收頭時出手")


func _test_saves_attacks_when_only_low_value_chips(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 1
	core.player2.hand.clear()
	var attacker := _place(core, "TANKW", "player2", 0, 0)
	attacker.set_numb(false)
	var chump := _place(core, "TANKW", "player1", 1, 0)
	chump.set_numb(false)

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "end_turn", "只有低價值削血時存攻擊")


func _test_holds_ass_in_hand(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 0
	core.player2.hand.assign(["ASSW"])

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "end_turn", "無斬殺/防禦時 ASS 留手上")


func _test_prefers_ass_lethal_placement(t: Object) -> void:
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 0
	var victim := _place(core, "ADCW", "player1", 2, 2)
	victim.set_numb(false)
	core.player2.hand.assign(["ASSW", "ADCW"])

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "play_card", "選擇佈署")
	t.eq(core.player2.hand[actions[0].hand_index], "ASSW", "打出的是 ASSW")
	var corners := [Vector2i(1, 1), Vector2i(1, 3), Vector2i(3, 1), Vector2i(3, 3)]
	t.ok(corners.has(Vector2i(actions[0].board_x, actions[0].board_y)), "落在斬殺斜角格")


# ---------- 治療 ----------

func _test_heal_not_emitted_when_no_counter(t: Object) -> void:
	var ai := AIController.new("boss", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 0
	core.number_of_heals["player2"] = 0
	core.player2.hand.clear()
	var wounded := _place(core, "TANKW", "player2", 0, 0)
	wounded.set_numb(false)
	wounded.health = 3
	wounded.max_health = 15

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.ok(actions[0].action_type != "heal", "無治療次數時不治療")


func _test_heal_targets_wounded_friendly(t: Object) -> void:
	var ai := AIController.new("boss", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 0
	core.number_of_heals["player2"] = 1
	core.player2.hand.clear()
	var wounded := _place(core, "TANKW", "player2", 0, 0)
	wounded.set_numb(false)
	wounded.health = 3
	wounded.max_health = 15

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "heal", "有治療次數時治療受傷友軍")
	t.eq(Vector2i(actions[0].board_x, actions[0].board_y), Vector2i(0, 0), "治療座標正確")


func _test_heal_skipped_when_deficit_too_small(t: Object) -> void:
	var ai := AIController.new("boss", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 0
	core.number_of_heals["player2"] = 1
	core.player2.hand.clear()
	var almost_full := _place(core, "TANKW", "player2", 0, 0)
	almost_full.set_numb(false)
	almost_full.max_health = 15
	almost_full.health = 14

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.ok(actions[0].action_type != "heal", "缺血過少時不治療")


func _test_heal_picks_critical_over_lightly_chipped(t: Object) -> void:
	var ai := AIController.new("boss", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 0
	core.number_of_heals["player2"] = 1
	core.player2.hand.clear()
	var critical := _place(core, "TANKW", "player2", 0, 0)
	critical.set_numb(false)
	critical.max_health = 15
	critical.health = 2
	var chipped := _place(core, "TANKW", "player2", 3, 3)
	chipped.set_numb(false)
	chipped.max_health = 15
	chipped.health = 10

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "heal", "治療")
	t.eq(Vector2i(actions[0].board_x, actions[0].board_y), Vector2i(0, 0), "優先治療瀕死單位")


func _test_heal_runs_after_lethal_attack_priority(t: Object) -> void:
	var ai := AIController.new("boss", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 1
	core.number_of_heals["player2"] = 1
	core.player2.hand.clear()
	var attacker := _place(core, "ADCW", "player2", 0, 1)
	attacker.set_numb(false)
	var victim := _place(core, "ASSW", "player1", 0, 2)
	victim.set_numb(false)
	victim.health = 1
	var wounded := _place(core, "TANKW", "player2", 3, 3)
	wounded.set_numb(false)
	wounded.max_health = 15
	wounded.health = 3

	ai.tick(core, 0)
	var actions: Array = ai.tick(core, _ts + 1)
	t.eq(actions.size(), 1, "送出一個行動")
	t.eq(actions[0].action_type, "attack", "斬殺攻擊優先於治療")
	t.eq(Vector2i(actions[0].board_x, actions[0].board_y), Vector2i(0, 1), "攻擊者座標正確")


# ---------- 目標圈 / 關卡 buff ----------

func _test_focus_position_tracks_action(t: Object) -> void:
	# 攻擊行動 → 設 focus；end_turn → 清 focus。
	var ai := AIController.new("white", _db)
	var core := _make_core()
	core.number_of_attacks["player2"] = 1
	var attacker := _place(core, "ADCW", "player2", 1, 1)
	attacker.set_numb(false)
	var victim := _place(core, "ASSW", "player1", 1, 2)
	victim.set_numb(false)
	victim.health = 1
	core.player2.hand.clear()
	ai.tick(core, 0)
	ai.tick(core, _ts + 1)
	t.ok(ai.has_focus, "攻擊後有目標圈")
	t.eq(ai.focus_position, Vector2i(1, 1), "目標圈落在攻擊者")

	var ai2 := AIController.new("white", _db)
	var core2 := _make_core()
	core2.player2.hand.clear()
	core2.player2.draw_pile.clear()
	core2.player2.discard_pile.clear()
	ai2.tick(core2, 0)
	ai2.tick(core2, _ts + 1)
	t.ok(not ai2.has_focus, "end_turn 後清除目標圈")


func _test_stage_one_shot_and_per_turn_buffs(t: Object) -> void:
	# green 一次性關卡 buff：AI 起始運氣 65。
	var green := AIController.new("green", _db)
	var core := _make_core()
	core.player2.hand.assign(["ADCW"])
	green.tick(core, 0)   # 首次 tick → ensure_initialized 套用 one-shot
	t.eq(int(core.players_luck["player2"]), 65, "green 關 AI 起始運氣 65")

	# boss 起手補牌至 4 張。
	var boss := AIController.new("boss", _db)
	var core2 := _make_core()
	core2.player2.hand.clear()
	boss.tick(core2, 0)
	t.eq(core2.player2.hand.size(), 4, "boss 關起手補至 4 張")

	# orange per-turn：每 3 個 AI 回合 +1 移動（turn_number=5 → ai_turn=3）。
	var orange := AIController.new("orange", _db)
	var core3 := _make_core()
	core3.turn_number = 5
	core3.number_of_movings["player2"] = 0
	core3.player2.hand.assign(["ADCW"])
	orange.tick(core3, 0)   # 首次見到此回合 → _per_turn 套用
	t.eq(int(core3.number_of_movings["player2"]), 1, "orange 關 ai_turn=3 時 +1 移動")
