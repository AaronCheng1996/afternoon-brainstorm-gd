# P2-4 選秀 BP 行動指令（翻譯自 screens/draft/draft_action.py DraftAction）。
# 表現層 → 選秀 dispatcher 的單向輸入。純資料（RefCounted，零 Node 依賴）。
class_name DraftAction
extends RefCounted

# add_card / remove_card / remove_last_card / advance_phase / confirm_start /
# toggle_timer / toggle_file_save / quit
var player: String
var action_type: String
var card_name: String = ""


func _init(who: String = "", type: String = "", card: String = "") -> void:
	player = who
	action_type = type
	card_name = card
