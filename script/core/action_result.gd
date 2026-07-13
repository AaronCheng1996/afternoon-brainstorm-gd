# P1-1 行動結果（翻譯自 core/game_action.py ActionResult）。
class_name ActionResult
extends RefCounted

var success: bool
var message: String
var quit: bool
var end_turn: bool


func _init(ok: bool = true, msg: String = "", is_quit: bool = false, is_end_turn: bool = false) -> void:
	success = ok
	message = msg
	quit = is_quit
	end_turn = is_end_turn
