# P9-3 攻擊演出資料庫 headless 驗收：依攻擊模式（Balance.attack_types）判遠程/近戰、派別色上色、快取。
# 純表現層資料（不影響對局）；視覺辨識由人工於 battle/anim_demo 過目。
extends RefCounted


func run(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()
	_test_ranged_vs_melee(t, db)
	_test_fx_color(t, db)
	_test_specials(t, db)
	db.free()


# 遠程（大十字 ADC / 最遠 SP）發射投射物；近戰（AP/TANK/HF/ASS/LF/APT）撲擊無投射物。
func _test_ranged_vs_melee(t: Object, db: Object) -> void:
	# 遠程職業（跨色驗證，判定只看攻擊模式 tag）。
	for cid in ["ADCW", "ADCR", "ADCB", "SPW", "SPC"]:
		t.ok(PieceAnimationLibrary.is_ranged(cid, db), "遠程：%s" % cid)
		t.ok(PieceAnimationLibrary.for_card(cid, db).has_projectile(), "遠程有投射物：%s" % cid)
	# 近戰職業。
	for cid in ["APW", "TANKW", "HFW", "ASSW", "LFW", "APTW"]:
		t.ok(not PieceAnimationLibrary.is_ranged(cid, db), "近戰：%s" % cid)
		t.ok(not PieceAnimationLibrary.for_card(cid, db).has_projectile(), "近戰無投射物：%s" % cid)


# 特效色＝派別色（color_rgb(色碼)）。
func _test_fx_color(t: Object, db: Object) -> void:
	var white := PieceAnimationLibrary.for_card("ADCW", db)
	t.ok(white.fx_color.is_equal_approx(db.color_rgb("W")), "ADCW 特效色＝白派別色")
	var red := PieceAnimationLibrary.for_card("ADCR", db)
	t.ok(red.fx_color.is_equal_approx(db.color_rgb("R")), "ADCR 特效色＝紅派別色")
	t.ok(not white.fx_color.is_equal_approx(red.fx_color), "不同派別特效色不同")


# 特殊卡（無職業）：不視為遠程、特效色為預設色。
func _test_specials(t: Object, db: Object) -> void:
	t.ok(not PieceAnimationLibrary.is_ranged("CUBE", db), "CUBE 非遠程")
	t.ok(not PieceAnimationLibrary.for_card("CUBE", db).has_projectile(), "CUBE 無投射物")
	t.ok(PieceAnimationLibrary.for_card("CUBE", db).fx_color.is_equal_approx(
		PieceAnimationLibrary.DEFAULT_FX), "無色卡用預設特效色")
