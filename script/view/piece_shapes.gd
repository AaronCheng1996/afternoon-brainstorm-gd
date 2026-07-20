# P2-1 佔位形狀資料：職業／特殊卡的正規化頂點表（座標 0..1，y 向下）。
# 來源：Python cards/base.py _compute_shape_points（見 02_卡牌能力總表.md 附錄）。
# 純資料 + 純靜態函式，零 Node 依賴，供 PieceView 與 headless 測試共用。
# 之後換美術：PieceView 隱藏 PlaceholderShape、顯示 SpriteSlot 即可，不動本表。
class_name PieceShapes
extends RefCounted

# 職業碼 → 正規化頂點（多邊形）。AP 為圓形，另以 _circle() 產生。
const JOB_POINTS := {
	"ADC": [Vector2(0.5, 0.3), Vector2(0.25, 0.7), Vector2(0.75, 0.7)],
	"HF": [Vector2(0.4, 0.4), Vector2(0.6, 0.4), Vector2(0.75, 0.65), Vector2(0.25, 0.65)],
	"LF": [
		Vector2(0.5, 0.3), Vector2(0.36, 0.42), Vector2(0.4775, 0.55), Vector2(0.36, 0.68),
		Vector2(0.5, 0.8), Vector2(0.64, 0.68), Vector2(0.5225, 0.55), Vector2(0.64, 0.42)],
	"ASS": [Vector2(0.5, 0.4), Vector2(0.2, 0.65), Vector2(0.5, 0.5), Vector2(0.8, 0.65)],
	"APT": [
		Vector2(0.4, 0.3), Vector2(0.25, 0.5), Vector2(0.4, 0.7),
		Vector2(0.6, 0.7), Vector2(0.75, 0.5), Vector2(0.6, 0.3)],
	"SP": [
		Vector2(0.375, 0.3), Vector2(0.25, 0.45), Vector2(0.5, 0.75),
		Vector2(0.75, 0.45), Vector2(0.625, 0.3)],
	"TANK": [Vector2(0.25, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75), Vector2(0.75, 0.25)],
}

# 特殊卡形狀。
const SPECIAL_POINTS := {
	"CUBE": [Vector2(0.45, 0.45), Vector2(0.45, 0.55), Vector2(0.55, 0.55), Vector2(0.55, 0.45)],
	"LUCKYBLOCK": [Vector2(0.4, 0.4), Vector2(0.4, 0.6), Vector2(0.6, 0.6), Vector2(0.6, 0.4)],
}

const CENTER := Vector2(0.5, 0.5)
const AP_RADIUS := 0.22
const AP_SEGMENTS := 24


# 取某形狀鍵（職業碼 "ADC"/"AP"… 或特殊卡 "CUBE"/"LUCKYBLOCK"）的正規化頂點。
# AP → 圓形近似（AP_SEGMENTS 邊）；未知鍵回傳空陣列。
static func normalized(shape_key: String) -> PackedVector2Array:
	if shape_key == "AP":
		return _circle(CENTER, AP_RADIUS, AP_SEGMENTS)
	if JOB_POINTS.has(shape_key):
		return _to_packed(JOB_POINTS[shape_key])
	if SPECIAL_POINTS.has(shape_key):
		return _to_packed(SPECIAL_POINTS[shape_key])
	return PackedVector2Array()


# 取縮放到像素尺寸的頂點。size＝格寬（像素）；extra_scale＝以中心為原點的額外放大（SHADOW=1.1）。
static func scaled(shape_key: String, size: float, extra_scale: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in normalized(shape_key):
		out.append((CENTER + (p - CENTER) * extra_scale) * size)
	return out


static func _to_packed(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(p)
	return out


static func _circle(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out
