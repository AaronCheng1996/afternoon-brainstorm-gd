# P2-3 對戰場景 headless 冒煙測試（見 docs/rebuild/06 P2-3）。
# 「觀感/手感」由人工於編輯器跑 battle.tscn 驗收（見 docs/rebuild/驗收_對戰.md）；
# 這裡守可自動化的邏輯：所有行動經場景 dispatch 路徑正確驅動 core、視圖與 core 狀態同步、
# 攻擊範圍預覽（含鏡像）計算、勝負畫面與重開。以「動畫關（瞬時）」模式讓 _post_dispatch 同步收斂。
extends RefCounted

# P7-4：場景已編輯器化——battle.tscn 內宣告 UI 骨架，測試改為 instantiate 場景（見 08 §2.6/§4）。
const BattleScene := preload("res://scenes/battle/battle.tscn")
const BattleScript := preload("res://scenes/battle/battle.gd")   # 靜態 resource_deltas 用


func run(t: Object) -> void:
	var dbs: Array = []
	_test_node_tree(t, dbs)
	_test_attack_flow(t, dbs)
	_test_all_actions(t, dbs)
	_test_win_and_restart(t, dbs)
	_test_range_preview_with_shadow(t, dbs)
	_test_view_toggle(t, dbs)
	_test_view_at_freed(t, dbs)
	_test_resource_feedback(t, dbs)
	_test_hand_columns_fixed(t, dbs)   # P12-20（D21）固定左右欄
	_test_board_anchor_geometry(t, dbs)   # P14-2 棋盤幾何由場景注入
	for db in dbs:
		db.free()


# P9-3：資源事件飄字——純函式 resource_deltas 只回報正向變化（避免額外建場景，維持既有洩漏基準）。
func _test_resource_feedback(t: Object, _dbs: Array) -> void:
	var before := {"token": {"player1": 1, "player2": 0}, "coin": {"player1": 0, "player2": 3}}
	var after := {"token": {"player1": 3, "player2": 0}, "coin": {"player1": 0, "player2": 2}}
	var deltas: Array = BattleScript.resource_deltas(before, after)
	t.eq(deltas.size(), 1, "res：只回報正向變化（token +2；coin 減不報）")
	t.eq(deltas[0]["kind"], "token", "res：變化類別為 token")
	t.eq(deltas[0]["owner"], "player1", "res：變化擁有者為 P1")
	t.eq(deltas[0]["delta"], 2, "res：變化量 +2")
	t.eq(BattleScript.resource_deltas({}, {}).size(), 0, "res：空快照無變化")
	# 多類多方同時變化。
	var b2 := {"luck": {"player1": 0}, "totem": {"player2": 5}}
	var a2 := {"luck": {"player1": 2}, "totem": {"player2": 9}}
	t.eq(BattleScript.resource_deltas(b2, a2).size(), 2, "res：多類正向變化各記一筆")


# 斷言左右兩欄「存活」子節點數與 core 雙方 hand 同步。P12-20（D21）：欄位歸屬固定
# （左＝_left_seat()、右＝_right_seat()），**不隨換手互換**；只有可點性隨當前操作方變。
# 用存活數（排除 queue_free 待刪）：headless 場景不在樹上，queue_free 不會即時處理，
# 每次重建的舊鈕會殘留為待刪節點，故以 is_queued_for_deletion 過濾。
func _assert_hands_synced(t: Object, b: Node, tag: String) -> void:
	var left: String = b._left_seat()
	var right: String = b._right_seat()
	t.eq(_live(b._left_hand_box), b._core.get_player(left).hand.size(),
		"%s：左欄＝%s 手牌數" % [tag, left])
	t.eq(_live(b._right_hand_box), b._core.get_player(right).hand.size(),
		"%s：右欄＝%s 手牌數（D19 公開）" % [tag, right])


# 容器內尚未待刪（存活）子節點數。
func _live(container: Node) -> int:
	var n: int = 0
	for c in container.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


# 容器內第一個存活子節點。
func _first_live(container: Node) -> Node:
	for c in container.get_children():
		if not c.is_queued_for_deletion():
			return c
	return null


# ---------------- P12-20（D21）手牌固定左右欄 ----------------
# 核心不變式：**換手前後兩欄的所屬玩家不變**（不再互換位置），只有「可點與否」與標題隨當前
# 操作方切換；兩欄內容恆與 core 雙方 hand 同步（D19 公開）。各模式歸屬：本機雙人＝P1 左/P2 右；
# 單人 vs AI＝人類 P1 左、CPU P2 右（CPU 欄恆唯讀）；回放＝無主視角 P1 左/P2 右且兩欄皆唯讀。
# （連線＝我的席位恆左欄，於 test_net_battle_scene 驗；旁觀於 test_net_spectator_scene 驗。）
func _test_hand_columns_fixed(t: Object, dbs: Array) -> void:
	# (1) 本機雙人：換手不互換欄位，只換可點性。
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 202)
	t.eq(b._core.current_player(), "player1", "cols：開局當前＝P1")
	t.eq(b._left_seat(), "player1", "cols：本機左欄＝P1")
	t.eq(b._right_seat(), "player2", "cols：本機右欄＝P2")
	t.ok(b._hand_interactive("player1"), "cols：P1 回合→P1（左欄）可點")
	t.ok(not b._hand_interactive("player2"), "cols：P1 回合→P2（右欄）唯讀")
	t.ok(not _first_live(b._left_hand_box).disabled, "cols：左欄鈕可點（P1 回合）")
	t.ok(_first_live(b._right_hand_box).disabled, "cols：右欄鈕唯讀（P1 回合）")
	_assert_hands_synced(t, b, "cols：換手前")

	b._do("end_turn", -1, -1)
	t.eq(b._core.current_player(), "player2", "cols：換手後當前＝P2")
	t.eq(b._left_seat(), "player1", "cols：**換手後左欄仍＝P1**（不互換位置）")
	t.eq(b._right_seat(), "player2", "cols：**換手後右欄仍＝P2**（不互換位置）")
	t.ok(not b._hand_interactive("player1"), "cols：P2 回合→P1（左欄）轉唯讀")
	t.ok(b._hand_interactive("player2"), "cols：P2 回合→P2（右欄）轉可點")
	t.ok(_first_live(b._left_hand_box).disabled, "cols：左欄鈕轉唯讀（P2 回合）")
	t.ok(not _first_live(b._right_hand_box).disabled, "cols：右欄鈕轉可點（P2 回合）")
	_assert_hands_synced(t, b, "cols：換手後")
	b.free()

	# (2) 單人 vs AI：人類 P1 恆左欄；CPU（P2）欄恆唯讀（含輪到 CPU 時）。
	var db2: Object = _new_db()
	dbs.append(db2)
	var ai: Node = BattleScene.instantiate()
	ai.boot(_deck("ADCW", 12), _deck("ADCW", 12), 203, db2, "white")
	ai.set_animation_enabled(false)
	t.eq(ai._left_seat(), "player1", "cols：單人左欄＝人類 P1（主視角恆左）")
	t.eq(ai._right_seat(), "player2", "cols：單人右欄＝CPU P2")
	t.ok(ai._hand_interactive("player1"), "cols：單人 P1 回合人類可點")
	t.ok(not ai._hand_interactive("player2"), "cols：CPU 手牌唯讀（P1 回合）")
	ai._do("end_turn", -1, -1)   # 換到 CPU 回合（headless 無 _process，AI 不自動行動）
	t.eq(ai._left_seat(), "player1", "cols：單人換手後左欄仍＝人類 P1")
	t.ok(not ai._hand_interactive("player2"), "cols：CPU 回合 CPU 手牌仍唯讀")
	t.ok(not ai._hand_interactive("player1"), "cols：CPU 回合人類手牌唯讀")
	ai.free()

	# (3) 回放：無主視角＝P1 左/P2 右，兩欄皆唯讀。
	var db3: Object = _new_db()
	dbs.append(db3)
	var rp: Node = BattleScene.instantiate()
	rp.boot_replay(ReplayLog.new(204, _deck("ADCW", 12), _deck("ADCW", 12)), db3)
	rp.set_animation_enabled(false)
	t.eq(rp._left_seat(), "player1", "cols：回放左欄＝P1")
	t.eq(rp._right_seat(), "player2", "cols：回放右欄＝P2")
	t.ok(not rp._hand_interactive("player1"), "cols：回放左欄唯讀（純觀看）")
	t.ok(not rp._hand_interactive("player2"), "cols：回放右欄唯讀（純觀看）")
	rp.free()


func _new_db() -> Object:
	return load("res://script/data/balance_db.gd").new()


func _mk_battle(dbs: Array, p1: Array, p2: Array, seed_v: int) -> Node:
	var db: Object = _new_db()
	dbs.append(db)
	var b: Node = BattleScene.instantiate()
	b.boot(p1, p2, seed_v, db)
	b.set_animation_enabled(false)   # 瞬時模式：行動同步收斂（headless 無 _process）
	return b


# ---------------- 0. 節點樹存在（instantiate 後 `%` 名稱解析成功）----------------
func _test_node_tree(t: Object, dbs: Array) -> void:
	var b: Node = BattleScene.instantiate()
	# 世界層與 HUD 骨架皆宣告於 .tscn，instantiate 後即可解析。
	for name in ["Background", "BackgroundImage", "BoardAnchorOrtho", "BoardAnchorIso",
			"BoardSkinLayer", "BoardSkinOrtho", "BoardSkinIso",
			"GridLayer", "PersistLayer", "PreviewLayer", "BoardLayer",
			"FxLayer", "HUD", "Scoreboard", "ResLabel", "CountsLabel", "HintLabel",
			"AttackBtn", "MoveBtn", "HealBtn", "CubeBtn", "UpgradeBtn", "HintToggle", "AnimToggle",
			"ViewToggle", "EndTurnBtn", "LeftHandTitle", "LeftHandBox", "RightHandTitle", "RightHandBox",
			"WinPanel", "WinLabel", "RestartBtn", "StatsBtn", "MenuBtn"]:
		t.ok(b.get_node_or_null("%" + name) != null, "tree：%s 節點存在" % name)
	# 格線 10 條預置於 GridLayer。
	t.eq(b.get_node("%GridLayer").get_child_count(), 10, "tree：GridLayer 預置 10 條格線")
	b.free()


func _deck(card_id: String, n: int) -> Array:
	var d: Array = []
	for _i in n:
		d.append(card_id)
	return d


# ---------------- 1. 出牌 + 攻擊（經場景輸入路徑）----------------
func _test_attack_flow(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 100)

	# HUD 已組好、初盤無棋子。
	t.ok(b._ui_built, "attack：UI 已建構")
	t.ok(b._scoreboard != null, "attack：記分板已綁定")
	t.eq(b._scoreboard.score, b._core.score, "attack：記分板分數同步 core")
	t.eq(b._scoreboard.turn_number, b._core.turn_number, "attack：記分板回合同步 core")
	t.eq(b._views.size(), 0, "attack：初盤無棋子視圖")

	# D19 手牌公開＋P12-20（D21）固定左右欄：本機雙人＝P1 左欄、P2 右欄；當前操作方可點、另一方唯讀。
	# （複用本場景避免另建 battle 影響既有洩漏基準；用存活數排除 headless 下 queue_free 待刪的舊鈕。）
	_assert_hands_synced(t, b, "hands：開局")
	t.eq(b._left_seat(), "player1", "hands：本機雙人左欄＝P1")
	t.eq(b._right_seat(), "player2", "hands：本機雙人右欄＝P2")
	t.ok(_live(b._left_hand_box) > 0, "hands：左欄有手牌")
	t.ok(not _first_live(b._left_hand_box).disabled, "hands：左欄（當前操作方 P1）可點")
	t.ok(_first_live(b._right_hand_box).disabled, "hands：右欄（非操作方 P2）唯讀（disabled）")

	# p1 出一子於 (1,1)：選手牌單位 → 點空格放置。
	b._on_hand_pressed(0)
	t.eq(b._placing_index, 0, "attack：選單位卡進入放置狀態")
	b._board_click(Vector2i(1, 1))
	t.eq(b._core.player1.on_board.size(), 1, "attack：p1 出牌後場上 1 子")
	t.eq(b._placing_index, -1, "attack：放置後清除放置狀態")
	t.ok(b._views.has(Vector2i(1, 1)), "attack：(1,1) 有棋子視圖")
	t.eq(b._views.size(), 1, "attack：視圖與棋子同步（1）")
	# P9-3：_make_piece_view 依職業指派攻擊演出——ADC（大十字）為遠程投射物。
	var adc_view: Node2D = b._views[Vector2i(1, 1)]
	t.ok(adc_view.animation_set != null and adc_view.animation_set.has_projectile(),
		"attack：ADC 視圖獲遠程投射物演出（P9-3）")

	b._do("end_turn", -1, -1)
	t.eq(b._core.current_player(), "player2", "attack：換 p2")
	# P12-2：換手後現操作方永遠在己方列 → 兩列內容互換，仍與 core 同步。
	_assert_hands_synced(t, b, "hands：換手後")

	# p2 於同欄 (1,3) 放一子供 p1 大十字攻擊。
	b._on_hand_pressed(0)
	b._board_click(Vector2i(1, 3))
	t.eq(b._core.player2.on_board.size(), 1, "attack：p2 出牌後場上 1 子")
	b._do("end_turn", -1, -1)
	t.eq(b._core.turn_number, 2, "attack：turn=2")
	t.eq(b._core.number_of_attacks["player1"], 2, "attack：p1 攻擊次數累積 2")

	var target: PieceState = b._core.player2.on_board[0]
	var hp0: int = target.health
	# 攻擊模式（預設）點我方 (1,1) → 大十字命中同欄 (1,3)。
	t.eq(b._mode, "attack", "attack：預設攻擊模式")
	b._board_click(Vector2i(1, 1))
	t.eq(target.health, hp0 - 4, "attack：ADCW 大十字造成 4 傷")
	t.eq(b._core.number_of_attacks["player1"], 1, "attack：消耗 1 次攻擊")

	b.free()


# ---------------- 2. 全行動類型（出牌/升級切換/治療/移動兩段式/方塊/結束）----------------
func _test_all_actions(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 7)
	# 注入已知手牌與金幣（測試設定；行動仍全走場景 dispatch）。
	b._core.get_player("player1").hand.assign(["ADCW", "ADCC", "HEAL", "MOVE", "CUBES"])
	b._core.players_coin["player1"] = 50
	b._refresh_hud()

	# (1) 放置一般單位 ADCW → (0,0)。
	b._on_hand_pressed(0)
	b._board_click(Vector2i(0, 0))
	t.eq(b._core.player1.on_board.size(), 1, "all：ADCW 放置成功")

	# (2) 選 Cyan 卡 → 升級切換（名字加「 (+)」）。
	b._on_hand_pressed(0)   # 現在 hand[0]=ADCC
	t.eq(b._placing_index, 0, "all：選 Cyan 卡放置")
	b._on_toggle_upgrade()
	t.eq(b._core.player1.hand[0], "ADCC (+)", "all：升級切換加後綴")

	# (3) 放置升級版 ADCC → (0,1)（金幣足夠，price_check 通過）。
	b._board_click(Vector2i(0, 1))
	t.eq(b._core.player1.on_board.size(), 2, "all：升級 ADCC 放置成功")
	var upg_ok: bool = false
	for p: PieceState in b._core.player1.on_board:
		if p.card_id == "ADCC" and p.upgrade:
			upg_ok = true
	t.ok(upg_ok, "all：場上有升級版 ADCC")
	t.ok(b._core.players_coin["player1"] < 50, "all：升級版扣了金幣")

	# 讓 (0,0) 的 ADCW 解暈以便移動（入場暈眩不可移動）。
	var mover: PieceState = null
	for p: PieceState in b._core.player1.on_board:
		if p.pos() == Vector2i(0, 0):
			mover = p
	mover.set_numb(false)

	# (4) HEAL 魔法（即時打出獲得治療次數）→ 治療模式點自方棋子花掉。
	b._on_hand_pressed(0)   # HEAL
	t.eq(b._core.number_of_heals["player1"], 1, "all：HEAL 給 1 次治療")
	b._set_mode("heal")
	b._board_click(Vector2i(0, 0))
	t.eq(b._core.number_of_heals["player1"], 0, "all：治療花掉 1 次")

	# (5) MOVE 魔法 → 兩段式移動 (0,0)→(1,0)。
	b._on_hand_pressed(0)   # MOVE
	t.eq(b._core.number_of_movings["player1"], 1, "all：MOVE 給 1 次移動")
	b._set_mode("move")
	b._board_click(Vector2i(0, 0))   # 階段1：啟用移動（扣點）
	t.ok(mover.is_moving(), "all：移動階段1 棋子進入移動中")
	t.eq(b._core.number_of_movings["player1"], 0, "all：移動點於階段1 扣除")
	b._board_click(Vector2i(0, 0))   # 階段2a：選取
	b._board_click(Vector2i(1, 0))   # 階段2b：移動到相鄰空格
	t.eq(mover.pos(), Vector2i(1, 0), "all：兩段式移動成功到 (1,0)")

	# (6) CUBES 魔法 → 方塊模式放一顆中立方塊。
	b._on_hand_pressed(0)   # CUBES
	t.eq(b._core.number_of_cubes["player1"], 2, "all：CUBES 給 2 次方塊")
	b._set_mode("cube")
	b._board_click(Vector2i(2, 2))
	t.eq(b._core.neutral_pieces.size(), 1, "all：放置一顆中立方塊")
	t.eq(b._core.number_of_cubes["player1"], 1, "all：方塊花掉 1 次")

	# 視圖與 core 全部棋子同步（2 我方 + 1 中立）。
	t.eq(b._views.size(), 3, "all：視圖與全部棋子同步（3）")

	# (7) 結束回合換手。
	b._do("end_turn", -1, -1)
	t.eq(b._core.current_player(), "player2", "all：結束回合換 p2")

	# P12-4：從公開快照重建盤面（把 _rebuild_board 的資料源一般化為「core 或快照」）。
	# 複用本場景避免新增場景實例（維持洩漏基準）；附一個鏡像以覆蓋快照的 Fuchsia 重建路徑。
	var host: PieceState = b._core.player1.on_board[0]
	var sh: PieceState = PieceState.make_shadow(host, "player1", 3, 3, false)
	host.shadows.append(sh)
	var n: int = b._core.get_all_pieces().size()
	var snap: Dictionary = GameSnapshot.encode(b._core)
	# 經 JSON 往返後套用，證明序列化產物足以重建盤面（連線客端/旁觀/重連路徑）。
	b.apply_snapshot(JSON.parse_string(JSON.stringify(snap)))
	t.eq(b._views.size(), n, "snap：從快照重建盤面視圖數＝棋子數（%d）" % n)
	t.eq(b._shadow_views.size(), 1, "snap：從快照重建 Fuchsia 鏡像視圖 1")
	# 還原為 core 資料源後盤面一致（apply_snapshot({}) 回歸即時編碼）。
	b.apply_snapshot({})
	t.eq(b._views.size(), n, "snap：還原 core 資料源後盤面視圖數一致（%d）" % n)

	b.free()


# ---------------- 3. 勝負畫面 + 重開 ----------------
func _test_win_and_restart(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 3)
	# 注入一個非暈眩的 p1 棋子（每回合結算 −1）；反覆結束回合直到 p1 達門檻獲勝。
	var scorer: PieceState = PieceState.make("ADCW", "player1", 0, 0, b._core.balance)
	scorer.set_numb(false)
	b._core.player1.on_board.append(scorer)
	b._core.board.set_occupied(Vector2i(0, 0), true)

	var guard: int = 0
	while not b._core.is_over() and guard < 60:
		guard += 1
		b._do("end_turn", -1, -1)

	t.ok(b._core.is_over(), "win：達門檻結束對局")
	t.eq(b._core.winner(), 0, "win：p1（score<0）獲勝")
	t.ok(b._win_panel.visible, "win：勝負畫面顯示")
	t.ok(not b._win_label.text.is_empty(), "win：勝負文字非空")

	# 重開：勝負畫面隱藏、盤面清空、可再戰。
	b._on_win_restart()
	t.ok(not b._core.is_over(), "win：重開後對局重置")
	t.ok(not b._win_panel.visible, "win：重開後勝負畫面隱藏")
	t.eq(b._views.size(), 0, "win：重開後盤面清空")
	t.eq(b._core.current_player(), "player1", "win：重開後回到先手")

	b.free()


# ---------------- 4. 攻擊範圍預覽（含 Fuchsia 鏡像）----------------
func _test_range_preview_with_shadow(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 11)

	# ADCW 大十字：以 (1,1) 為中心，命中同行同列（不含自身）。
	var adc: PieceState = PieceState.make("ADCW", "player1", 1, 1, b._core.balance)
	var cells: Array = b._footprint_cells(adc)
	t.ok(cells.has(Vector2i(1, 0)), "range：大十字含同欄 (1,0)")
	t.ok(cells.has(Vector2i(3, 1)), "range：大十字含同列 (3,1)")
	t.ok(not cells.has(Vector2i(1, 1)), "range：不含自身格")
	t.ok(not cells.has(Vector2i(2, 2)), "range：不含斜角 (2,2)")

	# 掛一個鏡像（linker=ADCW → 鏡像用 large_cross）於 (3,3)：範圍應加入以 (3,3) 為中心的行列。
	var shadow: PieceState = PieceState.make_shadow(adc, "player1", 3, 3, false)
	adc.shadows.append(shadow)
	var cells2: Array = b._footprint_cells(adc)
	t.ok(cells2.has(Vector2i(3, 0)), "range：含鏡像大十字同欄 (3,0)")
	t.ok(cells2.has(Vector2i(0, 3)), "range：含鏡像大十字同列 (0,3)")

	# 小十字（TANK）：僅上下左右。
	var tank: PieceState = PieceState.make("TANKW", "player1", 1, 1, b._core.balance)
	var tcells: Array = b._footprint_cells(tank)
	t.ok(tcells.has(Vector2i(1, 0)) and tcells.has(Vector2i(0, 1)), "range：小十字含正交鄰格")
	t.ok(not tcells.has(Vector2i(3, 1)), "range：小十字不含遠格")

	b.free()


# ---------------- 5. 視角切換（45 度等距 ⇄ 俯視正交）----------------
func _test_view_toggle(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 5)

	# 預設 45 度（ISO）；鈕文字反映當前模式；cell→pixel→cell 恆等。
	t.eq(b._view.mode, BoardView.Mode.ISO, "view：預設 45 度（等距）")
	t.eq(b._view_toggle_btn.text, "視角：45度", "view：鈕文字＝45度")
	var mid := Vector2i(2, 1)
	t.eq(b._cell_from_global(b._cell_center(mid)), mid, "view：等距下中心反算恆等")

	# 切到俯視（正交）：模式、鈕文字、格線端點都改；換算仍恆等。
	b._toggle_board_mode()
	t.eq(b._view.mode, BoardView.Mode.ORTHO, "view：切為俯視（正交）")
	t.eq(b._view_toggle_btn.text, "視角：俯視", "view：鈕文字＝俯視")
	t.eq(b._cell_from_global(b._cell_center(mid)), mid, "view：正交下中心反算恆等")
	# 正交下水平格線 H0 應為水平（兩端 y 相同）；等距則否。
	var h0: Line2D = b._grid_layer.get_node("H0")
	t.ok(is_equal_approx(h0.points[0].y, h0.points[1].y), "view：正交 H0 為水平線")

	# 切回 45 度：格線 H0 兩端 y 不同（菱形斜線）。
	b._toggle_board_mode()
	t.eq(b._view.mode, BoardView.Mode.ISO, "view：切回 45 度")
	var h0b: Line2D = b._grid_layer.get_node("H0")
	t.ok(not is_equal_approx(h0b.points[0].y, h0b.points[1].y), "view：等距 H0 為斜線")

	b.free()


# ---------------- 6. _view_at 對已釋放實例的防護（死亡動畫中懸停不崩潰）----------------
func _test_view_at_freed(t: Object, dbs: Array) -> void:
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 9)
	# 出一子建立視圖，再直接釋放該視圖但保留 _views 對應（模擬死亡動畫 queue_free 後尚未重建盤面）。
	b._on_hand_pressed(0)
	b._board_click(Vector2i(1, 1))
	t.ok(b._view_at(Vector2i(1, 1)) != null, "freed：出牌後該格有視圖")
	var v: Node = b._views[Vector2i(1, 1)]
	v.free()
	# Godot 會把容器內已釋放的 Object 參考自動 null 化，_view_at 應據此回 null
	# （不再取用已釋放實例的 card_id 而報錯＝本次回報的當機）。
	t.ok(not is_instance_valid(b._views.get(Vector2i(1, 1))), "freed：_views 內參考已失效")
	t.eq(b._view_at(Vector2i(1, 1)), null, "freed：_view_at 對已釋放實例回 null")
	b._hover_cell = Vector2i(1, 1)
	b._update_hint_text()   # 舊行為會在此取用已釋放實例的 card_id 而報錯
	t.ok(true, "freed：懸停提示路徑不崩潰")

	b.free()


# ---------------- P14-2 棋盤幾何編輯器化 ----------------
# 棋盤原點來自場景裡可拖曳的 BoardAnchorOrtho/BoardAnchorIso 節點、格距來自 root @export；
# 兩者都要真的傳進 BoardView，而且棋子/格線/點擊反算整組跟著搬（美術拖了才有意義）。
func _test_board_anchor_geometry(t: Object, dbs: Array) -> void:
	# (A) 預設場景：注入值＝場景宣告值＝BoardView 常數（畫面與 P14-2 前相同）。
	var b: Node = _mk_battle(dbs, _deck("ADCW", 12), _deck("ADCW", 12), 77)
	t.eq(b._view.ortho_origin, b.get_node("%BoardAnchorOrtho").position,
		"P14-2：ortho 原點取自 BoardAnchorOrtho")
	t.eq(b._view.iso_origin, b.get_node("%BoardAnchorIso").position,
		"P14-2：iso 原點取自 BoardAnchorIso")
	t.eq(b._view.ortho_origin, BoardView.ORTHO_ORIGIN, "P14-2：場景預設 anchor＝置中常數（P12-20）")
	t.eq(b._view.iso_origin, BoardView.ISO_ORIGIN, "P14-2：場景預設 iso anchor＝置中常數")
	t.eq(b._view.ortho_stride, b.board_ortho_stride, "P14-2：ortho 格距取自 @export")
	t.eq(b._view.iso_hw, b.board_iso_half_width, "P14-2：iso 半寬取自 @export")
	t.eq(b._view.iso_hh, b.board_iso_half_height, "P14-2：iso 半高取自 @export")
	t.eq(b._view.cell_size, b.board_cell_size, "P14-2：格寬取自 @export")
	b.free()

	# (B) 美術把 anchor 拖走、改格距 → 棋子位置/格線/點擊反算整組隨動。
	var db: Object = _new_db()
	dbs.append(db)
	var b2: Node = BattleScene.instantiate()
	var moved_iso := BoardView.ISO_ORIGIN + Vector2(37.0, -21.0)
	b2.get_node("%BoardAnchorIso").position = moved_iso
	b2.get_node("%BoardAnchorOrtho").position = Vector2(100.0, 60.0)
	b2.board_iso_half_width = 70.0
	b2.board_iso_half_height = 55.0
	b2.board_ortho_stride = 130.0
	b2.boot(_deck("ADCW", 12), _deck("ADCW", 12), 77, db)
	b2.set_animation_enabled(false)

	t.eq(b2._view.iso_origin, moved_iso, "P14-2：拖動 anchor 後 iso 原點跟著變")
	t.eq(b2._view.iso_hw, 70.0, "P14-2：改 @export 後 iso 半寬跟著變")
	# 格中心＝新參數算出的位置（預設視角＝ISO）。
	var expect_center: Vector2 = moved_iso + Vector2((0.5 - 0.5) * 70.0, (0.5 + 0.5) * 55.0)
	t.ok(b2._cell_center(Vector2i(0, 0)).is_equal_approx(expect_center),
		"P14-2：格中心依新幾何算出")
	# 點擊反算跟著搬：新位置的中心反算回同格，舊位置已不再是該格中心。
	t.eq(b2._cell_from_global(expect_center), Vector2i(0, 0), "P14-2：新幾何下點擊反算正確")
	# 格線也依新幾何重排（H0 起點＝corner(0,0)＝新原點）。
	var h0: Line2D = b2._grid_layer.get_node("H0")
	t.ok(h0.points[0].is_equal_approx(moved_iso), "P14-2：格線依新原點重排")
	# 棋子定位面（`_cell_topleft`＝`_rebuild_board` 指派給每個 PieceView 的 position）亦依新幾何，
	# 且仍以新的 cell_size 對齊格心（開局盤面為空，故驗換算面而非既有視圖）。
	var cell := Vector2i(2, 1)
	t.ok(b2._cell_topleft(cell).is_equal_approx(
			b2._cell_center(cell) - Vector2(b2.board_cell_size, b2.board_cell_size) * 0.5),
		"P14-2：棋子左上角依新幾何且對齊格心")
	b2.free()
