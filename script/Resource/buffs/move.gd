extends Buff
class_name Move

func apply_buff(target) -> void:
	icon_path = Global.buff_icon.move
	#可以移動
	if target.outfit_component:
		target.outfit_component.show_move()

func remove_buff(target) -> void:
	#恢復不可移動狀態
	if target.outfit_component:
		target.outfit_component.hide_move()
