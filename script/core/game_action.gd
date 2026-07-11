# P1-1 行動指令（表現層 → core 的單向輸入，見 docs/rebuild/04 §4、01 §4）。
# 實際 dispatch 分派在 P1-2 實作；此處先定義資料結構。
class_name GameAction
extends RefCounted

var action_type: String   # attack / play_card / move_to / heal / spawn_cube / toggle_upgrade / end_turn / quit
var player: String        # player1 / player2
var board_x: int = -1
var board_y: int = -1
var hand_index: int = -1


func _init(type: String = "", who: String = "") -> void:
	action_type = type
	player = who
