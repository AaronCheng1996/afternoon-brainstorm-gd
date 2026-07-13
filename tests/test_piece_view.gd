# P2-1 PieceView + 佔位形狀 headless 驗收（視覺辨識由人工於編輯器跑 piece_gallery.tscn 確認）。
# 這裡守住可自動化的資料組裝：形狀頂點、填色、外框（先/後手）、卡名/數值標籤、狀態圖示、鏡像模式。
extends RefCounted

const PieceShapesScript := preload("res://script/view/piece_shapes.gd")
const PieceViewScript := preload("res://scenes/battle/piece_view.gd")   # 常數用
const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")   # 實例化用（P7-3 編輯器化）

const SHAPE_KEYS := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP", "CUBE", "LUCKYBLOCK"]


func run(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()
	_test_node_tree(t)
	_test_shapes(t)
	_test_configure(t, db)
	_test_status_and_shadow(t, db)
	_test_all_cards(t, db)
	_test_animation_instant_invariance(t, db)
	db.free()   # BalanceDB extends Node，須手動釋放（對齊其他測試）


# P7-3：instantiate 場景後，`.tscn` 宣告的關鍵節點皆存在且能以 `%` 唯一名稱解析（未進樹亦可）。
func _test_node_tree(t: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	for path in ["VisualRoot", "VisualRoot/OutlineShape", "VisualRoot/PlaceholderShape",
			"VisualRoot/SpriteSlot", "StatsOverlay", "StatsOverlay/JobLabel", "StatsOverlay/NameLabel",
			"StatsOverlay/HealthLabel", "StatsOverlay/AttackLabel", "StatsOverlay/ArmorLabel",
			"StatsOverlay/ExtraLabel", "StatusIcons", "StatusIcons/NumbnessIcon",
			"StatusIcons/AngerIcon", "StatusIcons/MovingIcon"]:
		t.ok(v.get_node_or_null(path) != null, "節點存在：" + path)
	# 唯一名稱解析（未加入場景樹）。
	t.ok(v.get_node_or_null("%PlaceholderShape") != null, "唯一名稱 %PlaceholderShape 可解析")
	t.ok(v.get_node_or_null("%HealthLabel") != null, "唯一名稱 %HealthLabel 可解析")
	v.free()


func _test_shapes(t: Object) -> void:
	# 頂點數對齊 02 附錄。
	t.eq(PieceShapesScript.normalized("ADC").size(), 3, "ADC 三角形 3 點")
	t.eq(PieceShapesScript.normalized("TANK").size(), 4, "TANK 方形 4 點")
	t.eq(PieceShapesScript.normalized("HF").size(), 4, "HF 梯形 4 點")
	t.eq(PieceShapesScript.normalized("ASS").size(), 4, "ASS 燕形 4 點")
	t.eq(PieceShapesScript.normalized("APT").size(), 6, "APT 六邊形 6 點")
	t.eq(PieceShapesScript.normalized("SP").size(), 5, "SP 五邊鑽 5 點")
	t.eq(PieceShapesScript.normalized("LF").size(), 8, "LF 閃電 8 點")
	t.eq(PieceShapesScript.normalized("CUBE").size(), 4, "CUBE 4 點")
	t.eq(PieceShapesScript.normalized("LUCKYBLOCK").size(), 4, "LUCKYBLOCK 4 點")
	t.ok(PieceShapesScript.normalized("AP").size() >= 12, "AP 圓形近似 ≥12 點")
	t.eq(PieceShapesScript.normalized("NOPE").size(), 0, "未知形狀回空")

	# 正規化頂點皆落在 0..1。
	for key in SHAPE_KEYS:
		for p in PieceShapesScript.normalized(key):
			t.ok(p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0, "正規化範圍 " + key)

	# 縮放：TANK 左上角 (0.25,0.25) × 96 = (24,24)。
	var sc := PieceShapesScript.scaled("TANK", 96.0)
	t.ok(is_equal_approx(sc[0].x, 24.0) and is_equal_approx(sc[0].y, 24.0), "scaled TANK 首點=(24,24)")
	# extra_scale 以中心放大：SHADOW 1.1 使邊界外擴。
	var sc11 := PieceShapesScript.scaled("TANK", 96.0, 1.1)
	t.ok(sc11[0].x < sc[0].x, "extra_scale 1.1 使頂點外擴")


func _test_configure(t: Object, db: Object) -> void:
	# ADCW：白色三角形、先手紅框、職業碼 ADC、HP5/ATK4。
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("ADCW", 1, db)
	t.eq(v.job_label.text, "ADC", "ADCW 中央職業碼")
	t.eq(v.health_label.text, "5", "ADCW HP=5")
	t.eq(v.attack_label.text, "4", "ADCW ATK=4")
	t.eq(v.placeholder_shape.polygon.size(), 3, "ADCW 三角形")
	t.ok(v.placeholder_shape.color.is_equal_approx(Color(1, 1, 1)), "ADCW 白色填充")
	t.ok(v.outline_shape.color.r > v.outline_shape.color.b, "先手＝紅框(r>b)")
	t.ok(not v.name_label.text.is_empty(), "ADCW 卡名非空")
	v.free()

	# TANKBR：方形、後手藍框、HP20/ATK1。
	var v2: Node2D = PieceViewScene.instantiate()
	v2.configure("TANKBR", 2, db)
	t.eq(v2.placeholder_shape.polygon.size(), 4, "TANK 方形")
	t.eq(v2.health_label.text, "20", "TANKBR HP=20")
	t.eq(v2.attack_label.text, "1", "TANKBR ATK=1")
	t.ok(v2.outline_shape.color.b > v2.outline_shape.color.r, "後手＝藍框(b>r)")
	v2.free()

	# APW：圓形。
	var v3: Node2D = PieceViewScene.instantiate()
	v3.configure("APW", 1, db)
	t.ok(v3.placeholder_shape.polygon.size() >= 12, "APW 圓形")
	v3.free()

	# CUBE：中立灰框、以 CUBE 形狀。
	var v4: Node2D = PieceViewScene.instantiate()
	v4.configure("CUBE", 0, db)
	t.eq(v4.placeholder_shape.polygon.size(), 4, "CUBE 小方塊")
	t.ok(v4.outline_shape.color.is_equal_approx(PieceViewScript.NEUTRAL_OUTLINE), "CUBE 中立灰框")
	v4.free()


func _test_status_and_shadow(t: Object, db: Object) -> void:
	# 狀態圖示開關。
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("APW", 1, db)
	t.ok(not v.is_status_visible("numbness"), "初始無麻痺圖示")
	v.set_status("numbness", true)
	t.ok(v.is_status_visible("numbness"), "麻痺圖示可顯示")
	v.set_status("anger", true)
	t.ok(v.is_status_visible("anger"), "怒氣圖示可顯示")
	v.set_status("numbness", false)
	t.ok(not v.is_status_visible("numbness"), "麻痺圖示可隱藏")
	v.free()

	# 鏡像模式：沿用 linker 職業形狀、半透明、不顯數值。
	var s: Node2D = PieceViewScene.instantiate()
	s.configure("SHADOW", 1, db, true, "ADC")
	t.eq(s.placeholder_shape.polygon.size(), 3, "SHADOW 沿用 ADC 三角形")
	t.ok(s.placeholder_shape.color.a < 1.0, "SHADOW 半透明")
	t.ok(not s.health_label.visible, "SHADOW 不顯 HP")
	t.ok(not s.attack_label.visible, "SHADOW 不顯 ATK")
	s.free()


func _test_all_cards(t: Object, db: Object) -> void:
	# 遍歷 BalanceDB 全卡（含 CUBE/LUCKYBLOCK 別名）→ 皆可組裝出形狀與非空卡名。
	var missing := 0
	for cid in db.all_card_ids():
		var v: Node2D = PieceViewScene.instantiate()
		v.configure(cid, 1, db)
		if v.placeholder_shape.polygon.size() == 0:
			missing += 1
		v.free()
	t.eq(missing, 0, "全卡皆有佔位形狀")


# P9-2：瞬時模式（動畫關）不變性——受擊/死亡不生任何特效、不改 visual_root，死亡立即回呼。
# 這守住「表現層強化不得改變動畫關時的行為」（鐵則 4/驗收）。
func _test_animation_instant_invariance(t: Object, db: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("ADCW", 1, db)
	t.ok(v.fx_layer == null, "fx_layer 預設為 null（退回自身）")

	v.instant = true
	var fx := Node2D.new()
	v.fx_layer = fx
	v.play_hurt()
	t.eq(fx.get_child_count(), 0, "瞬時受擊：不生粒子")
	t.ok(v.visual_root.scale.is_equal_approx(Vector2.ONE), "瞬時受擊：不改縮放")
	t.ok(v.visual_root.modulate.is_equal_approx(Color(1, 1, 1, 1)), "瞬時受擊：不改亮度")

	var done := [false]
	v.play_death(func() -> void: done[0] = true)
	t.ok(done[0], "瞬時死亡：立即回呼")
	t.eq(fx.get_child_count(), 0, "瞬時死亡：不生殘影/粒子")

	fx.free()
	v.free()
