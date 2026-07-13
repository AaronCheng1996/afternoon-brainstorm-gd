# P10-3 驗收：CPU AI 策略層（翻譯自 Python tests/test_campaign_strategies.py 的策略相關案例）。
# 對應 script/ai/ai_strategy.gd 與 docs/rebuild/03 §6。
# 僅涵蓋 Strategy 基底＋各色/boss 子策略；AIController／boss_config／deck_builder／campaign_save
# 相關案例屬 P10-4/P10-5，不在此檔。_place 對齊 P10-2 test（工廠預設暈眩、佔格）。
extends RefCounted

var _db: Object = null


func _make_core() -> GameCore:
	var core := GameCore.new()
	core.setup(["ADCW"], ["ADCW"], 42, _db)
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

	# 工廠與 faction_overrides
	_test_factory_creates_each_stage(t)
	_test_white_attack_min_score_lowered_via_faction_override(t)
	# Red
	_test_red_apr_attack_bonus_scales_with_target_damage(t)
	_test_red_attack_bonus_rewards_damage_growth(t)
	_test_red_strategy_prefers_hfr_over_tankr(t)
	_test_red_hfr_anger_attack_gets_huge_bonus(t)
	_test_red_placement_bonus(t)
	# Blue
	_test_expected_tokens_from_apb_attack_scales_with_targets(t)
	_test_expected_tokens_from_lfb_multi_target_attack(t)
	_test_adcb_placement_bonus_scales_with_token_engines(t)
	_test_apb_swing_with_armed_adcb_gets_chain_bonus(t)
	_test_numb_adcb_doesnt_arm_token_draw_chain(t)
	_test_blue_apb_attack_outranks_adcb_for_token_economy(t)
	_test_spb_placement_deferred_when_other_units_in_hand(t)
	_test_blue_spb_placement_penalized_when_no_enemies(t)
	_test_blue_spb_attack_outranks_other_blue_attackers(t)
	_test_blue_spb_placement_scales_with_discard_pile(t)
	_test_blue_adcb_placement_bonus_when_token_draw_imminent(t)
	_test_blue_lfb_placement_holds_when_board_sparse(t)
	_test_blue_attack_bonus_peaks_at_two_tokens(t)
	_test_blue_hfb_attack_scales_with_tokens(t)
	# Green
	_test_green_hfg_attack_bonus_scales_with_block_count(t)
	_test_green_lfg_attack_bonus_scales_with_block_count(t)
	_test_green_lf_attack_bonus_when_adjacent_to_lucky_block(t)
	_test_green_lfg_attack_bonus_big_when_adjacent(t)
	_test_green_aptg_placement_rewards_empty_neighbors(t)
	_test_numb_attacker_not_resurrected_by_faction_bonus(t)
	_test_green_best_attack_skips_aptg_even_with_kill_in_range(t)
	# Orange
	_test_orange_asso_anger_attack_outranks_idle_attack(t)
	_test_orange_placement_rewards_open_positions_for_movers(t)
	_test_orange_hfo_attack_bonus_scales_with_ramp_and_multitarget(t)
	# Boss
	_test_boss_placement_prefers_tank_against_high_damage_opponent(t)
	_test_boss_trailing_attack_bonus(t)
	# 基底決策
	_test_base_best_placement_and_attack_smoke(t)

	_db.free()
	_db = null


# ---------- 工廠與 faction_overrides ----------

func _test_factory_creates_each_stage(t: Object) -> void:
	for stage in ["white", "red", "blue", "green", "orange", "boss"]:
		var s := AIStrategy.create(stage, _db)
		t.ok(s != null, "%s 策略非空" % stage)
	# attack_min_score faction override（見 campaign_setting.json）。
	t.eq(AIStrategy.create("red", _db).attack_min_score, 12.0, "red attack_min 12")
	t.eq(AIStrategy.create("blue", _db).attack_min_score, 13.0, "blue attack_min 13")
	t.eq(AIStrategy.create("orange", _db).attack_min_score, 12.0, "orange attack_min 12")
	t.eq(AIStrategy.create("boss", _db).attack_min_score, 13.0, "boss attack_min 13")
	t.eq(AIStrategy.create("white", _db).placement_min_score, 1.0, "placement_min 預設 1")


func _test_white_attack_min_score_lowered_via_faction_override(t: Object) -> void:
	t.ok(AIStrategy.create("white", _db).attack_min_score <= 10.0, "white attack_min <=10")


# ---------- Red ----------

func _test_red_apr_attack_bonus_scales_with_target_damage(t: Object) -> void:
	var s := AIStrategy.RedStrategy.new()
	var core := _make_core()
	var apr := _place(core, "APR", "player2", 1, 1)
	apr.set_numb(false)
	_place(core, "TANKW", "player1", 0, 0)
	var weak_score := s.attack_bonus(apr, core, 10.0)

	var core2 := _make_core()
	var apr2 := _place(core2, "APR", "player2", 1, 1)
	apr2.set_numb(false)
	_place(core2, "ADCW", "player1", 0, 0)
	var strong_score := s.attack_bonus(apr2, core2, 10.0)
	t.ok(strong_score > weak_score, "APR 加成隨目標攻擊力提升")


func _test_red_attack_bonus_rewards_damage_growth(t: Object) -> void:
	var s := AIStrategy.RedStrategy.new()
	var core := _make_core()
	var adc := _place(core, "ADCR", "player2", 0, 0)
	var fresh := s.attack_bonus(adc, core, 10.0)
	adc.damage += 3
	var ramped := s.attack_bonus(adc, core, 10.0)
	t.ok(ramped >= fresh + 15.0, "成長攻擊力獎勵")


func _test_red_strategy_prefers_hfr_over_tankr(t: Object) -> void:
	var s := AIStrategy.RedStrategy.new()
	var core := _make_core()
	var tankr := _place(core, "TANKR", "player2", 0, 0)
	var hfr := _place(core, "HFR", "player2", 1, 0)
	t.ok(s.attack_bonus(hfr, core, 5.0) > s.attack_bonus(tankr, core, 5.0), "HFR 攻擊優先於 TANKR")


func _test_red_hfr_anger_attack_gets_huge_bonus(t: Object) -> void:
	var s := AIStrategy.RedStrategy.new()
	var core := _make_core()
	var hfr := _place(core, "HFR", "player2", 1, 1)
	var no_anger := s.attack_bonus(hfr, core, 10.0)
	hfr.set_anger(true)
	var angered := s.attack_bonus(hfr, core, 10.0)
	t.ok(angered >= no_anger + 20.0, "怒氣 HFR 巨額加成")


func _test_red_placement_bonus(t: Object) -> void:
	var s := AIStrategy.RedStrategy.new()
	var core := _make_core()
	var lfr := s.placement_bonus("LFR", Vector2i(0, 0), core, "player2", 10.0)
	var tankr := s.placement_bonus("TANKR", Vector2i(0, 0), core, "player2", 10.0)
	t.eq(lfr, 15.0, "LFR 佈署 +5")
	t.eq(tankr, 10.0, "TANKR 無佈署加成")


# ---------- Blue ----------

func _test_expected_tokens_from_apb_attack_scales_with_targets(t: Object) -> void:
	var core := _make_core()
	var apb := _place(core, "APB", "player2", 1, 1)
	apb.set_numb(false)
	_place(core, "ADCW", "player1", 1, 2)
	t.eq(AIStrategy.BlueStrategy.expected_tokens_from_attack(apb, core), 2, "APB 產球=目標×2")


func _test_expected_tokens_from_lfb_multi_target_attack(t: Object) -> void:
	var core := _make_core()
	var lfb := _place(core, "LFB", "player2", 1, 1)
	lfb.set_numb(false)
	_place(core, "ADCW", "player1", 1, 0)
	_place(core, "ADCW", "player1", 0, 1)
	_place(core, "ADCW", "player1", 2, 1)
	t.eq(AIStrategy.BlueStrategy.expected_tokens_from_attack(lfb, core), 3, "LFB 產球=目標數")


func _test_adcb_placement_bonus_scales_with_token_engines(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var lone := s.placement_bonus("ADCB", Vector2i(0, 0), core, "player2", 10.0)

	var core2 := _make_core()
	_place(core2, "APB", "player2", 1, 1)
	_place(core2, "LFB", "player2", 2, 2)
	_place(core2, "TANKB", "player2", 3, 3)
	var with_engines := s.placement_bonus("ADCB", Vector2i(0, 0), core2, "player2", 10.0)
	t.ok(with_engines >= lone + 10.0, "ADCB 佈署隨引擎友軍提升")


func _test_apb_swing_with_armed_adcb_gets_chain_bonus(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	core.players_token["player2"] = 1
	var apb := _place(core, "APB", "player2", 1, 1)
	apb.set_numb(false)
	_place(core, "ADCW", "player1", 1, 2)
	var no_adcb := s.attack_bonus(apb, core, 10.0)

	var armed := _place(core, "ADCB", "player2", 0, 0)
	armed.set_numb(false)
	var with_adcb := s.attack_bonus(apb, core, 10.0)
	t.ok(with_adcb >= no_adcb + 10.0, "醒著的 ADCB 提供連鎖加成")


func _test_numb_adcb_doesnt_arm_token_draw_chain(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	core.players_token["player2"] = 1
	var apb := _place(core, "APB", "player2", 1, 1)
	apb.set_numb(false)
	_place(core, "ADCW", "player1", 1, 2)
	var no_adcb := s.attack_bonus(apb, core, 10.0)

	var numb_adcb := _place(core, "ADCB", "player2", 0, 0)
	numb_adcb.set_numb(true)
	var with_numb := s.attack_bonus(apb, core, 10.0)
	t.eq(with_numb, no_adcb, "暈眩 ADCB 不啟動連鎖")


func _test_blue_apb_attack_outranks_adcb_for_token_economy(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var apb := _place(core, "APB", "player2", 1, 1)
	apb.set_numb(false)
	var adcb := _place(core, "ADCB", "player2", 3, 3)
	adcb.set_numb(false)
	_place(core, "ADCW", "player1", 0, 0)
	t.ok(s.attack_bonus(apb, core, 10.0) > s.attack_bonus(adcb, core, 10.0), "APB 為經濟優於 ADCB")


func _test_spb_placement_deferred_when_other_units_in_hand(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	_place(core, "ADCW", "player1", 1, 0)
	core.get_player("player2").hand.assign(["SPB"])
	var solo := s.placement_bonus("SPB", Vector2i(0, 0), core, "player2", 10.0)

	var core2 := _make_core()
	_place(core2, "ADCW", "player1", 1, 0)
	core2.get_player("player2").hand.assign(["SPB", "TANKB", "ADCB", "APB"])
	var crowded := s.placement_bonus("SPB", Vector2i(0, 0), core2, "player2", 10.0)
	t.ok(crowded < solo - 10.0, "手上尚有其他單位時 SPB 佈署延後")


func _test_blue_spb_placement_penalized_when_no_enemies(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var no_enemies := s.placement_bonus("SPB", Vector2i(0, 0), core, "player2", 10.0)
	t.ok(no_enemies <= 0, "無敵人 SPB 佈署 <=0")
	var core2 := _make_core()
	_place(core2, "ADCW", "player1", 1, 0)
	var with_enemies := s.placement_bonus("SPB", Vector2i(0, 0), core2, "player2", 10.0)
	t.ok(with_enemies > no_enemies, "有敵人 SPB 佈署較高")


func _test_blue_spb_attack_outranks_other_blue_attackers(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var spb := _place(core, "SPB", "player2", 0, 0)
	var adcb := _place(core, "ADCB", "player2", 3, 0)
	t.ok(s.attack_bonus(spb, core, 10.0) > s.attack_bonus(adcb, core, 10.0), "SPB 攻擊優於其他藍卡")


func _test_blue_spb_placement_scales_with_discard_pile(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var early := _make_core()
	_place(early, "ADCW", "player1", 1, 0)
	var early_score := s.placement_bonus("SPB", Vector2i(0, 0), early, "player2", 10.0)

	var late := _make_core()
	_place(late, "ADCW", "player1", 1, 0)
	late.get_player("player2").discard_pile.assign(["TANKB", "TANKB", "TANKB", "TANKB", "TANKB"])
	var late_score := s.placement_bonus("SPB", Vector2i(0, 0), late, "player2", 10.0)
	t.ok(late_score > early_score, "SPB 佈署隨棄牌堆規模提升")


func _test_blue_adcb_placement_bonus_when_token_draw_imminent(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	core.players_token["player2"] = 2
	var high := s.placement_bonus("ADCB", Vector2i(0, 0), core, "player2", 10.0)
	core.players_token["player2"] = 0
	var low := s.placement_bonus("ADCB", Vector2i(0, 0), core, "player2", 10.0)
	t.ok(high > low + 10.0, "接近抽牌門檻時 ADCB 佈署提升")


func _test_blue_lfb_placement_holds_when_board_sparse(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var sparse := s.placement_bonus("LFB", Vector2i(0, 0), core, "player2", 10.0)

	var core2 := _make_core()
	_place(core2, "ADCW", "player1", 1, 0)
	_place(core2, "ADCW", "player1", 0, 1)
	var rich := s.placement_bonus("LFB", Vector2i(0, 0), core2, "player2", 10.0)
	t.ok(rich > sparse, "目標豐富時 LFB 佈署較高")


func _test_blue_attack_bonus_peaks_at_two_tokens(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var adc := _place(core, "ADCB", "player2", 0, 0)
	core.players_token["player2"] = 0
	var base0 := s.attack_bonus(adc, core, 10.0)
	core.players_token["player2"] = 2
	var base2 := s.attack_bonus(adc, core, 10.0)
	t.ok(base2 > base0, "2 token 時攻擊加成較高")


func _test_blue_hfb_attack_scales_with_tokens(t: Object) -> void:
	var s := AIStrategy.BlueStrategy.new()
	var core := _make_core()
	var hf := _place(core, "HFB", "player2", 1, 1)
	_place(core, "ADCW", "player1", 1, 2)
	core.players_token["player2"] = 0
	var no_tokens := s.attack_bonus(hf, core, 10.0)
	core.players_token["player2"] = 2
	var with_tokens := s.attack_bonus(hf, core, 10.0)
	t.ok(with_tokens > no_tokens, "HFB 攻擊隨 token 提升")


# ---------- Green ----------

func _test_green_hfg_attack_bonus_scales_with_block_count(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var hfg := _place(core, "HFG", "player2", 1, 1)
	var one_score := s.attack_bonus(hfg, core, 10.0)
	for cell: Vector2i in [Vector2i(2, 1), Vector2i(0, 1), Vector2i(1, 0)]:
		_place(core, "LUCKYBLOCK", "neutral", cell.x, cell.y)
	var three_score := s.attack_bonus(hfg, core, 10.0)
	t.ok(three_score >= one_score + 60.0, "HFG 攻擊隨方塊數提升")


func _test_green_lfg_attack_bonus_scales_with_block_count(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var lfg := _place(core, "LFG", "player2", 1, 1)
	var one_score := s.attack_bonus(lfg, core, 10.0)
	for cell: Vector2i in [Vector2i(2, 1), Vector2i(0, 1), Vector2i(1, 0)]:
		_place(core, "LUCKYBLOCK", "neutral", cell.x, cell.y)
	var three_score := s.attack_bonus(lfg, core, 10.0)
	t.ok(three_score >= one_score + 90.0, "LFG 攻擊隨方塊數提升")


func _test_green_lf_attack_bonus_when_adjacent_to_lucky_block(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var lf := _place(core, "LFG", "player2", 1, 1)
	var no_block := s.attack_bonus(lf, core, 10.0)
	_place(core, "LUCKYBLOCK", "neutral", 2, 1)
	var with_block := s.attack_bonus(lf, core, 10.0)
	t.ok(with_block > no_block, "LFG 相鄰方塊加成")


func _test_green_lfg_attack_bonus_big_when_adjacent(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var lf := _place(core, "LFG", "player2", 1, 1)
	var base := s.attack_bonus(lf, core, 10.0)
	_place(core, "LUCKYBLOCK", "neutral", 2, 1)
	var boosted := s.attack_bonus(lf, core, 10.0)
	t.ok(boosted >= base + 40.0, "LFG 相鄰方塊 >=+40")


func _test_green_aptg_placement_rewards_empty_neighbors(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var center := s.placement_bonus("APTG", Vector2i(1, 1), core, "player2", 10.0)
	_place(core, "TANKG", "player2", 0, 1)
	_place(core, "TANKG", "player2", 1, 0)
	var blocked := s.placement_bonus("APTG", Vector2i(1, 1), core, "player2", 10.0)
	t.ok(center > blocked, "APTG 佈署偏好空鄰格")


func _test_numb_attacker_not_resurrected_by_faction_bonus(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var hf := _place(core, "HFG", "player2", 1, 1)
	hf.set_numb(true)
	_place(core, "LUCKYBLOCK", "neutral", 2, 1)
	core.number_of_attacks["player2"] = 1
	t.eq(s.best_attack(core, "player2"), null, "暈眩攻擊者不因加成復活")


func _test_green_best_attack_skips_aptg_even_with_kill_in_range(t: Object) -> void:
	var s := AIStrategy.GreenStrategy.new()
	var core := _make_core()
	var apt := _place(core, "APTG", "player2", 1, 1)
	apt.set_numb(false)
	var target := _place(core, "ADCW", "player1", 1, 2)
	target.set_numb(false)
	target.health = 1
	core.number_of_attacks["player2"] = 1
	t.eq(s.best_attack(core, "player2"), null, "APTG 不會被選為攻擊者")


# ---------- Orange ----------

func _test_orange_asso_anger_attack_outranks_idle_attack(t: Object) -> void:
	var s := AIStrategy.OrangeStrategy.new()
	var core := _make_core()
	var asso := _place(core, "ASSO", "player2", 1, 1)
	var fresh := s.attack_bonus(asso, core, 10.0)
	asso.set_anger(true)
	var angered := s.attack_bonus(asso, core, 10.0)
	t.ok(angered >= fresh + 18.0, "怒氣 ASSO 攻擊優於待機")


func _test_orange_placement_rewards_open_positions_for_movers(t: Object) -> void:
	var s := AIStrategy.OrangeStrategy.new()
	var core := _make_core()
	var center := s.placement_bonus("ADCO", Vector2i(1, 1), core, "player2", 10.0)
	var corner := s.placement_bonus("ADCO", Vector2i(0, 0), core, "player2", 10.0)
	t.ok(center > corner, "機動系偏好開闊中央")


func _test_orange_hfo_attack_bonus_scales_with_ramp_and_multitarget(t: Object) -> void:
	var s := AIStrategy.OrangeStrategy.new()
	var core := _make_core()
	var hfo := _place(core, "HFO", "player2", 1, 1)
	hfo.set_numb(false)
	var baseline := s.attack_bonus(hfo, core, 10.0)

	var a := _place(core, "ADCW", "player1", 0, 0)
	var b := _place(core, "ADCW", "player1", 2, 0)
	var c := _place(core, "ADCW", "player1", 0, 2)
	a.set_numb(false)
	b.set_numb(false)
	c.set_numb(false)
	var multi := s.attack_bonus(hfo, core, 10.0)
	t.ok(multi > baseline, "多目標提升 HFO 攻擊加成")

	hfo.extra_damage = 2
	var ramped := s.attack_bonus(hfo, core, 10.0)
	t.ok(ramped > multi + 10.0, "extra_damage 進一步提升")


# ---------- Boss ----------

func _test_boss_placement_prefers_tank_against_high_damage_opponent(t: Object) -> void:
	var s := AIStrategy.BossStrategy.new()
	var core := _make_core()
	var adc1 := _place(core, "ADCW", "player1", 0, 0)
	adc1.damage = 5
	var adc2 := _place(core, "ADCW", "player1", 0, 1)
	adc2.damage = 5
	var with_tank := s.placement_bonus("TANKB", Vector2i(2, 2), core, "player2", 10.0)
	var with_adc := s.placement_bonus("ADCR", Vector2i(2, 2), core, "player2", 10.0)
	t.ok(with_tank > with_adc, "面對高攻對手偏好 TANK")


func _test_boss_trailing_attack_bonus(t: Object) -> void:
	var s := AIStrategy.BossStrategy.new()
	var core := _make_core()
	var atk := _place(core, "ADCW", "player2", 1, 1)
	core.score = 0
	var even := s.attack_bonus(atk, core, 10.0)
	core.score = -10
	var trailing := s.attack_bonus(atk, core, 10.0)
	t.ok(trailing > even, "落後時全體攻擊加成")


# ---------- 基底決策煙霧 ----------

func _test_base_best_placement_and_attack_smoke(t: Object) -> void:
	var s := AIStrategy.WhiteStrategy.new()
	var core := _make_core()
	core.get_player("player2").hand.assign(["ADCW", "TANKW"])
	var placement := s.best_placement(core, "player2")
	t.ok(placement != null, "白色基底能選出佈署")
	t.ok(placement.score > 0, "佈署分數 > 0")

	var attacker := _place(core, "ADCW", "player2", 1, 1)
	attacker.set_numb(false)
	var victim := _place(core, "ASSW", "player1", 1, 2)
	victim.set_numb(false)
	core.number_of_attacks["player2"] = 1
	var attack := s.best_attack(core, "player2")
	t.ok(attack != null, "白色基底能選出攻擊")
	t.eq(Vector2i(attack.x, attack.y), Vector2i(1, 1), "攻擊者座標正確")
