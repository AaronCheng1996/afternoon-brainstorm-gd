# P2-4 選秀 BP：核心邏輯 + 場景 headless 冒煙（見 docs/rebuild/06 P2-4、01 §9）。
# 邏輯翻譯自 core/draft_dispatcher.py（Python 無對應測試，故自寫）；
# 「觀感」由人工於編輯器跑 draft.tscn 驗收（docs/rebuild/驗收_BP.md）。
extends RefCounted

const DraftSceneScript := preload("res://scenes_v2/draft/draft.gd")


func run(t: Object) -> void:
	_test_phase_flow(t)
	_test_limits(t)
	_test_remove(t)
	_test_toggles(t)
	_test_scene(t)


func _add(disp: DraftDispatcherV2, st: DraftStateV2, who: String, card: String) -> DraftResultV2:
	return disp.dispatch(DraftActionV2.new(who, "add_card", card), st)


func _adv(disp: DraftDispatcherV2, st: DraftStateV2, who: String) -> DraftResultV2:
	return disp.dispatch(DraftActionV2.new(who, "advance_phase"), st)


func _fill(disp: DraftDispatcherV2, st: DraftStateV2, who: String, units: Array) -> void:
	for u: String in units:
		_add(disp, st, who, u)


# ---------------- 1. 三階段流程 ----------------
func _test_phase_flow(t: Object) -> void:
	var st := DraftStateV2.new()
	var disp := DraftDispatcherV2.new()
	t.eq(st.phase, "p1_first6", "flow：初始階段 p1_first6")
	t.eq(st.current_editor(), "player1", "flow：p1_first6 由 player1 編輯")

	# 非當前選手行動被拒。
	var r0 := _add(disp, st, "player2", "ADCW")
	t.ok(not r0.success and r0.message == "Not your turn", "flow：非當前選手 add 被拒")
	t.eq(st.player2_deck.size(), 0, "flow：被拒後 p2 牌組不變")

	# p1 未滿 6 不能進下一階段。
	_fill(disp, st, "player1", ["ADCW", "ADCW", "TANKW"])
	var rbad := _adv(disp, st, "player1")
	t.ok(not rbad.success and rbad.message == "Phase not ready", "flow：<6 張不能進下一階段")

	# p1 補到 6 → 進 p2_pick12。
	_fill(disp, st, "player1", ["TANKW", "HFW", "HFW"])
	t.eq(st.player1_deck.size(), 6, "flow：p1 選滿 6")
	var r1 := _adv(disp, st, "player1")
	t.ok(r1.success and r1.phase_advanced and not r1.ready_to_start, "flow：p1 first6 → 進階")
	t.eq(st.phase, "p2_pick12", "flow：進入 p2_pick12")
	t.eq(st.current_editor(), "player2", "flow：改由 player2 編輯")

	# p2 選滿 12 → 進 p1_last6。
	_fill(disp, st, "player2", ["ADCW", "ADCW", "TANKW", "TANKW", "HFW", "HFW",
		"LFW", "LFW", "ASSW", "ASSW", "APW", "APW"])
	t.eq(st.player2_deck.size(), 12, "flow：p2 選滿 12")
	var r2 := _adv(disp, st, "player2")
	t.eq(st.phase, "p1_last6", "flow：進入 p1_last6")
	t.eq(st.current_editor(), "player1", "flow：回到 player1 補牌")

	# p1 補滿 12 → done，ready_to_start。
	_fill(disp, st, "player1", ["LFW", "LFW", "ASSW", "ASSW", "APW", "APW"])
	t.eq(st.player1_deck.size(), 12, "flow：p1 補滿 12")
	var r3 := _adv(disp, st, "player1")
	t.eq(st.phase, "done", "flow：進入 done")
	t.ok(r3.ready_to_start, "flow：done → ready_to_start")


# ---------------- 2. 限制（同名上限 / 牌組上限）----------------
func _test_limits(t: Object) -> void:
	var st := DraftStateV2.new()
	var disp := DraftDispatcherV2.new()

	# 單位同名 ≤2。
	t.ok(_add(disp, st, "player1", "ADCW").success, "limit：ADCW 第 1 張")
	t.ok(_add(disp, st, "player1", "ADCW").success, "limit：ADCW 第 2 張")
	var r3 := _add(disp, st, "player1", "ADCW")
	t.ok(not r3.success and r3.message == "Over limit", "limit：ADCW 第 3 張超限")
	t.eq(st.player1_deck.count("ADCW"), 2, "limit：ADCW 僅 2 張")

	# 魔法同名 ≤3。
	for _i in 3:
		t.ok(_add(disp, st, "player1", "HEAL").success, "limit：HEAL 前 3 張")
	var rh := _add(disp, st, "player1", "HEAL")
	t.ok(not rh.success and rh.message == "Over limit", "limit：HEAL 第 4 張超限")

	# 牌組 12 張上限（目前 5 張，補到 12 再 +1）。
	_fill(disp, st, "player1", ["TANKW", "TANKW", "HFW", "HFW", "LFW", "LFW", "ASSW"])
	t.eq(st.player1_deck.size(), 12, "limit：湊滿 12 張")
	var rf := _add(disp, st, "player1", "APW")
	t.ok(not rf.success and rf.message == "Deck is full", "limit：滿 12 張再加被拒")

	# 空名 / "None" 被拒（不加）。
	t.ok(not _add(disp, st, "player1", "").success, "limit：空名被拒")
	t.ok(not _add(disp, st, "player1", "None").success, "limit：None 被拒")


# ---------------- 3. 移除（同名最後一張 / 最後一張）----------------
func _test_remove(t: Object) -> void:
	var st := DraftStateV2.new()
	var disp := DraftDispatcherV2.new()
	_fill(disp, st, "player1", ["ADCW", "TANKW", "ADCW"])
	# remove_card 移除「最後一張同名」。
	disp.dispatch(DraftActionV2.new("player1", "remove_card", "ADCW"), st)
	t.eq(st.player1_deck.count("ADCW"), 1, "remove：移除一張 ADCW 後剩 1")
	t.eq(st.player1_deck, ["ADCW", "TANKW"] as Array[String], "remove：移除的是最後一張同名")
	# remove_last_card 移除末端。
	disp.dispatch(DraftActionV2.new("player1", "remove_last_card"), st)
	t.eq(st.player1_deck, ["ADCW"] as Array[String], "remove：remove_last_card 移除末端")


# ---------------- 4. 切換（計時 / 存檔）----------------
func _test_toggles(t: Object) -> void:
	var st := DraftStateV2.new()
	var disp := DraftDispatcherV2.new()
	t.eq(st.timer_mode, "timer", "toggle：預設正計時")
	disp.dispatch(DraftActionV2.new("player1", "toggle_timer"), st)
	t.eq(st.timer_mode, "countdown", "toggle：切為倒數")
	disp.dispatch(DraftActionV2.new("player1", "toggle_timer"), st)
	t.eq(st.timer_mode, "timer", "toggle：再切回正計時")
	t.eq(st.file_auto_delete, false, "toggle：存檔預設保留")
	disp.dispatch(DraftActionV2.new("player1", "toggle_file_save"), st)
	t.eq(st.file_auto_delete, true, "toggle：切為自動刪除")


# ---------------- 5. 場景 headless 冒煙（經場景行動路徑）----------------
func _test_scene(t: Object) -> void:
	var db: Object = load("res://script_v2/data/balance_db.gd").new()
	var b: Node = DraftSceneScript.new()
	b.boot(42, db)

	t.ok(b._ui_built, "scene：UI 已建構")
	# 首次刷新後展示館為白色頁 8 職業。
	t.eq(b._exhibit_box.get_child_count(), 8, "scene：白色頁 8 個職業卡")
	t.eq(b._magic_box.get_child_count(), 3, "scene：魔法列 3 張")

	# p1 經展示館加牌（超限會設訊息）。
	b._on_exhibit_pressed("ADCW")
	b._on_exhibit_pressed("ADCW")
	b._on_exhibit_pressed("ADCW")   # 第 3 張超限
	t.eq(b._state.player1_deck.count("ADCW"), 2, "scene：ADCW 上限 2")
	t.ok(not b._msg_label.text.is_empty(), "scene：超限顯示訊息")

	# 點自己牌組的卡可移除。
	b._on_deck_card_pressed("player1", "ADCW")
	t.eq(b._state.player1_deck.count("ADCW"), 1, "scene：移除一張 ADCW")

	# 走完整流程到 done（用場景行動路徑）。
	b._on_exhibit_pressed("ADCW")   # 回到 2 張
	for u in ["TANKW", "TANKW", "HFW", "HFW"]:
		b._on_exhibit_pressed(u)    # p1 湊到 6
	b._on_advance()
	t.eq(b._state.phase, "p2_pick12", "scene：進入 p2 階段")
	for u in ["ADCW", "ADCW", "TANKW", "TANKW", "HFW", "HFW", "LFW", "LFW", "ASSW", "ASSW", "APW", "APW"]:
		b._on_exhibit_pressed(u)
	b._on_advance()
	t.eq(b._state.phase, "p1_last6", "scene：進入 p1 補牌階段")
	for u in ["LFW", "LFW", "ASSW", "ASSW", "APW", "APW"]:
		b._on_exhibit_pressed(u)
	b._on_advance()                 # → done → _start_battle（headless get_tree()==null，安全略過）
	t.eq(b._state.phase, "done", "scene：完成 BP")
	t.ok(b._ready_to_start, "scene：標記 ready_to_start")
	t.eq(b._state.player1_deck.size(), 12, "scene：p1 牌組 12 張")
	t.eq(b._state.player2_deck.size(), 12, "scene：p2 牌組 12 張")

	# 色頁切換（Purple 只 4 職業）。
	b._select_color(9)
	t.eq(b._selected_color, 9, "scene：切到紫色頁")

	b.free()
	db.free()
