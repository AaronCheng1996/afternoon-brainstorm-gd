# P8-5 記分板元件 headless 測試（見 docs/rebuild/06 P8-5）。
# 守：update_board() 後顯示值與傳入資料同步——分差正負、達門檻旗標、回合/當前玩家文字、
# 動態長條（記分條填色＋中線、趨勢柱＋中線）數量。純表現層，不依賴 GameCore。
# 「觀感/可讀性」由人工於編輯器過目（driver：battle.tscn）。
extends RefCounted

const ScoreboardScene := preload("res://scenes/battle/scoreboard.tscn")


func run(t: Object) -> void:
	_test_node_tree(t)
	_test_leader_and_lead(t)
	_test_threshold(t)
	_test_turn_text(t)
	_test_meter_children(t)
	_test_trend_children(t)


func _mk() -> Node:
	return ScoreboardScene.instantiate()


# ---------------- 0. 節點樹（`%` 解析）----------------
func _test_node_tree(t: Object) -> void:
	var sb: Node = _mk()
	for name in ["TurnLabel", "LeadLabel", "ThresholdLabel", "MeterTrack", "MeterFillRoot",
			"TrendTitle", "TrendRoot"]:
		t.ok(sb.get_node_or_null("%" + name) != null, "tree：%s 節點存在" % name)
	sb.free()


# ---------------- 1. 領先方判定與讀數（含正負分）----------------
func _test_leader_and_lead(t: Object) -> void:
	var sb: Node = _mk()

	# 負分 = 先手 P1 領先。
	sb.update_board(-3, 10, 4, "player1", [])
	t.eq(sb.leader(), 0, "lead：score<0 → P1 領先")
	t.eq(sb.lead_amount(), 3, "lead：領先幅度 3")
	t.ok(sb.get_node("%LeadLabel").text.begins_with("P1 領先 3"), "lead：讀數文字 P1 領先 3")

	# 正分 = 後手 P2 領先。
	sb.update_board(5, 10, 6, "player2", [])
	t.eq(sb.leader(), 1, "lead：score>0 → P2 領先")
	t.eq(sb.lead_amount(), 5, "lead：領先幅度 5")
	t.ok(sb.get_node("%LeadLabel").text.begins_with("P2 領先 5"), "lead：讀數文字 P2 領先 5")

	# 平手。
	sb.update_board(0, 10, 2, "player1", [])
	t.eq(sb.leader(), -1, "lead：score==0 → 平手")
	t.eq(sb.get_node("%LeadLabel").text, "平手", "lead：讀數文字 平手")

	sb.free()


# ---------------- 2. 達門檻旗標與標示 ----------------
func _test_threshold(t: Object) -> void:
	var sb: Node = _mk()

	sb.update_board(-9, 10, 8, "player1", [])
	t.ok(not sb.at_threshold(), "thr：|9| < 10 未達門檻")
	t.ok(not sb.get_node("%LeadLabel").text.contains("達門檻"), "thr：未達門檻不加標示")

	sb.update_board(-10, 10, 10, "player1", [])
	t.ok(sb.at_threshold(), "thr：|10| >= 10 達門檻")
	t.ok(sb.get_node("%LeadLabel").text.contains("達門檻"), "thr：達門檻加標示")

	# 正向達門檻同樣成立。
	sb.update_board(12, 10, 11, "player2", [])
	t.ok(sb.at_threshold(), "thr：+12 >= 10 達門檻（P2）")

	# 門檻讀數文字含雙方勝利條件。
	t.ok(sb.get_node("%ThresholdLabel").text.contains("10"), "thr：門檻標籤含門檻值")

	sb.free()


# ---------------- 3. 回合/當前玩家文字 ----------------
func _test_turn_text(t: Object) -> void:
	var sb: Node = _mk()

	sb.update_board(0, 10, 7, "player1", [])
	var txt1: String = sb.get_node("%TurnLabel").text
	t.ok(txt1.contains("回合 7"), "turn：含回合數 7")
	t.ok(txt1.contains("先手 P1"), "turn：當前先手 P1")

	sb.update_board(0, 10, 8, "player2", [])
	var txt2: String = sb.get_node("%TurnLabel").text
	t.ok(txt2.contains("回合 8"), "turn：含回合數 8")
	t.ok(txt2.contains("後手 P2"), "turn：當前後手 P2")

	sb.free()


# ---------------- 4. 記分條動態子節點（填色 + 中線）----------------
func _test_meter_children(t: Object) -> void:
	var sb: Node = _mk()

	# 平手：僅中線（無填色）。
	sb.update_board(0, 10, 1, "player1", [])
	t.eq(sb.meter_child_count(), 1, "meter：平手僅中線")

	# 有領先：填色 + 中線 = 2。
	sb.update_board(-4, 10, 2, "player1", [])
	t.eq(sb.meter_child_count(), 2, "meter：領先時填色+中線")

	# 重複更新不累積（每次重建）。
	sb.update_board(6, 10, 3, "player2", [])
	t.eq(sb.meter_child_count(), 2, "meter：更新後不累積殘留")

	sb.free()


# ---------------- 5. 趨勢動態子節點（中線 + 每回合一柱）----------------
func _test_trend_children(t: Object) -> void:
	var sb: Node = _mk()

	# 空歷史：僅中線。
	sb.update_board(0, 10, 0, "player1", [])
	t.eq(sb.trend_child_count(), 1, "trend：空歷史僅中線")

	# 5 筆歷史：中線 + 5 柱 = 6。
	sb.update_board(-3, 10, 5, "player1", [0, -1, 1, -2, -3])
	t.eq(sb.trend_child_count(), 6, "trend：5 筆 → 中線+5 柱")

	# 超過 TREND_MAX(8)：只顯示最近 8 筆 → 中線 + 8 = 9。
	var long_hist: Array = []
	for i in 12:
		long_hist.append(i - 6)
	sb.update_board(5, 10, 12, "player2", long_hist)
	t.eq(sb.trend_child_count(), 9, "trend：>8 筆只取最近 8 → 中線+8")

	sb.free()
