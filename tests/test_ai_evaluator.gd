# P10-2 驗收：CPU AI 佈署/攻擊評分層（翻譯自 Python tests/test_ai_evaluator.py）。
# 對應 script/ai/ai_evaluator.gd 與 docs/rebuild/03 §3–§5。
# _place 對齊 Python helpers.place_card：以 PieceState.make（工廠預設暈眩：非 ASS 入場暈眩）
# 佈署、佔格，不強制翻轉狀態；各案例照 Python 原案例顯式設定 numbness。
# 原 Python 檔中 2 個透過 WhiteStrategy.best_placement 的案例（strategy_prefers_tank /
# releases_adc）改以「白色基底 best_placement＝對手牌×空格取 evaluate_placement 最大」的
# 純評分等價實作（_white_best_placement）驗證，避免前置 P10-3 的 Strategy 類別。
extends RefCounted

# 全檔共用一個 BalanceDB（extends Node），於 run() 結尾釋放，避免累積 orphan（見 09 §11）。
var _db: Object = null


func _make_core() -> GameCore:
	var core := GameCore.new()
	core.setup(["ADCW"], ["ADCW"], 42, _db)
	return core


# 佈署一顆棋子（工廠預設暈眩、佔格）。owner=neutral 進 neutral_pieces。
func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


# 白色基底 best_placement 等價：對每張手牌 × 每個空格取 evaluate_placement 最大者的卡名（白色無 placement_bonus）。
func _white_best_placement(core: GameCore, owner: String, hand: Array) -> String:
	var best_name: String = ""
	var best_score: float = -INF
	for card_name: String in hand:
		for p: Vector2i in AIQuery.empty_positions(core):
			var s: float = AIEvaluator.evaluate_placement(card_name, p, core, owner)
			if s > best_score:
				best_score = s
				best_name = card_name
	return best_name


func run(t: Object) -> void:
	_db = load("res://script/data/balance_db.gd").new()

	_test_parse_card_name_white_adc(t)
	_test_parse_card_name_unknown_returns_empty(t)
	_test_card_base_stats_returns_health_damage(t)
	_test_evaluate_placement_rejects_occupied_position(t)
	_test_evaluate_placement_rejects_out_of_bounds(t)
	_test_evaluate_placement_sp_prefers_corner_far_from_enemies(t)
	_test_evaluate_placement_tank_prefers_near_enemies(t)
	_test_evaluate_attack_returns_zero_if_no_targets(t)
	_test_evaluate_attack_returns_negative_for_numb_attacker(t)
	_test_evaluate_attack_rewards_kill(t)
	_test_evaluate_attack_picks_higher_threat_target_when_tie(t)
	_test_lethal_placement_bonus_for_ass_adjacent_to_killable_enemy(t)
	_test_lethal_placement_bonus_zero_when_not_in_range(t)
	_test_lethal_placement_bonus_zero_for_numb_on_deploy_cards(t)
	_test_defensive_placement_bonus_blocks_ass_kill_spot(t)
	_test_defensive_placement_bonus_zero_for_unrelated_position(t)
	_test_defensive_placement_bonus_sums_when_blocking_saves_multiple(t)
	_test_ai_picks_blocker_over_safe_corner_when_adc_is_threatened(t)
	_test_threat_placement_bonus_rewards_having_targets_in_range(t)
	_test_estimate_score_per_turn_normal_unit(t)
	_test_estimate_score_per_turn_sp_uses_extra_score(t)
	_test_estimate_score_per_turn_zero_for_neutrals_and_spells(t)
	_test_score_income_bonus_higher_for_sp(t)
	_test_evaluate_attack_kill_bonus_higher_for_sp_than_equal_damage_unit(t)
	_test_evaluate_placement_sp_outscores_equivalent_unit_for_score_income(t)
	_test_protection_bonus_penalizes_unprotected_squishy_dps(t)
	_test_protection_bonus_rewards_dps_with_front_line(t)
	_test_protection_bonus_zero_for_tank_class(t)
	_test_strategy_prefers_tank_over_adc_on_empty_board(t)
	_test_strategy_releases_adc_after_tank_is_down(t)
	_test_future_ass_threat_penalty_scales_with_empty_diagonal_neighbors(t)
	_test_future_ass_threat_zero_for_high_hp_units(t)
	_test_future_ass_threat_zero_when_diagonal_neighbors_occupied(t)
	_test_adcw_placement_prefers_corner_over_center_under_ass_threat(t)
	_test_hf_placement_prefers_center_over_corner_due_to_reach(t)
	_test_reach_bonus_zero_for_nearest_attackers(t)
	_test_evaluate_placement_avoids_immediate_kill_spot(t)
	_test_hand_threat_penalty_applies_to_ass(t)
	_test_ass_placement_without_kill_or_defense_skipped_after_threshold(t)
	_test_evaluate_placement_ass_lethal_outscores_safe_corner_placement(t)

	_db.free()
	_db = null


func _test_parse_card_name_white_adc(t: Object) -> void:
	var r := AIEvaluator.parse_card_name("ADCW", _db)
	t.eq(r[0], "ADC", "parse 職業碼 ADC")
	t.eq(r[1], "W", "parse 色碼 W")


func _test_parse_card_name_unknown_returns_empty(t: Object) -> void:
	var r := AIEvaluator.parse_card_name("HEAL", _db)
	t.eq(r[0], "", "未知卡職業空")
	t.eq(r[1], "", "未知卡色碼空")


func _test_card_base_stats_returns_health_damage(t: Object) -> void:
	var r := AIEvaluator.card_base_stats("ADCW", _db)
	t.ok(r[0] > 0, "ADCW health>0")
	t.ok(r[1] > 0, "ADCW damage>0")


func _test_evaluate_placement_rejects_occupied_position(t: Object) -> void:
	var core := _make_core()
	_place(core, "TANKW", "player1", 1, 1)
	var score := AIEvaluator.evaluate_placement("ADCW", Vector2i(1, 1), core, "player2")
	t.ok(score < 0, "佔用格 < 0")


func _test_evaluate_placement_rejects_out_of_bounds(t: Object) -> void:
	var core := _make_core()
	var score := AIEvaluator.evaluate_placement("ADCW", Vector2i(5, 5), core, "player2")
	t.ok(score < 0, "界外 < 0")


func _test_evaluate_placement_sp_prefers_corner_far_from_enemies(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player1", 0, 0)
	var corner_far := AIEvaluator.evaluate_placement("SPW", Vector2i(3, 3), core, "player2")
	var center := AIEvaluator.evaluate_placement("SPW", Vector2i(2, 2), core, "player2")
	t.ok(corner_far > center, "SP 偏好遠角落")


func _test_evaluate_placement_tank_prefers_near_enemies(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player1", 0, 0)
	var near := AIEvaluator.evaluate_placement("TANKW", Vector2i(1, 0), core, "player2")
	var far := AIEvaluator.evaluate_placement("TANKW", Vector2i(3, 3), core, "player2")
	t.ok(near > far, "TANK 偏好貼近敵人")


func _test_evaluate_attack_returns_zero_if_no_targets(t: Object) -> void:
	var core := _make_core()
	var attacker := _place(core, "TANKW", "player1", 0, 0)
	attacker.set_numb(false)
	_place(core, "TANKW", "player2", 3, 3)
	var r := AIEvaluator.evaluate_attack(attacker, core)
	t.ok(float(r[0]) <= 0, "無目標 score<=0")
	t.eq(r[1], null, "無目標 target null")


func _test_evaluate_attack_returns_negative_for_numb_attacker(t: Object) -> void:
	var core := _make_core()
	var attacker := _place(core, "ADCW", "player1", 1, 1)   # ADC 入場暈眩
	_place(core, "TANKW", "player2", 1, 2)
	var r := AIEvaluator.evaluate_attack(attacker, core)
	t.ok(float(r[0]) < 0, "暈眩攻擊者 score<0")


func _test_evaluate_attack_rewards_kill(t: Object) -> void:
	var core := _make_core()
	var attacker := _place(core, "ADCW", "player1", 1, 1)
	attacker.set_numb(false)
	var victim := _place(core, "ASSW", "player2", 1, 2)
	var r := AIEvaluator.evaluate_attack(attacker, core)
	t.ok(float(r[0]) > 100, "斬殺 score>100")
	t.eq(r[1], victim, "目標為受害者")


func _test_evaluate_attack_picks_higher_threat_target_when_tie(t: Object) -> void:
	var core := _make_core()
	var attacker := _place(core, "ADCW", "player1", 1, 1)
	attacker.set_numb(false)
	var weak := _place(core, "TANKW", "player2", 0, 1)
	weak.set_numb(false)
	var strong := _place(core, "ADCW", "player2", 1, 0)
	strong.set_numb(false)
	var r := AIEvaluator.evaluate_attack(attacker, core)
	t.eq(r[1], strong, "選較高威脅目標")
	t.ok(float(r[0]) > 0, "score>0")


func _test_lethal_placement_bonus_for_ass_adjacent_to_killable_enemy(t: Object) -> void:
	var core := _make_core()
	var victim := _place(core, "ADCW", "player1", 2, 2)
	victim.set_numb(false)
	var score := AIEvaluator.lethal_placement_bonus("ASSW", Vector2i(1, 1), core, "player2")
	t.ok(score >= 100.0, "ASS 斬殺佈署 >=100")


func _test_lethal_placement_bonus_zero_when_not_in_range(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player1", 0, 0)
	var score := AIEvaluator.lethal_placement_bonus("ASSW", Vector2i(3, 3), core, "player2")
	t.eq(score, 0.0, "範圍外 0")


func _test_lethal_placement_bonus_zero_for_numb_on_deploy_cards(t: Object) -> void:
	var core := _make_core()
	var victim := _place(core, "ASSW", "player1", 1, 1)
	victim.set_numb(false)
	victim.health = 1
	for card_name in ["ADCW", "TANKW", "HFW", "LFW", "APTW"]:
		var score := AIEvaluator.lethal_placement_bonus(card_name, Vector2i(1, 2), core, "player2")
		t.eq(score, 0.0, "%s 入場暈眩無斬殺加成" % card_name)


func _test_defensive_placement_bonus_blocks_ass_kill_spot(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player2", 3, 0)
	var bonus := AIEvaluator.defensive_placement_bonus("TANKW", Vector2i(2, 1), core, "player2")
	t.ok(bonus > 0, "堵住斬殺格 >0")


func _test_defensive_placement_bonus_zero_for_unrelated_position(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player2", 3, 0)
	var bonus := AIEvaluator.defensive_placement_bonus("TANKW", Vector2i(0, 3), core, "player2")
	t.eq(bonus, 0.0, "無關位置 0")


func _test_defensive_placement_bonus_sums_when_blocking_saves_multiple(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player2", 1, 0)
	_place(core, "ADCW", "player2", 1, 2)
	# ASS 於 (2,1) small_x 可打 (1,0)(3,0)(1,2)(3,2) — 兩隻 ADC 都被威脅。
	var one := AIEvaluator.defensive_placement_bonus("TANKW", Vector2i(2, 1), core, "player2")
	var core2 := _make_core()
	_place(core2, "ADCW", "player2", 1, 0)
	var single := AIEvaluator.defensive_placement_bonus("TANKW", Vector2i(2, 1), core2, "player2")
	t.ok(one > single, "同時保住兩隻 > 一隻")


func _test_ai_picks_blocker_over_safe_corner_when_adc_is_threatened(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player2", 3, 0)
	var block_spot := AIEvaluator.evaluate_placement("TANKW", Vector2i(2, 1), core, "player2")
	var safe_corner := AIEvaluator.evaluate_placement("TANKW", Vector2i(0, 3), core, "player2")
	t.ok(block_spot > safe_corner, "堵斬殺格 > 安全角落")


func _test_threat_placement_bonus_rewards_having_targets_in_range(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player1", 0, 0)
	var in_range := AIEvaluator.threat_placement_bonus("ASSW", Vector2i(1, 1), core, "player2")
	var no_targets := AIEvaluator.threat_placement_bonus("ASSW", Vector2i(3, 3), core, "player2")
	t.ok(in_range > no_targets, "有目標 > 無目標")


func _test_estimate_score_per_turn_normal_unit(t: Object) -> void:
	t.eq(AIEvaluator.estimate_score_per_turn("ADCW", _db), 1, "ADCW 得分 1")
	t.eq(AIEvaluator.estimate_score_per_turn("TANKW", _db), 1, "TANKW 得分 1")
	t.eq(AIEvaluator.estimate_score_per_turn("ASSW", _db), 1, "ASSW 得分 1")


func _test_estimate_score_per_turn_sp_uses_extra_score(t: Object) -> void:
	t.eq(AIEvaluator.estimate_score_per_turn("SPW", _db), 2, "SPW 得分 2（extra_score=1）")


func _test_estimate_score_per_turn_zero_for_neutrals_and_spells(t: Object) -> void:
	t.eq(AIEvaluator.estimate_score_per_turn("CUBE", _db), 0, "CUBE 得分 0")
	t.eq(AIEvaluator.estimate_score_per_turn("HEAL", _db), 0, "HEAL 得分 0")
	t.eq(AIEvaluator.estimate_score_per_turn("MOVE", _db), 0, "MOVE 得分 0")


func _test_score_income_bonus_higher_for_sp(t: Object) -> void:
	t.ok(AIEvaluator.score_income_bonus("SPW", _db) > AIEvaluator.score_income_bonus("ADCW", _db), "SP 得分收益較高")


func _test_evaluate_attack_kill_bonus_higher_for_sp_than_equal_damage_unit(t: Object) -> void:
	var core := _make_core()
	var attacker := _place(core, "ADCW", "player1", 1, 1)
	attacker.set_numb(false)
	var sp_target := _place(core, "SPW", "player2", 1, 0)
	sp_target.set_numb(false)
	var sp_r := AIEvaluator.evaluate_attack(attacker, core)

	var core2 := _make_core()
	var attacker2 := _place(core2, "ADCW", "player1", 1, 1)
	attacker2.set_numb(false)
	var ass_target := _place(core2, "ASSW", "player2", 1, 0)
	ass_target.set_numb(false)
	ass_target.damage = 5   # 與 SP 同攻擊力以做公平比較
	var ass_r := AIEvaluator.evaluate_attack(attacker2, core2)

	t.ok(float(sp_r[0]) > float(ass_r[0]), "殺 SP 收益 > 殺同攻非得分卡")


func _test_evaluate_placement_sp_outscores_equivalent_unit_for_score_income(t: Object) -> void:
	var core := _make_core()
	var sp_score := AIEvaluator.evaluate_placement("SPW", Vector2i(0, 0), core, "player2")
	var ass_score := AIEvaluator.evaluate_placement("ASSW", Vector2i(3, 3), core, "player2")
	t.ok(sp_score > ass_score, "SP 佈署因得分收益勝出")


func _test_protection_bonus_penalizes_unprotected_squishy_dps(t: Object) -> void:
	var core := _make_core()
	t.ok(AIEvaluator.protection_bonus("ADCW", core, "player2") < 0, "無前排 ADC 扣分")
	t.ok(AIEvaluator.protection_bonus("SPW", core, "player2") < 0, "無前排 SP 扣分")
	t.ok(AIEvaluator.protection_bonus("APW", core, "player2") < 0, "無前排 AP 扣分")


func _test_protection_bonus_rewards_dps_with_front_line(t: Object) -> void:
	var core := _make_core()
	_place(core, "TANKW", "player2", 0, 0)
	t.ok(AIEvaluator.protection_bonus("ADCW", core, "player2") > 0, "有前排 ADC 加分")


func _test_protection_bonus_zero_for_tank_class(t: Object) -> void:
	var core := _make_core()
	t.eq(AIEvaluator.protection_bonus("TANKW", core, "player2"), 0.0, "TANK 不受保護門檻約束")
	t.eq(AIEvaluator.protection_bonus("HFW", core, "player2"), 0.0, "HF 不受保護門檻約束")
	t.eq(AIEvaluator.protection_bonus("LFW", core, "player2"), 0.0, "LF 不受保護門檻約束")


func _test_strategy_prefers_tank_over_adc_on_empty_board(t: Object) -> void:
	var core := _make_core()
	var best := _white_best_placement(core, "player2", ["ADCW", "TANKW"])
	t.eq(best, "TANKW", "空盤首佈署選 TANK")


func _test_strategy_releases_adc_after_tank_is_down(t: Object) -> void:
	var core := _make_core()
	_place(core, "TANKW", "player2", 0, 0)
	var best := _white_best_placement(core, "player2", ["ADCW"])
	t.eq(best, "ADCW", "前排就位後放 ADC")


func _test_future_ass_threat_penalty_scales_with_empty_diagonal_neighbors(t: Object) -> void:
	var core := _make_core()
	var center := AIEvaluator.future_ass_threat_penalty("ADCW", Vector2i(1, 1), core)
	var corner := AIEvaluator.future_ass_threat_penalty("ADCW", Vector2i(0, 0), core)
	t.ok(center < corner, "中央比角落更負")
	t.ok(center < 0, "中央 <0")
	t.ok(corner < 0, "角落 <0")


func _test_future_ass_threat_zero_for_high_hp_units(t: Object) -> void:
	var core := _make_core()
	t.eq(AIEvaluator.future_ass_threat_penalty("HFW", Vector2i(1, 1), core), 0.0, "HF 高血無懼")
	t.eq(AIEvaluator.future_ass_threat_penalty("TANKW", Vector2i(1, 1), core), 0.0, "TANK 高血無懼")
	t.eq(AIEvaluator.future_ass_threat_penalty("LFW", Vector2i(1, 1), core), 0.0, "LF 高血無懼")


func _test_future_ass_threat_zero_when_diagonal_neighbors_occupied(t: Object) -> void:
	var core := _make_core()
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
		_place(core, "TANKW", "player1", cell.x, cell.y)
	t.eq(AIEvaluator.future_ass_threat_penalty("ADCW", Vector2i(1, 1), core), 0.0, "斜角全滿無威脅")


func _test_adcw_placement_prefers_corner_over_center_under_ass_threat(t: Object) -> void:
	var core := _make_core()
	var corner := AIEvaluator.evaluate_placement("ADCW", Vector2i(0, 0), core, "player2")
	var center := AIEvaluator.evaluate_placement("ADCW", Vector2i(1, 1), core, "player2")
	t.ok(corner > center, "ADC 角落勝中央")


func _test_hf_placement_prefers_center_over_corner_due_to_reach(t: Object) -> void:
	var core := _make_core()
	var corner := AIEvaluator.evaluate_placement("HFW", Vector2i(0, 0), core, "player2")
	var center := AIEvaluator.evaluate_placement("HFW", Vector2i(1, 1), core, "player2")
	t.ok(center > corner, "HF 中央因覆蓋勝出")


func _test_reach_bonus_zero_for_nearest_attackers(t: Object) -> void:
	var core := _make_core()
	t.eq(AIEvaluator.reach_bonus("SPW", Vector2i(0, 0), core), 0.0, "SP reach 0")
	t.eq(AIEvaluator.reach_bonus("APW", Vector2i(1, 1), core), 0.0, "AP reach 0")


func _test_evaluate_placement_avoids_immediate_kill_spot(t: Object) -> void:
	var core := _make_core()
	var enemy := _place(core, "ADCW", "player1", 1, 1)
	enemy.set_numb(false)
	core.number_of_attacks["player1"] = 1
	var unsafe := AIEvaluator.evaluate_placement("ASSW", Vector2i(0, 1), core, "player2")
	var safe := AIEvaluator.evaluate_placement("ASSW", Vector2i(3, 3), core, "player2")
	t.ok(safe > unsafe, "避開即死格")


func _test_hand_threat_penalty_applies_to_ass(t: Object) -> void:
	t.ok(AIEvaluator.hand_threat_penalty("ASSW", _db) < 0, "ASS 手牌保留扣分")
	t.eq(AIEvaluator.hand_threat_penalty("TANKW", _db), 0.0, "TANK 無手牌保留扣分")


func _test_ass_placement_without_kill_or_defense_skipped_after_threshold(t: Object) -> void:
	var core := _make_core()
	# 無友方可護、無敵人在攻擊範圍 — ASS 佈署只是純數值堆疊。
	var score := AIEvaluator.evaluate_placement("ASSW", Vector2i(0, 0), core, "player2")
	t.ok(score < 1.0, "純堆疊 ASS 佈署 < 佈署門檻")


func _test_evaluate_placement_ass_lethal_outscores_safe_corner_placement(t: Object) -> void:
	var core := _make_core()
	var victim := _place(core, "ADCW", "player1", 0, 0)
	victim.set_numb(false)
	var lethal_spot := AIEvaluator.evaluate_placement("ASSW", Vector2i(1, 1), core, "player2")
	var safe_corner := AIEvaluator.evaluate_placement("ASSW", Vector2i(3, 3), core, "player2")
	t.ok(lethal_spot > safe_corner, "斬殺佈署 > 安全角落")
	t.ok(lethal_spot >= 100.0, "斬殺佈署 >=100")
