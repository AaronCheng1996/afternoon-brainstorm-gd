# P2-5 主選單 / 設定 / 終局統計 headless 驗收（見 docs/rebuild/06 P2-5）。
# 守：設定持久化 round-trip、終局畫面資料組裝與建構、主選單建構、battle 統計前幾名。
# 「觀感」與整條流程串接由人工於編輯器驗收（docs/rebuild/驗收_選單流程.md）。
extends RefCounted

const MenuScene := preload("res://scenes/menu/main_menu.tscn")     # P7-6：改 instantiate
const EndGameScene := preload("res://scenes/end_game/end_game.tscn")  # P7-6：改 instantiate
const BattleScene := preload("res://scenes/battle/battle.tscn")   # P7-4：battle 已編輯器化，改 instantiate


func run(t: Object) -> void:
	_test_node_tree(t)
	_test_settings_roundtrip(t)
	_test_end_game_build(t)
	_test_main_menu_build(t)
	_test_stat_bars(t)


# ---------------- 0. 節點樹存在（instantiate 後 `%` 名稱解析成功）----------------
func _test_node_tree(t: Object) -> void:
	var m: Node = MenuScene.instantiate()
	for name in ["Background", "HUD", "TitleLabel", "SubtitleLabel", "LocalBattleBtn",
			"EncyclopediaBtn", "EndlessBtn", "SettingsBtn", "QuitBtn", "MsgLabel", "VersionLabel",
			"SettingsPanel", "HintBtn", "AnimBtn", "BackBtn"]:
		t.ok(m.get_node_or_null("%" + name) != null, "menu tree：%s 節點存在" % name)
	m.free()

	var e: Node = EndGameScene.instantiate()
	for name in ["Background", "ChartLayer", "HUD", "TitleLabel", "ChartCaption",
			"BarsRoot", "AgainBtn", "MenuBtn"]:
		t.ok(e.get_node_or_null("%" + name) != null, "end tree：%s 節點存在" % name)
	e.free()


# ---------------- 1. 設定持久化 round-trip ----------------
func _test_settings_roundtrip(t: Object) -> void:
	var existed: bool = FileAccess.file_exists(SettingsStore.PATH)
	var orig: Dictionary = SettingsStore.load_settings()

	SettingsStore.save_settings(false, false)
	var r: Dictionary = SettingsStore.load_settings()
	t.eq(r["hints_on"], false, "settings：hints 存 false 後讀回 false")
	t.eq(r["animations_on"], false, "settings：animations 存 false 後讀回 false")

	SettingsStore.save_settings(true, false)
	var r2: Dictionary = SettingsStore.load_settings()
	t.eq(r2["hints_on"], true, "settings：hints 改 true")
	t.eq(r2["animations_on"], false, "settings：animations 維持 false")

	# 還原（不留測試痕跡）。
	if existed:
		SettingsStore.save_settings(bool(orig["hints_on"]), bool(orig["animations_on"]))
	else:
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("settings.json")


# ---------------- 2. 終局統計畫面建構 ----------------
func _test_end_game_build(t: Object) -> void:
	var e: Node = EndGameScene.instantiate()
	# P8-6：configure 改收完整統計 export（{stat_name: {owner_cardid: int}}）。
	e.configure(0, -10, 10, [0, -1, -3, -4, -7, -10], {
		"KILLED": {"player1_ADCW": 3, "player2_TANKW": 1},
		"DAMAGE_DEALT": {"player1_ADCW": 24},
		"SCORED": {"player1_SPW": 6, "player2_ADCW": 2},
	})
	t.ok(e._built, "end：configure 後已建構")
	t.eq(e._winner, 0, "end：勝者為 P1")
	t.eq(e._win_threshold, 10, "end：門檻 10")
	t.ok(e.get_node("%ChartLayer").get_child_count() > 0, "end：折線圖層繪出內容")
	t.ok(e.get_node("%BarsRoot").get_child_count() > 0, "end：統計長條繪出內容")

	# P8-6 z-order：ChartFrame 移出 HUD、位於 ChartLayer 之前（樹序在下＝渲染於折線之下）。
	var root_children: Array = e.get_children()
	t.ok(root_children.find(e.get_node("%ChartFrame")) < root_children.find(e.get_node("%ChartLayer")),
		"end：ChartFrame 樹序在 ChartLayer 之前（折線不被遮）")

	# P8-6 表格：table_data() 與傳入 Statistics 一致（含未列於某類的欄位補 0）。
	var td: Dictionary = e.table_data()
	t.eq(td["player1_ADCW"]["KILLED"], 3, "table：ADCW 擊殺 3")
	t.eq(td["player1_ADCW"]["DAMAGE_DEALT"], 24, "table：ADCW 造成傷害 24")
	t.eq(td["player1_ADCW"]["SCORED"], 0, "table：ADCW 未得分補 0")
	t.eq(td["player1_SPW"]["SCORED"], 6, "table：SPW 得分 6")
	t.eq(td["player2_ADCW"]["SCORED"], 2, "table：P2 ADCW 得分 2")
	t.ok(e.get_node("%TableRoot").get_child_count() > 0, "table：TableRoot 產出內容")

	# P8-6 圖／表切換：預設圖表；切換後表格顯示、圖表群隱藏。
	t.ok(not e._show_table, "view：預設為圖表")
	t.ok(e.get_node("%ChartFrame").visible and not e.get_node("%TableRoot").visible, "view：圖表可見/表格隱藏")
	e.toggle_view()
	t.ok(e._show_table, "view：切換後為表格")
	t.ok(e.get_node("%TableRoot").visible and not e.get_node("%ChartFrame").visible, "view：表格可見/圖表隱藏")
	e.toggle_view()
	t.ok(not e._show_table, "view：再切回圖表")

	# 空 score_history / 空統計也不崩潰。
	var e2: Node = EndGameScene.instantiate()
	e2.configure(-1, 0, 8, [], {})
	t.ok(e2._built, "end：空資料也可建構")
	t.eq(e2.table_data().size(), 0, "end：空統計 table_data 為空")
	e.free()
	e2.free()


# ---------------- 3. 主選單建構 ----------------
func _test_main_menu_build(t: Object) -> void:
	var m: Node = MenuScene.instantiate()
	m._bind_nodes()   # 未進場景樹，_ready 不會自動呼叫
	t.ok(m._ui_built, "menu：UI 已建構")
	t.ok(m._settings_panel != null and not m._settings_panel.visible, "menu：設定面板預設隱藏")
	# 開設定 → 顯示；切換不崩潰（會寫檔，之後 round-trip 測試已保護，這裡切回原值）。
	m._on_open_settings()
	t.ok(m._settings_panel.visible, "menu：開啟設定面板")
	var before: bool = m._hints_on
	m._on_toggle_hint()
	t.eq(m._hints_on, not before, "menu：切換提示開關")
	m._on_toggle_hint()   # 切回
	m._on_close_settings()
	t.ok(not m._settings_panel.visible, "menu：關閉設定面板")
	m.free()
	# 清掉切換寫入的檔（保持乾淨）。
	var d := DirAccess.open("user://")
	if d != null and d.file_exists("settings.json"):
		d.remove("settings.json")


# ---------------- 4. 統計摘要長條 + 表格（battle stats → end_game，P8-6）----------------
# P8-6：摘要長條與表格改由 end_game 從完整 export 派生（單一資料源）；此測經真實 battle stats
# → export_for_charts() → end_game 驗證 top-N 排序與 per-卡表格與 Statistics 一致。
func _test_stat_bars(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var b: Node = BattleScene.instantiate()
	b.boot(["ADCW"], ["ADCW"], 1, db)
	b.set_animation_enabled(false)
	# 造 >5 個擊殺者以驗證取前 5 名。
	b._core.stats.increment(Statistics.StatType.KILLED, "player2_TANKW", 1)
	b._core.stats.increment(Statistics.StatType.KILLED, "player1_ADCW", 3)
	for i in 5:
		b._core.stats.increment(Statistics.StatType.KILLED, "player1_C%d" % i, i + 1)
	b._core.stats.increment(Statistics.StatType.DAMAGE_DEALT, "player1_ADCW", 24)

	var e: Node = EndGameScene.instantiate()
	e.configure(0, -1, 10, [], b._core.stats.export_for_charts())

	# 摘要長條：降冪、至多前 5。
	var killed: Array = e._bars_for("KILLED")
	t.eq(killed[0][0], "player1_C4", "bars：擊殺最高者（C4=5）排第一")
	t.eq(killed[0][1], 5, "bars：擊殺最高值 5")
	t.ok(killed.size() <= 5, "bars：至多前 5 名")

	# 表格：per 卡值與 Statistics 一致。
	var td: Dictionary = e.table_data()
	t.eq(td["player1_ADCW"]["KILLED"], 3, "table：ADCW 擊殺 3 與 Statistics 一致")
	t.eq(td["player1_ADCW"]["DAMAGE_DEALT"], 24, "table：ADCW 傷害 24 與 Statistics 一致")
	t.eq(td["player2_TANKW"]["KILLED"], 1, "table：P2 TANKW 擊殺 1 與 Statistics 一致")

	e.free()
	b.free()
	db.free()
