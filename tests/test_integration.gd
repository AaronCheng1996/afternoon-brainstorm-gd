# P1-14 核心整合回歸（見 docs/rebuild/06 P1-14）。
# 三個整局腳本測試 + 「game_core 無 Node 依賴」靜態檢查：
#   1. 白鏡像對局照腳本走多步、斷言中間狀態（出牌/攻擊/擊殺/結算計分）。
#   2. 藍 vs 綠：token/luck 資源交互（經真實傷害管線）。
#   3. 固定 seed 半隨機對局打到分出勝負（煙霧測試：不崩潰、統計非空）。
extends RefCounted


func _make_core(p1_deck: Array, p2_deck: Array, seed_v: int) -> GameCore:
	var db: Object = load("res://script_v2/data/balance_db.gd").new()
	var core := GameCore.new()
	core.setup(p1_deck, p2_deck, seed_v, db)
	return core


func _deck(card_id: String, n: int) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


func _play(core: GameCore, owner: String, x: int, y: int, idx: int = 0) -> void:
	var a := GameAction.new("play_card", owner)
	a.board_x = x
	a.board_y = y
	a.hand_index = idx
	core.dispatch(a)


func _attack(core: GameCore, owner: String, x: int, y: int) -> void:
	var a := GameAction.new("attack", owner)
	a.board_x = x
	a.board_y = y
	core.dispatch(a)


func _place(core: GameCore, card_id: String, owner: String, x: int, y: int) -> PieceState:
	var p := PieceState.make(card_id, owner, x, y, core.balance)
	p.set_numb(false)
	if owner == "neutral":
		core.neutral_pieces.append(p)
	else:
		core.get_player(owner).on_board.append(p)
	core.board.set_occupied(Vector2i(x, y), true)
	return p


func _free_cells(core: GameCore) -> Array:
	var out: Array = []
	for x in 4:
		for y in 4:
			if core.board.is_free(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func run(t: Object) -> void:
	var cores: Array = []
	_test_white_mirror(t, cores)
	_test_blue_vs_green(t, cores)
	_test_random_smoke(t, cores)
	_test_no_node_dependency(t)
	for c in cores:
		if c.balance != null:
			c.balance.free()


# ---------------- 1. 白鏡像對局腳本 ----------------
func _test_white_mirror(t: Object, cores: Array) -> void:
	var core := _make_core(_deck("ADCW", 12), _deck("ADCW", 12), 100); cores.append(core)

	# turn0 p1：出兩張 ADCW（皆入場暈眩）。
	_play(core, "player1", 1, 0)
	t.eq(core.player1.on_board.size(), 1, "白鏡像：p1 出牌後場上 1 子")
	t.eq(core.player1.hand.size(), 2, "白鏡像：p1 出牌後手牌 2")
	_play(core, "player1", 1, 1)
	t.eq(core.player1.on_board.size(), 2, "白鏡像：p1 出第二張後場上 2 子")

	# p1 結束回合：兩子暈眩 → 0 分；換 p2。
	core.end_turn("player1")
	t.eq(core.score, 0, "白鏡像：p1 首回合暈眩子結算 0 分")
	t.eq(core.turn_number, 1, "白鏡像：turn=1")
	t.eq(core.current_player(), "player2", "白鏡像：換 p2")
	t.eq(core.number_of_attacks["player2"], 1, "白鏡像：p2 turn_start +1 攻擊")

	# p2 出一子（同欄 x=1，供之後被 p1 攻擊）。
	_play(core, "player2", 1, 3)
	t.eq(core.player2.on_board.size(), 1, "白鏡像：p2 出牌後場上 1 子")

	# p2 結束回合 → 換 p1（turn2），p1 兩子解暈、攻擊次數累積為 2（含首回合未用的 1）。
	core.end_turn("player2")
	t.eq(core.turn_number, 2, "白鏡像：turn=2")
	t.eq(core.number_of_attacks["player1"], 2, "白鏡像：p1 攻擊次數累積 2")
	t.ok(not core.player1.on_board[0].is_numb(), "白鏡像：p1 子解暈")

	var p2_piece: PieceState = core.player2.on_board[0]
	var p2_hp: int = p2_piece.health

	# p1 第一次攻擊：large_cross 命中同欄 p2 子（5→1）。
	_attack(core, "player1", 1, 1)
	t.eq(p2_piece.health, p2_hp - 4, "白鏡像：ADCW 攻擊造成 4 傷（5→1）")
	t.eq(core.number_of_attacks["player1"], 1, "白鏡像：消耗 1 次攻擊")

	# p1 第二次攻擊：擊殺 p2 子。
	_attack(core, "player1", 1, 0)
	core.logic_step()   # 回收死亡棋子
	t.eq(core.number_of_attacks["player1"], 0, "白鏡像：攻擊次數用盡")
	t.eq(core.player2.on_board.size(), 0, "白鏡像：p2 子被擊殺並回收")
	t.ok(core.stats.get_stat(Statistics.StatType.KILLED, "player1_ADCW") > 0, "白鏡像：KILLED 統計記錄")

	# p1 結束回合：兩子非暈眩 → 各 +1 → score -2。
	core.end_turn("player1")
	t.eq(core.score, -2, "白鏡像：p1 兩非暈子結算 → score -2")

	# 再一輪：p2 補子、p1 再攻擊一次造成傷害（此回合僅 1 次攻擊）。
	_play(core, "player2", 1, 3)
	core.end_turn("player2")
	t.eq(core.turn_number, 4, "白鏡像：turn=4")
	t.eq(core.number_of_attacks["player1"], 1, "白鏡像：p1 turn4 攻擊次數 1")
	var p2b: PieceState = core.player2.on_board[0]
	var p2b_hp: int = p2b.health
	_attack(core, "player1", 1, 1)
	t.eq(p2b.health, p2b_hp - 4, "白鏡像：第二輪攻擊再造成 4 傷")
	core.end_turn("player1")
	t.eq(core.score, -4, "白鏡像：再結算 → score -4")
	t.ok(not core.is_over(), "白鏡像：尚未分出勝負")


# ---------------- 2. 藍 vs 綠：token/luck 交互 ----------------
func _test_blue_vs_green(t: Object, cores: Array) -> void:
	var core := _make_core(_deck("APB", 12), _deck("APG", 12), 200); cores.append(core)
	var apb := _place(core, "APB", "player1", 0, 0)
	var apg := _place(core, "APG", "player2", 1, 0)

	# 藍 APB 攻擊綠 APG：造成傷害 → 獲得 token。
	var token_before: int = core.players_token["player1"]
	CombatV2.attack(core, apb)
	t.ok(core.players_token["player1"] > token_before, "藍綠：APB 攻擊後 player1 獲得 token")
	t.ok(apg.is_numb(), "藍綠：APB 攻擊附帶麻痺")

	# 綠 APG 反擊藍 APB：目標壞運 + 自身好運 → players_luck 變動。
	apg.set_numb(false)
	CombatV2.attack(core, apg)
	t.ok(core.players_luck["player1"] != 50 or core.players_luck["player2"] != 50,
		"藍綠：APG 觸發好/壞運 → players_luck 由初始 50 變動")

	# 統計非空（傷害有被記錄）。
	t.ok(not core.stats.get_all(Statistics.StatType.DAMAGE_DEALT).is_empty(), "藍綠：DAMAGE_DEALT 統計非空")


# ---------------- 3. 固定 seed 半隨機對局（煙霧測試）----------------
# p1 積極（出牌 + 攻擊），p2 消極（僅結束回合）；p1 每回合自方非暈子結算使 score 往負走，
# 必於門檻前分出勝負（player1）。過程驅動多色卡的佈署/更新鉤子，驗證整局不崩潰、統計非空。
func _test_random_smoke(t: Object, cores: Array) -> void:
	var p1_deck: Array = ["ADCW", "TANKW", "SPW", "APW", "HFW", "LFW",
		"ASSW", "APTW", "ADCR", "APB", "ADCG", "ADCO"]
	var core := _make_core(p1_deck, _deck("ADCW", 12), 424242); cores.append(core)

	var guard: int = 0
	while not core.is_over() and guard < 300:
		guard += 1
		var cur: String = core.current_player()
		if cur == "player1":
			var free: Array = _free_cells(core)
			if not core.player1.hand.is_empty() and not free.is_empty():
				var cell: Vector2i = core.rng.choice(free)
				_play(core, "player1", cell.x, cell.y, 0)
			# 對每個自方棋子嘗試攻擊（無敵方目標則自然無效、不消耗）。
			for piece: PieceState in core.player1.on_board.duplicate():
				if core.number_of_attacks["player1"] <= 0:
					break
				_attack(core, "player1", piece.board_x, piece.board_y)
			core.logic_step()
			core.end_turn("player1")
		else:
			core.end_turn("player2")
		core.logic_step()

	t.ok(core.is_over(), "煙霧：對局在門檻內分出勝負（guard=" + str(guard) + "）")
	t.eq(core.winner(), 0, "煙霧：積極的 player1 獲勝（score<0）")
	t.ok(not core.stats.score_history.is_empty(), "煙霧：score_history 非空")
	t.ok(not core.stats.get_all(Statistics.StatType.SCORED).is_empty(), "煙霧：SCORED 統計非空")


# ---------------- 4. game_core 無 Node 依賴（靜態 grep 檢查）----------------
# 掃 script_v2/core 全部 .gd，非註解行不得出現 get_tree( 或 load("res://scenes（見 D1）。
func _test_no_node_dependency(t: Object) -> void:
	var files: Array = []
	_gather_gd("res://script_v2/core", files)
	t.ok(files.size() > 0, "無 Node 依賴：掃到 core 腳本檔")
	var offenders: Array = []
	for path: String in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var line_no: int = 0
		while not f.eof_reached():
			var line: String = f.get_line()
			line_no += 1
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue   # 略過註解
			if stripped.contains("get_tree(") or stripped.contains("load(\"res://scenes"):
				offenders.append(path + ":" + str(line_no))
		f.close()
	t.ok(offenders.is_empty(), "無 Node 依賴：core 無 get_tree/場景 load（違規：" + str(offenders) + "）")


func _gather_gd(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		var full: String = dir_path + "/" + name
		if d.current_is_dir():
			if name != "." and name != "..":
				_gather_gd(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
