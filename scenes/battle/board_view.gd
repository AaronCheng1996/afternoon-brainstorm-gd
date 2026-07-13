# P9-1 棋盤座標換算器（正交 / 等距雙模式）。見 docs/rebuild/06 P9-1、09 §7。
# 純數學、零 Node 依賴（RefCounted），可 headless 測試。對戰場景所有 cell↔pixel 換算
# （棋子定位、格線、高亮、攻擊範圍預覽、投射物/飄字瞄準、點擊反算）統一走這裡。
#
# 規則核心零改動：本類只影響「畫在哪裡」，不影響「發生什麼」。
# 等距公式（見 P9-1 步驟）：以格線交點座標 (gx,gy) 線性映射到螢幕——
#   sx = origin.x + (gx − gy)·HW
#   sy = origin.y + (gx + gy)·HH
# 正交模式沿用舊 battle 常數（ORIGIN=(40,150)、STRIDE=118），確保切回時像素完全一致。
class_name BoardView
extends RefCounted

enum Mode { ORTHO, ISO }

const BOARD := 4
const CELL := 96.0   # 佔位形狀邊長（＝PieceView.CELL_SIZE）；等距下棋子仍以此方形佔位置中，不做偽 3D。

# 正交參數（保持與 P2 舊實作完全一致）。
const ORTHO_ORIGIN := Vector2(40.0, 150.0)
const ORTHO_STRIDE := 118.0

# 等距參數：菱形格的半寬 / 半高（＝步驟公式中的 w/2、h/2）。
const ISO_HW := 60.0
const ISO_HH := 48.0
const ISO_ORIGIN := Vector2(276.0, 160.0)   # 格線交點 (0,0) 的螢幕位置（菱形頂角）。

var mode: int = Mode.ISO   # P9-1 新方向：預設等距；ORTHO 供切換對照。


# 格線交點（整數或半格皆可，gx,gy ∈ [0,BOARD]）→ 螢幕像素。所有換算的基元。
func corner(gx: float, gy: float) -> Vector2:
	if mode == Mode.ISO:
		return ISO_ORIGIN + Vector2((gx - gy) * ISO_HW, (gx + gy) * ISO_HH)
	return ORTHO_ORIGIN + Vector2(gx, gy) * ORTHO_STRIDE


# 格中心（棋子/瞄準用）。
func cell_center(cell: Vector2i) -> Vector2:
	return corner(cell.x + 0.5, cell.y + 0.5)


# 佔位棋子左上角原點（PieceView 以左上為原點、中心在 +CELL/2；置中對齊格中心）。
func cell_topleft(cell: Vector2i) -> Vector2:
	return cell_center(cell) - Vector2(CELL, CELL) * 0.5


# 一格的四頂點（順時針），供高亮/預覽繪製。正交＝方形、等距＝菱形。
func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		corner(cell.x, cell.y),
		corner(cell.x + 1, cell.y),
		corner(cell.x + 1, cell.y + 1),
		corner(cell.x, cell.y + 1),
	])


# 螢幕像素 → 連續格座標（反矩陣）。整數部即所在格。
func pixel_to_grid(p: Vector2) -> Vector2:
	if mode == Mode.ISO:
		var d: Vector2 = p - ISO_ORIGIN
		var u: float = d.x / ISO_HW   # = gx − gy
		var v: float = d.y / ISO_HH   # = gx + gy
		return Vector2((v + u) * 0.5, (v - u) * 0.5)
	return (p - ORTHO_ORIGIN) / ORTHO_STRIDE


# 螢幕像素 → 格座標；界外回傳 (-1,-1)。
func cell_from_pixel(p: Vector2) -> Vector2i:
	var g: Vector2 = pixel_to_grid(p)
	var cx: int = int(floor(g.x))
	var cy: int = int(floor(g.y))
	if cx >= 0 and cx < BOARD and cy >= 0 and cy < BOARD:
		return Vector2i(cx, cy)
	return Vector2i(-1, -1)


# 螢幕深度序（等距：越靠畫面下方＝越前）。供棋子 z_index 決定遮擋。
func depth(cell: Vector2i) -> int:
	return cell.x + cell.y
