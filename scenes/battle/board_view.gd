# P9-1 棋盤座標換算器（正交 / 等距雙模式）。見 docs/rebuild/06 P9-1、09 §7。
# 純數學、零 Node 依賴（RefCounted），可 headless 測試。對戰場景所有 cell↔pixel 換算
# （棋子定位、格線、高亮、攻擊範圍預覽、投射物/飄字瞄準、點擊反算）統一走這裡。
#
# 規則核心零改動：本類只影響「畫在哪裡」，不影響「發生什麼」。
# 等距公式（見 P9-1 步驟）：以格線交點座標 (gx,gy) 線性映射到螢幕——
#   sx = origin.x + (gx − gy)·HW
#   sy = origin.y + (gx + gy)·HH
# **P12-20（D21，2026-07-19）棋盤置中**：雙方手牌改為固定左右兩欄後，棋盤由畫面左側移到
# 水平置中（1024 基準寬）。兩模式的棋盤水平中心皆＝512，左右各留約 256px 給手牌欄。
# 原「正交沿用 P2 舊常數 ORIGIN=(40,150)」的像素對齊需求已由本次改版取代（僅影響畫在哪裡）。
class_name BoardView
extends RefCounted

enum Mode { ORTHO, ISO }

const BOARD := 4

# --- 幾何預設值（P14-2 前為唯一來源；現為「場景未指定時的預設」，見下方同名 var）---
const CELL := 96.0   # 佔位形狀邊長（＝PieceView.CELL_SIZE）；等距下棋子仍以此方形佔位置中，不做偽 3D。

# 正交參數：STRIDE 不變；ORIGIN.x 由 40 → 276 使棋盤置中（寬 4×118=472，(1024−472)/2=276）。
const ORTHO_ORIGIN := Vector2(276.0, 150.0)
const ORTHO_STRIDE := 118.0

# 等距參數：菱形格的半寬 / 半高（＝步驟公式中的 w/2、h/2）。
const ISO_HW := 60.0
const ISO_HH := 48.0
# 格線交點 (0,0) 的螢幕位置（菱形頂角）。ISO 下 origin.x 即菱形水平中心（(gx−gy) 對稱 ±4×HW=±240），
# 故置中＝512；棋盤水平範圍 [272, 752]。
const ISO_ORIGIN := Vector2(512.0, 160.0)

var mode: int = Mode.ISO   # P9-1 新方向：預設等距；ORTHO 供切換對照。

# **P14-2 美術可編輯化**：幾何參數由常數改為實例欄位，預設值＝上列常數（不指定時行為與改版前
# 逐位相同）。呼叫端（battle.gd）於 `_ready` 以 battle.tscn 宣告的 `BoardAnchorOrtho`/`BoardAnchorIso`
# 節點位置與 root `@export` 格距覆寫，美術即可在編輯器拖曳原點/調整格距，不必讀程式。
# 本類仍是純數學、零 Node 依賴（RefCounted），可 headless 測試。
var cell_size: float = CELL
var ortho_origin: Vector2 = ORTHO_ORIGIN
var ortho_stride: float = ORTHO_STRIDE
var iso_origin: Vector2 = ISO_ORIGIN
var iso_hw: float = ISO_HW
var iso_hh: float = ISO_HH


# 一次覆寫全部幾何參數（供場景注入）。傳入非正數的格距/格寬視為「不指定」，保留預設，
# 避免美術誤填 0 造成除以零（pixel_to_grid）或棋子退化成零尺寸。
func configure(a_cell_size: float, a_ortho_origin: Vector2, a_ortho_stride: float,
		a_iso_origin: Vector2, a_iso_hw: float, a_iso_hh: float) -> void:
	if a_cell_size > 0.0:
		cell_size = a_cell_size
	ortho_origin = a_ortho_origin
	if a_ortho_stride > 0.0:
		ortho_stride = a_ortho_stride
	iso_origin = a_iso_origin
	if a_iso_hw > 0.0:
		iso_hw = a_iso_hw
	if a_iso_hh > 0.0:
		iso_hh = a_iso_hh


# 格線交點（整數或半格皆可，gx,gy ∈ [0,BOARD]）→ 螢幕像素。所有換算的基元。
func corner(gx: float, gy: float) -> Vector2:
	if mode == Mode.ISO:
		return iso_origin + Vector2((gx - gy) * iso_hw, (gx + gy) * iso_hh)
	return ortho_origin + Vector2(gx, gy) * ortho_stride


# 格中心（棋子/瞄準用）。
func cell_center(cell: Vector2i) -> Vector2:
	return corner(cell.x + 0.5, cell.y + 0.5)


# 佔位棋子左上角原點（PieceView 以左上為原點、中心在 +CELL/2；置中對齊格中心）。
func cell_topleft(cell: Vector2i) -> Vector2:
	return cell_center(cell) - Vector2(cell_size, cell_size) * 0.5


# 一格的四頂點（順時針），供高亮/預覽繪製。正交＝方形、等距＝菱形。
func cell_polygon(cell: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		corner(cell.x, cell.y),
		corner(cell.x + 1, cell.y),
		corner(cell.x + 1, cell.y + 1),
		corner(cell.x, cell.y + 1),
	])


# P12-22：格多邊形「向格心內縮」版本——每頂點朝格心移動 inset 像素。
# 所有權外框（先手紅/後手藍）畫在這上面：相鄰格原本共邊，兩格皆有棋子時外框會互相覆蓋、
# 無法分辨；內縮一圈後各自完整可辨。正交（方形）與等距（菱形）皆適用。
# inset 夾在「頂點到格心距離的一半」以內，避免過大時多邊形翻面/退化。
func cell_polygon_inset(cell: Vector2i, inset: float) -> PackedVector2Array:
	var c: Vector2 = cell_center(cell)
	var out := PackedVector2Array()
	for v in cell_polygon(cell):
		var d: Vector2 = c - v
		var dist: float = d.length()
		if dist <= 0.001:
			out.append(v)
			continue
		out.append(v + d / dist * minf(inset, dist * 0.5))
	return out


# 螢幕像素 → 連續格座標（反矩陣）。整數部即所在格。
func pixel_to_grid(p: Vector2) -> Vector2:
	if mode == Mode.ISO:
		var d: Vector2 = p - iso_origin
		var u: float = d.x / iso_hw   # = gx − gy
		var v: float = d.y / iso_hh   # = gx + gy
		return Vector2((v + u) * 0.5, (v - u) * 0.5)
	return (p - ortho_origin) / ortho_stride


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
