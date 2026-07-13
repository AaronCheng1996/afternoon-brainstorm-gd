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


# 正交模式像素必須與 P2 舊實作一致（ORIGIN=(40,150)、STRIDE=118、INSET=11）。
func _test_ortho_matches_legacy(t: Object) -> void:
	var bv: Object = BoardViewScript.new()
	bv.mode = BoardViewScript.Mode.ORTHO
	var origin := Vector2(40.0, 150.0)
	var stride := 118.0
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
