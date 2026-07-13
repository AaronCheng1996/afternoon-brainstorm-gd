# P10-1 驗收：CPU AI 幾何查詢層（翻譯自 Python tests/test_ai_query.py）。
# 對應 script/ai/ai_query.gd 與 docs/rebuild/03 §2。
extends RefCounted

# 全檔共用一個 BalanceDB（extends Node），於 run() 結尾釋放，避免累積 orphan（見 09 §11）。
var _db: Object = null


func _make_core() -> GameCore:
	var core := GameCore.new()
	core.setup(["ADCW"], ["ADCW"], 42, _db)
	return core


# 直接放一顆棋子在場上（非暈眩、佔格）。owner=neutral 進 neutral_pieces。
func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	p.set_numb(false)
	p.extra_damage = 0
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func _has(arr: Array, piece: PieceState) -> bool:
	return arr.has(piece)


func run(t: Object) -> void:
	_db = load("res://script/data/balance_db.gd").new()
	_test_empty_positions(t)
	_test_position_safety(t)
	_test_corner_and_edge(t)
	_test_enemy_and_friendly(t)
	_test_targets_small_cross(t)
	_test_targets_large_cross(t)
	_test_targets_empty_when_out_of_range(t)
	_test_nearest_enemy_distance(t)
	_test_targets_no_rng(t)
	_test_cells_threatening_corner_adc(t)
	_test_cells_threatening_high_hp(t)
	_test_cells_threatening_occupied(t)
	_test_incoming_zero_no_attacks(t)
	_test_incoming_counts_in_range(t)
	_test_incoming_caps_by_attack_count(t)
	_test_incoming_ignores_numb(t)
	_test_coverage_hf_corner_vs_center(t)
	_test_coverage_adc_large_cross(t)
	_test_coverage_zero_for_nearest(t)
	_test_playable_and_move_helpers(t)
	_db.free()
	_db = null


func _test_empty_positions(t: Object) -> void:
	var core := _make_core()
	_place(core, "TANKW", "player1", 0, 0)
	_place(core, "ADCW", "player2", 3, 3)
	var empties := AIQuery.empty_positions(core)
	t.ok(not empties.has(Vector2i(0, 0)), "empty_positions 排除 (0,0)")
	t.ok(not empties.has(Vector2i(3, 3)), "empty_positions 排除 (3,3)")
	t.ok(empties.has(Vector2i(1, 1)), "empty_positions 含 (1,1)")
	t.eq(empties.size(), 4 * 4 - 2, "empty_positions 數量")


func _test_position_safety(t: Object) -> void:
	t.eq(AIQuery.position_safety(0, 0), 3.0, "safety 角落")
	t.eq(AIQuery.position_safety(3, 3), 3.0, "safety 角落")
	t.eq(AIQuery.position_safety(1, 0), 2.0, "safety 邊")
	t.eq(AIQuery.position_safety(0, 2), 2.0, "safety 邊")
	t.eq(AIQuery.position_safety(1, 1), 1.0, "safety 中央")
	t.eq(AIQuery.position_safety(2, 2), 1.0, "safety 中央")


func _test_corner_and_edge(t: Object) -> void:
	t.ok(AIQuery.is_corner(0, 0), "is_corner (0,0)")
	t.ok(AIQuery.is_corner(3, 3), "is_corner (3,3)")
	t.ok(not AIQuery.is_corner(0, 1), "非 corner (0,1)")
	t.ok(AIQuery.is_edge(0, 1), "is_edge (0,1)")
	t.ok(AIQuery.is_edge(2, 3), "is_edge (2,3)")
	t.ok(not AIQuery.is_edge(0, 0), "corner 非 edge")
	t.ok(not AIQuery.is_edge(1, 1), "中央非 edge")


func _test_enemy_and_friendly(t: Object) -> void:
	var core := _make_core()
	var a := _place(core, "ADCW", "player1", 0, 0)
	var b := _place(core, "TANKW", "player2", 3, 3)
	t.eq(AIQuery.enemy_cards(core, "player1"), [b], "enemy_cards p1")
	t.eq(AIQuery.enemy_cards(core, "player2"), [a], "enemy_cards p2")
	t.eq(AIQuery.friendly_cards(core, "player1"), [a], "friendly_cards p1")
	t.eq(AIQuery.friendly_cards(core, "player2"), [b], "friendly_cards p2")


func _test_targets_small_cross(t: Object) -> void:
	var core := _make_core()
	var tank := _place(core, "TANKW", "player1", 1, 1)   # small_cross
	var above := _place(core, "ADCW", "player2", 1, 0)
	var below := _place(core, "ADCW", "player2", 1, 2)
	var diagonal := _place(core, "ADCW", "player2", 2, 2)
	var hits := AIQuery.attack_targets_at(core, tank)
	t.ok(_has(hits, above), "small_cross 命中上方")
	t.ok(_has(hits, below), "small_cross 命中下方")
	t.ok(not _has(hits, diagonal), "small_cross 不命中斜角")


func _test_targets_large_cross(t: Object) -> void:
	var core := _make_core()
	var adc := _place(core, "ADCW", "player1", 1, 1)   # large_cross
	var far_row := _place(core, "TANKW", "player2", 3, 1)
	var far_col := _place(core, "TANKW", "player2", 1, 3)
	var off_axis := _place(core, "TANKW", "player2", 2, 2)
	var hits := AIQuery.attack_targets_at(core, adc)
	t.ok(_has(hits, far_row), "large_cross 命中同列")
	t.ok(_has(hits, far_col), "large_cross 命中同行")
	t.ok(not _has(hits, off_axis), "large_cross 不命中軸外")


func _test_targets_empty_when_out_of_range(t: Object) -> void:
	var core := _make_core()
	var tank := _place(core, "TANKW", "player1", 0, 0)
	_place(core, "ADCW", "player2", 3, 3)
	t.eq(AIQuery.attack_targets_at(core, tank), [], "範圍外無目標")


func _test_nearest_enemy_distance(t: Object) -> void:
	var core := _make_core()
	_place(core, "ADCW", "player2", 0, 0)
	_place(core, "ADCW", "player2", 3, 3)
	t.eq(AIQuery.nearest_enemy_distance(core, "player1", 1, 0), 1, "最近敵距 =1")
	t.eq(AIQuery.nearest_enemy_distance(core, "player1", 2, 2), 2, "最近敵距 =2")


# SPW（farthest）查詢不得推進 rng（引擎的 detection 仍需要它）。
func _test_targets_no_rng(t: Object) -> void:
	var core := _make_core()
	var sp := _place(core, "SPW", "player1", 0, 0)
	_place(core, "ADCW", "player2", 3, 3)
	_place(core, "ADCW", "player2", 2, 3)
	var state_before: int = core.rng._rng.state
	AIQuery.attack_targets_at(core, sp)
	t.eq(core.rng._rng.state, state_before, "查詢不消耗 rng")


func _test_cells_threatening_corner_adc(t: Object) -> void:
	var core := _make_core()
	var adc := _place(core, "ADCW", "player2", 3, 0)   # health 5
	t.eq(AIQuery.cells_threatening_card(core, adc), [Vector2i(2, 1)], "脆皮角落唯一威脅格")


func _test_cells_threatening_high_hp(t: Object) -> void:
	var core := _make_core()
	var tank := _place(core, "TANKW", "player2", 3, 0)   # 15 HP，ASS 一擊不死
	t.eq(AIQuery.cells_threatening_card(core, tank), [], "高血無威脅格")


func _test_cells_threatening_occupied(t: Object) -> void:
	var core := _make_core()
	var adc := _place(core, "ADCW", "player2", 3, 0)
	_place(core, "ASSW", "player2", 2, 1)   # 唯一威脅格已被佔
	t.eq(AIQuery.cells_threatening_card(core, adc), [], "威脅格被佔即無")


func _test_incoming_zero_no_attacks(t: Object) -> void:
	var core := _make_core()
	var enemy := _place(core, "ADCW", "player1", 1, 1)
	enemy.set_numb(false)
	core.number_of_attacks["player1"] = 0
	t.eq(AIQuery.incoming_damage_at_position(core, "player2", 0, 1), 0, "對手無攻擊次數 → 0")


func _test_incoming_counts_in_range(t: Object) -> void:
	var core := _make_core()
	var enemy := _place(core, "ADCW", "player1", 1, 1)
	enemy.set_numb(false)
	core.number_of_attacks["player1"] = 2
	t.eq(AIQuery.incoming_damage_at_position(core, "player2", 0, 1), enemy.damage, "large_cross 命中該格")


func _test_incoming_caps_by_attack_count(t: Object) -> void:
	var core := _make_core()
	for x in 3:
		var e := _place(core, "ADCW", "player1", x, 0)
		e.set_numb(false)
	core.number_of_attacks["player1"] = 1
	t.eq(AIQuery.incoming_damage_at_position(core, "player2", 0, 1), 4, "受攻擊次數上限箝制")


func _test_incoming_ignores_numb(t: Object) -> void:
	var core := _make_core()
	var e := _place(core, "ADCW", "player1", 1, 1)
	e.set_numb(true)
	core.number_of_attacks["player1"] = 2
	t.eq(AIQuery.incoming_damage_at_position(core, "player2", 0, 1), 0, "麻痺敵人不計傷")


func _test_coverage_hf_corner_vs_center(t: Object) -> void:
	var core := _make_core()
	var corner := AIQuery.attack_coverage_cells(core, 0, 0, "small_cross small_x")
	var center := AIQuery.attack_coverage_cells(core, 1, 1, "small_cross small_x")
	t.eq(corner, 3, "HF 角落覆蓋 3")
	t.eq(center, 8, "HF 中央覆蓋 8")


func _test_coverage_adc_large_cross(t: Object) -> void:
	var core := _make_core()
	t.eq(AIQuery.attack_coverage_cells(core, 0, 0, "large_cross"), 6, "large_cross 角落 6")
	t.eq(AIQuery.attack_coverage_cells(core, 1, 1, "large_cross"), 6, "large_cross 中央 6")


func _test_coverage_zero_for_nearest(t: Object) -> void:
	var core := _make_core()
	t.eq(AIQuery.attack_coverage_cells(core, 1, 1, "nearest"), 0, "nearest 覆蓋 0")
	t.eq(AIQuery.attack_coverage_cells(core, 1, 1, "farthest"), 0, "farthest 覆蓋 0")


func _test_playable_and_move_helpers(t: Object) -> void:
	t.ok(AIQuery.is_playable_unit_card("ADCW"), "單位牌可佈署")
	t.ok(not AIQuery.is_playable_unit_card("HEAL"), "HEAL 非佈署")
	t.ok(not AIQuery.is_playable_unit_card("MOVEO"), "MOVEO 非佈署")
	t.ok(not AIQuery.is_playable_unit_card("CUBES"), "CUBES 非佈署")

	var core := _make_core()
	var mover := _place(core, "ADCW", "player1", 0, 0)
	# 8 鄰中僅 (1,0)/(0,1)/(1,1) 在界內
	var dests := AIQuery.move_destinations_for(core, mover)
	t.eq(dests.size(), 3, "角落移動目的地 3 格")
	t.ok(dests.has(Vector2i(1, 1)), "含斜角空格")
	mover.set_moving(true)
	t.eq(AIQuery.units_with_pending_move(core, "player1").size(), 1, "移動中棋子計數")
