# P2-4 選秀 BP 狀態（翻譯自 core/draft_state.py DraftState，本機模式）。
# 純資料（RefCounted，零 Node 依賴）。LAN 遮蔽/暫停/存檔序列化（D8）本輪不做。
# 三階段：p1_first6（p1 選滿 ≥6）→ p2_pick12（p2 選滿 12）→ p1_last6（p1 補滿 12）→ done。
class_name DraftStateV2
extends RefCounted

var player1_deck: Array[String] = []
var player2_deck: Array[String] = []
var phase: String = "p1_first6"

var timer_mode: String = "timer"        # timer / countdown
var file_auto_delete: bool = false


# 取某玩家牌組（回傳實際參考，dispatcher 直接增刪）。
func get_deck(owner: String) -> Array:
	return player1_deck if owner == "player1" else player2_deck


# 當前可編輯的玩家（依階段）。
func current_editor() -> String:
	match phase:
		"p1_first6", "p1_last6":
			return "player1"
		"p2_pick12":
			return "player2"
		_:
			return ""


# 是否可進入下一階段（達該階段最低張數）。
func can_advance() -> bool:
	match phase:
		"p1_first6":
			return player1_deck.size() >= 6
		"p2_pick12":
			return player2_deck.size() >= 12
		"p1_last6":
			return player1_deck.size() >= 12
		"done":
			return true
	return false


func advance_phase() -> void:
	match phase:
		"p1_first6":
			phase = "p2_pick12"
		"p2_pick12":
			phase = "p1_last6"
		"p1_last6":
			phase = "done"
