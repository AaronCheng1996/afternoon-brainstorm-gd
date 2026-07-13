# P8-4 百科圖鑑 headless 驗收（見 docs/rebuild/06 P8-4）。
# 守：場景建構、色系/職業篩選、單卡詳情組裝、攻擊模式圖示對應無缺漏、全卡詳情資料完整、
# 衍生物連結偵測。觀感（版面/動線）由人工於編輯器過目。
extends RefCounted

const EncScene := preload("res://scenes/encyclopedia/encyclopedia.tscn")
const EncScript := preload("res://scenes/encyclopedia/encyclopedia.gd")


func run(t: Object) -> void:
	_test_node_tree(t)
	_test_build_and_default_detail(t)
	_test_filters(t)
	_test_attack_icon_coverage(t)
	_test_card_data_integrity(t)
	_test_derivatives(t)


func _fresh_db() -> Object:
	return load("res://script/data/balance_db.gd").new()


func _booted(db: Object) -> Node:
	var e: Node = EncScene.instantiate()
	e.boot(db)
	return e


# ---------------- 0. 節點樹（instantiate 後 `%` 名稱解析成功）----------------
func _test_node_tree(t: Object) -> void:
	var e: Node = EncScene.instantiate()
	for name in ["Background", "PreviewRoot", "HUD", "ColorTabs", "JobTabs", "CardGrid",
			"DetailName", "DetailStats", "AttackCaption", "AttackIcons", "DetailDesc",
			"DerivCaption", "DerivRow", "BackBtn"]:
		t.ok(e.get_node_or_null("%" + name) != null, "enc tree：%s 節點存在" % name)
	e.free()


# ---------------- 1. 建構＋預設詳情 ----------------
func _test_build_and_default_detail(t: Object) -> void:
	var db := _fresh_db()
	var e := _booted(db)
	t.ok(e._ui_built, "enc：boot 後已建構")
	t.eq(e._color_tab_btns.size(), 10, "enc：10 個色系分頁")
	t.eq(e._job_tab_btns.size(), EncScript.JOB_ORDER.size() + 1, "enc：職業篩選＝全部＋8 職業")
	t.ok(e.get_node("%CardGrid").get_child_count() > 0, "enc：預設色頁有卡片")
	t.ok(e._current_id != "", "enc：預設自動選中第一張卡")
	t.ok(not (e.get_node("%DetailName") as Label).text.is_empty(), "enc：詳情名稱已填")
	t.ok(e.get_node("%PreviewRoot").get_child_count() >= 1, "enc：預覽有 PieceView")
	e.free()
	db.free()


# ---------------- 2. 色系／職業篩選 ----------------
func _test_filters(t: Object) -> void:
	var db := _fresh_db()
	# 魅紫（Purple）只有 4 職業。
	var e := _booted(db)
	e._select_color(9)   # P
	var p_ids: Array = e._cards_for_color()
	t.eq(p_ids.size(), 4, "enc：魅紫只有 4 張（AP/TANK/HF/ASS）")
	for id in p_ids:
		t.eq(db.color_code_of(id), "P", "enc：魅紫清單皆為 P 色 %s" % id)
	# 職業篩選 TANK：白色只留 TANKW。
	e._select_color(0)   # W
	e._select_job("TANK")
	var tank_ids: Array = e._cards_for_color()
	t.eq(tank_ids.size(), 1, "enc：蒼白×TANK 篩出 1 張")
	t.eq(db.job_of(tank_ids[0]), "TANK", "enc：篩選後職業為 TANK")
	# 全部復原。
	e._select_job("")
	t.ok(e._cards_for_color().size() >= 8, "enc：蒼白全部 ≥8 張")
	e.free()
	db.free()


# ---------------- 3. 攻擊模式圖示對應無缺漏 ----------------
func _test_attack_icon_coverage(t: Object) -> void:
	var db := _fresh_db()
	# 涵蓋 attack_type_tags 內所有職業（含 CUBE）。
	var jobs: Array = EncScript.JOB_ORDER.duplicate()
	jobs.append("CUBE")
	for job in jobs:
		var tags: String = db.attack_types(job)
		for tok in tags.split(" ", false):
			t.ok(EncScript.ATTACK_ICON.has(tok),
				"enc：攻擊 tag %s（%s）有圖示對應" % [tok, job])
			var file_name: String = EncScript.ATTACK_ICON.get(tok, "")
			var path: String = EncScript.ATTACK_ICON_DIR + file_name + ".png"
			t.ok(ResourceLoader.exists(path), "enc：圖示檔存在 %s" % path)
	db.free()


# ---------------- 4. 全卡詳情資料完整 ----------------
func _test_card_data_integrity(t: Object) -> void:
	var db := _fresh_db()
	var e := _booted(db)
	var checked: int = 0
	# 逐色系走訪百科實際可瀏覽的卡片集合（＝ _cards_for_color）。
	for i in EncScript.COLORS.size():
		e._select_color(i)
		e._select_job("")
		for id in e._cards_for_color():
			checked += 1
			var info: Dictionary = db.text(id)
			t.ok(not String(info.get("name", "")).is_empty(), "enc：%s 有名稱" % id)
			var desc: String = String(info.get("description", "")) + String(info.get("hint", ""))
			t.ok(not desc.strip_edges().is_empty(), "enc：%s 有描述/提示" % id)
			var st: Dictionary = db.stats(id)
			t.ok(st.has("health") and st.has("damage"), "enc：%s 有生命/攻擊數值" % id)
	t.eq(checked, 76, "enc：可瀏覽實卡共 76 張（9 色×8＋魅紫 4）")
	e.free()
	db.free()


# ---------------- 5. 衍生物連結偵測 ----------------
func _test_derivatives(t: Object) -> void:
	var db := _fresh_db()
	var e := _booted(db)
	# 緋紫射手（ADCF）描述含「影子」→ SHADOW 連結。
	e._show_detail("ADCF")
	t.ok(e.get_node("%DerivRow").get_child_count() >= 1, "enc：緋紫卡出現衍生物連結")
	t.ok((e.get_node("%DerivCaption") as Label).visible, "enc：有衍生物時標題可見")
	# 點連結不崩潰，預覽重建。
	e._show_derivative("SHADOW")
	t.ok(e.get_node("%PreviewRoot").get_child_count() >= 1, "enc：點 SHADOW 後仍有預覽")
	# 蒼白射手（ADCW）為純數值卡，無衍生物 → 連結列收起。
	e._show_detail("ADCW")
	t.ok(not (e.get_node("%DerivCaption") as Label).visible, "enc：無衍生物時標題隱藏")
	e.free()
	db.free()
