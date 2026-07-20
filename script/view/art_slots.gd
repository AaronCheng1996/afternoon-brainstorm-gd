# P14-5 素材插槽與自動載入慣例。見 docs/rebuild/06 P14-5、08 §5.3/§5.5、11_美術指南.md（P14-7）。
#
# 目的：美術**丟檔案即生效、零程式改動**。本類集中「素材路徑慣例」與「查檔→有圖才用」的取用邏輯，
# 讓 piece_view / battle / 各場景背景走同一條路，路徑只定義在這裡一處。
#
# 慣例（P14-1 §5.5 裁定：沿用既有資產根 `res://img/`，不另開 `art/`）：
#   棋子貼圖　`res://img/piece/card/<card_id>.png`
#   棋盤底圖　`res://img/board/skin_ortho.png`（俯視）／`skin_iso.png`（45 度）
#   場景背景　`res://img/UI/bg/<scene_name>.png`（battle/draft/encyclopedia/end_game/
#   　　　　　main_menu/online_lobby）
#
# 查檔一律 `ResourceLoader.exists()`（同 encyclopedia.gd 的 ATTACK_ICON 慣例）——
# **檔案不存在時一律回 null，呼叫端退回現行的幾何佔位／純色背景，行為與放圖前完全相同**。
# 純靜態、零狀態；不持有資源。
class_name ArtSlots
extends RefCounted

## 棋子貼圖目錄（檔名＝card_id，如 `ADCW.png`）。
const PIECE_DIR := "res://img/piece/card/"
## 棋盤底圖：俯視（正交）視角。
const BOARD_SKIN_ORTHO := "res://img/board/skin_ortho.png"
## 棋盤底圖：45 度（等距）視角。
const BOARD_SKIN_ISO := "res://img/board/skin_iso.png"
## 場景背景目錄（檔名＝場景名，如 `battle.png`）。
const BG_DIR := "res://img/UI/bg/"


# 查檔取貼圖；不存在（或不是貼圖）時回 null。全案唯一的素材查檔入口。
static func texture_at(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# 棋子貼圖路徑。dir 留空時用預設慣例目錄（呼叫端可 @export 覆蓋，便於測試與美術試放）。
static func piece_texture_path(card_id: String, dir: String = PIECE_DIR) -> String:
	if card_id.is_empty():
		return ""
	var d := dir if not dir.is_empty() else PIECE_DIR
	if not d.ends_with("/"):
		d += "/"
	return d + card_id + ".png"


# 棋子貼圖（無圖回 null → 呼叫端用幾何佔位形）。
static func piece_texture(card_id: String, dir: String = PIECE_DIR) -> Texture2D:
	return texture_at(piece_texture_path(card_id, dir))


# 場景背景路徑。
static func background_path(scene_name: String, dir: String = BG_DIR) -> String:
	if scene_name.is_empty():
		return ""
	var d := dir if not dir.is_empty() else BG_DIR
	if not d.ends_with("/"):
		d += "/"
	return d + scene_name + ".png"


# 把場景背景圖套進 .tscn 宣告的 `BackgroundImage`(TextureRect) 插槽。
# 有圖→填貼圖並顯示（蓋住底下的 Background 純色）；無圖→維持隱藏（＝現況純色背景）。
# 回傳是否真的套上了圖（測試用）。slot 為 null（舊場景未加插槽）時安全略過。
static func apply_background(slot: TextureRect, scene_name: String, dir: String = BG_DIR) -> bool:
	if slot == null or not is_instance_valid(slot):
		return false
	var tex := texture_at(background_path(scene_name, dir))
	slot.texture = tex
	slot.visible = tex != null
	return tex != null
