# P9-1 BoardView 座標換算 headless 測試（見 docs/rebuild/06 P9-1）。
# 守：正交/等距兩模式下 cell→pixel→cell 恆等、格中心/頂點/深度序自洽、
# 正交模式像素與 P2 舊常數完全一致（切回不位移）。
extends RefCounted

const BoardViewScript := preload("res://scenes/battle/board_view.gd")


func run(t: Object) -> void:
	_test_roundtrip(t, BoardViewScript.Mode.ORTHO, "ortho")
	_test_roundtrip(t, BoardViewScript.Mode.ISO, "iso")
	_test_ortho_matches_legacy(t)
	_test_topleft_centered(t)
	_test_polygon_and_depth(t)
	_test_out_of_board(t)
	_test_polygon_inset(t)   # P12-22 所有權外框內縮


# 每格中心反算回同格；格內任一取樣點也落在該格。
func _test_roundtrip(t: Object, mode: int, tag: String) -> void:
	var bv: Object = BoardViewScript.new()
	bv.mode = mode
	for y in range(BoardViewScript.BOARD):
		for x in range(BoardViewScript.BOARD):
			var cell := Vector2i(x, y)
			var center: Vector2 = bv.cell_center(cell)
			t.eq(bv.cell_from_pixel(center), cell, "%s：中心反算 (%d,%d)" % [tag, x, y])
			# 格內四個偏移取樣（避開邊界），都應反算回本格。
			for off in [Vector2(-12, -8), Vector2(12, -8), Vector2(-12, 8), Vector2(12, 8)]:
				t.eq(bv.cell_from_pixel(center + off), cell,
					"%s：格內取樣反算 (%d,%d)" % [tag, x, y])


# 正交模式的 cell→pixel 公式：topleft＝origin+cell*stride+inset、center＝origin+cell*stride+stride/2。
# P12-20（D21）棋盤置中後 origin 由 (40,150) 改為 ORTHO_ORIGIN，故改由常數導出（守公式而非絕對像素）。
func _test_ortho_matches_legacy(t: Object) -> void:
	var bv: Object = BoardViewScript.new()
	bv.mode = BoardViewScript.Mode.ORTHO
	var origin: Vector2 = BoardViewScript.ORTHO_ORIGIN
	var stride: float = BoardViewScript.ORTHO_STRIDE
	var inset := (stride - BoardViewScript.CELL) * 0.5
	for cell in [Vector2i(0, 0), Vector2i(1, 2), Vector2i(3, 3)]:
		var legacy_topleft: Vector2 = origin + Vector2(cell) * stride + Vector2(inset, inset)
		var legacy_center: Vector2 = origin + Vector2(cell) * stride + Vector2(stride, stride) * 0.5
		t.ok(bv.cell_topleft(cell).is_equal_approx(legacy_topleft),
			"ortho：topleft 與舊值一致 (%d,%d)" % [cell.x, cell.y])
		t.ok(bv.cell_center(cell).is_equal_approx(legacy_center),
			"ortho：center 與舊值一致 (%d,%d)" % [cell.x, cell.y])


# 佔位棋子（96 方形）以左上為原點時，其視覺中心對齊格中心。
func _test_topleft_centered(t: Object) -> void:
	for mode in [BoardViewScript.Mode.ORTHO, BoardViewScript.Mode.ISO]:
		var bv: Object = BoardViewScript.new()
		bv.mode = mode
		var cell := Vector2i(2, 1)
		var recentered: Vector2 = bv.cell_topleft(cell) + Vector2(BoardViewScript.CELL, BoardViewScript.CELL) * 0.5
		t.ok(recentered.is_equal_approx(bv.cell_center(cell)), "topleft+半格=中心 (mode=%d)" % mode)


# cell_polygon 為四頂點；等距下為菱形（四頂點皆不同、非軸對齊方形）；depth 隨 x+y 遞增。
func _test_polygon_and_depth(t: Object) -> void:
	var bv: Object = BoardViewScript.new()
	bv.mode = BoardViewScript.Mode.ISO
	var poly: PackedVector2Array = bv.cell_polygon(Vector2i(1, 1))
	t.eq(poly.size(), 4, "iso：cell_polygon 四頂點")
	# 等距菱形：相鄰頂點的 x 與 y 都在變（非正交方形的水平/垂直邊）。
	t.ok(poly[0].x != poly[1].x and poly[0].y != poly[1].y, "iso：多邊形為菱形（邊斜向）")
	t.eq(bv.depth(Vector2i(3, 3)), 6, "depth(3,3)=6")
	t.ok(bv.depth(Vector2i(2, 1)) < bv.depth(Vector2i(2, 2)), "depth 隨 x+y 遞增")


# 界外像素回傳 (-1,-1)。
func _test_out_of_board(t: Object) -> void:
	for mode in [BoardViewScript.Mode.ORTHO, BoardViewScript.Mode.ISO]:
		var bv: Object = BoardViewScript.new()
		bv.mode = mode
		# 遠離棋盤的點必在界外。
		t.eq(bv.cell_from_pixel(Vector2(-9999, -9999)), Vector2i(-1, -1), "界外(左上, mode=%d)" % mode)
		t.eq(bv.cell_from_pixel(Vector2(9999, 9999)), Vector2i(-1, -1), "界外(右下, mode=%d)" % mode)


# P12-22：所有權外框內縮多邊形——每頂點嚴格落在原格多邊形內（正交＋等距），且相鄰格的
# 內縮框彼此分離（原本共邊，兩格皆有棋子時外框互相覆蓋、無法分辨先後手）。
func _test_polygon_inset(t: Object) -> void:
	const INSET := 6.0
	for mode in [BoardViewScript.Mode.ORTHO, BoardViewScript.Mode.ISO]:
		var bv: Object = BoardViewScript.new()
		bv.mode = mode
		var tag: String = "ortho" if mode == BoardViewScript.Mode.ORTHO else "iso"
		for cell in [Vector2i(0, 0), Vector2i(1, 2), Vector2i(3, 3)]:
			var base: PackedVector2Array = bv.cell_polygon(cell)
			var ins: PackedVector2Array = bv.cell_polygon_inset(cell, INSET)
			t.eq(ins.size(), base.size(), "%s：內縮多邊形頂點數不變 (%d,%d)" % [tag, cell.x, cell.y])
			for i in ins.size():
				t.ok(Geometry2D.is_point_in_polygon(ins[i], base),
					"%s：內縮頂點 %d 嚴格落在原格內 (%d,%d)" % [tag, i, cell.x, cell.y])
				t.ok(ins[i].distance_to(base[i]) > 0.5,
					"%s：頂點 %d 確實內移 (%d,%d)" % [tag, i, cell.x, cell.y])
		# 相鄰兩格（共邊）：內縮後兩框最近頂點仍有間距 → 不再重疊、各自可辨。
		var a: PackedVector2Array = bv.cell_polygon_inset(Vector2i(1, 1), INSET)
		var b: PackedVector2Array = bv.cell_polygon_inset(Vector2i(2, 1), INSET)
		var min_d := INF
		for pa in a:
			for pb in b:
				min_d = minf(min_d, pa.distance_to(pb))
		t.ok(min_d > 1.0, "%s：相鄰格內縮框分離（最近頂點距離 %.1f > 0）" % [tag, min_d])
		# 對照：未內縮時相鄰格共用兩個頂點（距離 0）＝原本互相覆蓋的成因。
		var a0: PackedVector2Array = bv.cell_polygon(Vector2i(1, 1))
		var b0: PackedVector2Array = bv.cell_polygon(Vector2i(2, 1))
		var shared := 0
		for pa in a0:
			for pb in b0:
				if pa.distance_to(pb) < 0.001:
					shared += 1
		t.eq(shared, 2, "%s：未內縮時相鄰格共用 2 頂點（共邊＝覆蓋成因）" % tag)
