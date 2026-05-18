extends Card
class_name Piece

signal piece_die(piece: Piece)

var card_type : Global.CardType = Global.CardType.PIECE
@export var health_component : HealthComponent
@export var attack_component : AttackComponent
@export var outfit_component : OutfitComponent
@export var score_component : ScoreComponent
@export var buff_component : BuffComponent
var is_dead: bool = false
var auto_attack_loop_count: int = 0
var auto_attack_loop_count_limit: int = 15

func _ready() -> void:
	if health_component:
		health_component.death.connect(die)
	refresh()

#回歸原廠設定
func renew() -> void:
	if buff_component:
		buff_component.clear_buffs()
	if health_component:
		health_component.max_health = health_component.DEFAULT_MAX_HEALTH
		health_component.health = health_component.max_health
		health_component.shield = health_component.DEFAULT_SHIELD
		health_component.always_show = false
		health_component.health_display.hide()
	if attack_component:
		attack_component.atk = attack_component.DEFAULT_ATK
	if score_component:
		score_component.score = score_component.DEFAULT_SCORE
	if outfit_component:
		outfit_component.txt_value.hide()
		outfit_component.player_effect.hide()
	is_on_board = false
	is_dead = false
	refresh()

#region 觸發時機
#棋子放置時
func on_piece_set() -> void:
	if buff_component:
		var stun_debuff = Global.get_stun_debuff()
		stun_debuff.show_name = Global.data.buff.sleep.name
		stun_debuff.description = Global.data.buff.sleep.description
		stun_debuff.icon_path = Global.buff_icon.sleep
		add_buff(stun_debuff)
	refresh()

#回合開始時
func on_turn_start(current_turn: int) -> void:
	refresh()

#回合結束時
func on_turn_end(current_turn: int) -> void:
	if not card_owner == null:
		if current_turn != card_owner.id:
			return
	tick()
	refresh()

#移動後
func after_move() -> void:
	Global.piece_moved(self)
	refresh()

#計算分數
func get_score(current_turn: int) -> int:
	if card_owner == null:
		return 0
	if current_turn != card_owner.id:
		return 0
	if not score_component:
		return 0
	if card_owner.id == 0:
		return -score_component.score
	else:
		return score_component.score
#endregion

#region 動作
#選取特效
func show_select_effect() -> void:
	#預留：選取動畫
	if outfit_component and is_on_board:
		outfit_component.show_control_panel()
func hide_select_effect() -> void:
	#預留：選取動畫
	if outfit_component:
		outfit_component.hide_control_panel()
#攻擊
func attack() -> void:
	if attack_component:
		attack_component.attack(Global.get_board_pieces().filter(filter_opponent_piece))
	refresh()
#自動攻擊
func auto_attack() -> void:
	auto_attack_loop_count += 1
	if Global.DEBUG:
		print("[DEBUG] auto_attack_loop_count: ", auto_attack_loop_count)
	if not attack_component:
		return
	if auto_attack_loop_count >= auto_attack_loop_count_limit: #防止無限迴圈 上限15層
		return
	if not buff_component:
		attack_component.attack(Global.get_board_pieces().filter(filter_opponent_piece))
		auto_attack_loop_count = 0
		return
	if buff_component.has_buff(Global.data.buff.sleep.name): #若有睡眠狀態，移除但不攻擊
		remove_buff(buff_component.get_buff(Global.data.buff.sleep.name))
		return
	if buff_component.has_buff(Global.data.buff.stun.name): #若有暈眩狀態，移除但不攻擊
		remove_buff(buff_component.get_buff(Global.data.buff.stun.name))
		return
	if Global.DEBUG:
		print("[DEBUG] 觸發自動攻擊: ", show_name)
	attack_component.attack(Global.get_board_pieces().filter(filter_opponent_piece))
	auto_attack_loop_count = 0
	refresh()
#取得攻擊範圍
func get_target_location() -> Array:
	if attack_component:
		return attack_component.get_target_location(Global.get_board_pieces().filter(filter_opponent_piece))
	return []
#取得移動範圍
func get_move_location() -> Array:
	var result = []
	for key: Vector2i in Global.board_dic.keys():
		if Global.board_dic[key] is not int: #該格子有其他棋子
			continue
		if abs(key.x - location.x) <= 1 and abs(key.y - location.y) <= 1: #九宮格範圍
			result.append(key)
	return result
#補血
func heal(heal: int, applyer) -> int:
	if health_component:
		var is_over_healed = health_component.heal(heal)
		refresh()
		return is_over_healed
	return 0
#獲得護盾
func shielded(value: int, applyer) -> void:
	if health_component:
		health_component.shielded(value)
		refresh()
#被鎖定
func targeted() -> bool:
	return true
#承受傷害
func take_damaged(damage: int, applyer) -> bool:
	if damage <= 0:
		return false
	if health_component:
		if outfit_component:
			outfit_component.play_hit_flash()
		var is_killed = health_component.take_damaged(damage)
		refresh()
		return is_killed
	return false
#死亡
func die(true_death: bool = false) -> void:
	if not buff_component.has_buff(Global.data.buff.death_door.name) or true_death:
		renew()
		card_owner.grave.append(self)
		Global.board_dic[location] = 0
		emit_signal("piece_die", self)
#更新顯示數值
func refresh() -> void:
	if not outfit_component:
		return
	if attack_component:
		outfit_component.refresh_value(attack_component.atk, attack_component.DEFAULT_ATK)
#endregion

#region buff
#賦予buff
func add_buff(buff: Buff) -> void:
	if buff_component:
		buff_component.add_buff(buff)
		refresh()
#移除buff
func remove_buff(buff: Buff) -> void:
	if buff_component:
		buff_component.remove_buff(buff)
		refresh()
#經過一回合
func tick() -> void:
	if buff_component:
		buff_component.tick()
		refresh()
#清除buff
func clear_buffs() -> void:
	if buff_component:
		buff_component.clear_buffs()
		refresh()

#endregion

#region 工具
#取得最近友方
func get_nearest_ally() -> Piece:
	var allys = Global.get_board_pieces().filter(filter_ally_piece).filter(func(element: Piece): return !element.is_dead)
	allys = attack_component.find_nearest_target(location, allys)
	if allys.size() > 0:
		var random_index = Global.rng.randi_range(0, allys.size() - 1)
		return allys[random_index]
	return null
#取得最近敵方
func get_nearest_enemy() -> Piece:
	var enemys = Global.get_board_pieces().filter(filter_opponent_piece).filter(func(element: Piece): return !element.is_dead)
	enemys = attack_component.find_nearest_target(location, enemys)
	if enemys.size() > 0:
		var random_index = Global.rng.randi_range(0, enemys.size() - 1)
		return enemys[random_index]
	return null
#取得最遠敵方
func get_farest_enemy() -> Piece:
	var enemys = Global.get_board_pieces().filter(filter_opponent_piece).filter(func(element: Piece): return !element.is_dead)
	enemys = attack_component.find_farest_target(location, enemys)
	if enemys.size() > 0:
		var random_index = Global.rng.randi_range(0, enemys.size() - 1)
		return enemys[random_index]
	return null
#取得隨機敵方
func get_random_enemy() -> Piece:
	var enemys = Global.get_board_pieces().filter(filter_opponent_piece).filter(func(element: Piece): return !element.is_dead)
	if enemys.size() > 0:
		var random_index = Global.rng.randi_range(0, enemys.size() - 1)
		return enemys[random_index]
	return null
#endregion

#region 過濾
#過濾出除自己外的友方
func filter_ally_piece(piece: Piece) -> bool:
	if piece.card_owner == null:
		return false
	return piece.card_owner.id == card_owner.id and piece.location != location
#過濾出敵方
func filter_opponent_piece(piece: Piece) -> bool:
	if piece.card_owner == null:
		return true
	return piece.card_owner.id != card_owner.id
func filter_opponent_piece_only(piece: Piece) -> bool:
	if piece.card_owner == null:
		return false
	return piece.card_owner.id != card_owner.id
#endregion
