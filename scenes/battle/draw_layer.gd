# 以 _draw 回呼繪製的 Node2D（queue_redraw() → _draw() → 呼叫 cb）。
# 用於對戰場景的高亮/預覽層：節點宣告於 battle.tscn，battle.gd 於綁定時設定 cb。
class_name BattleDrawLayer
extends Node2D

var cb: Callable = Callable()


func _draw() -> void:
	if cb.is_valid():
		cb.call()
