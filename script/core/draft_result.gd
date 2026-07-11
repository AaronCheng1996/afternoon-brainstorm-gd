# P2-4 選秀 BP 行動結果（翻譯自 core/draft_dispatcher.py DraftResult）。
class_name DraftResultV2
extends RefCounted

var success: bool
var message: String
var phase_advanced: bool = false
var ready_to_start: bool = false


func _init(a_success: bool, a_message: String = "") -> void:
	success = a_success
	message = a_message
