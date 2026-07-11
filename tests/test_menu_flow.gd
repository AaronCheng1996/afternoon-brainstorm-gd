# P2-5 主選單 / 設定 / 終局統計 headless 驗收（見 docs/rebuild/06 P2-5）。
# 守：設定持久化 round-trip、終局畫面資料組裝與建構、主選單建構、battle 統計前幾名。
# 「觀感」與整條流程串接由人工於編輯器驗收（docs/rebuild/驗收_選單流程.md）。
extends RefCounted

const MenuScript := preload("res://scenes/menu/main_menu.gd")
const EndGameScript := preload("res://scenes/end_game/end_game.gd")
const BattleScene := preload("res://scenes/battle/battle.tscn")   # P7-4：battle 已編輯器化，改 instantiate


func run(t: Object) -> void:
	_test_settings_roundtrip(t)
	_test_end_game_build(t)
	_test_main_menu_build(t)
	_test_stat_bars(t)


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
	var e: Node = EndGameScript.new()
	e.configure(0, -10, 10, [0, -1, -3, -4, -7, -10], {
		"KILLED": [["player1_ADCW", 3], ["player2_TANKW", 1]],
		"DAMAGE_DEALT": [],
		"SCORED": [["player1_SPW", 6]],
	})
	t.ok(e._built, "end：configure 後已建構")
	t.eq(e._winner, 0, "end：勝者為 P1")
	t.eq(e._win_threshold, 10, "end：門檻 10")
	t.ok(e.get_child_count() > 0, "end：建出節點（背景/圖層/HUD）")
	# 空 score_history 也不崩潰。
	var e2: Node = EndGameScript.new()
	e2.configure(-1, 0, 8, [], {})
	t.ok(e2._built, "end：空資料也可建構")
	e.free()
	e2.free()


# ---------------- 3. 主選單建構 ----------------
func _test_main_menu_build(t: Object) -> void:
	var m: Node = MenuScript.new()
	m._build_ui()   # 未進場景樹，_ready 不會自動呼叫
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


# ---------------- 4. battle 統計前幾名（供終局圖表）----------------
func _test_stat_bars(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()
	var b: Node = BattleScene.instantiate()
	b.boot(["ADCW"], ["ADCW"], 1, db)
	b.set_animation_enabled(false)
	b._core.stats.increment(Statistics.StatType.KILLED, "player2_TANKW", 1)
	b._core.stats.increment(Statistics.StatType.KILLED, "player1_ADCW", 3)
	b._core.stats.increment(Statistics.StatType.DAMAGE_DEALT, "player1_ADCW", 24)
	var bars: Dictionary = b._build_stat_bars()
	t.ok(bars.has("KILLED") and bars.has("DAMAGE_DEALT") and bars.has("SCORED"), "bars：三類齊備")
	t.eq(bars["KILLED"][0][0], "player1_ADCW", "bars：擊殺最高者排第一")
	t.eq(bars["KILLED"][0][1], 3, "bars：擊殺最高值 3")
	t.ok(bars["KILLED"].size() <= 5, "bars：至多前 5 名")
	b.free()
	db.free()
