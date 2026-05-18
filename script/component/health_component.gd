extends Node2D
class_name HealthComponent

signal on_over_heal(value: int)
signal damage_taken(value: int)
signal death()

@onready var health_display: Control = $HealthDisplay
@onready var hurtbar: ProgressBar = $HealthDisplay/hurtbar
@onready var healthbar: ProgressBar = $HealthDisplay/healthbar
@onready var timer: Timer = $HealthDisplay/Timer
@onready var lbl_health: Label = $HealthDisplay/lbl_health
@onready var shield_effect: ColorRect = $HealthDisplay/shield_effect
@onready var shield_icon: TextureRect = $HealthDisplay/shield_icon
@onready var lbl_shield: Label = $HealthDisplay/shield_icon/lbl_shield

var always_show : bool = false

#生命
@export var DEFAULT_MAX_HEALTH : int = 10
var max_health : int
var health : int
#護盾
@export var DEFAULT_SHIELD : int = 0
var shield : int
#血條動畫時間
var hurtbar_animation_time : float = 0.3
var healthbar_wait_time : float = 0.5

func _ready() -> void:
	if not always_show:
		health_display.hide()
	max_health = DEFAULT_MAX_HEALTH
	health = max_health
	shield = DEFAULT_SHIELD
	hurtbar.max_value = max_health
	hurtbar.value = health
	healthbar.max_value = max_health
	healthbar.value = health
	lbl_health.text = "{0} / {1}".format([str(health), str(max_health)])

func _process(delta: float) -> void:
	#血條動畫
	if hurtbar.max_value != max_health:
		hurtbar.max_value = max_health
	if healthbar.max_value != max_health:
		healthbar.max_value = max_health
	if healthbar.value != health:
		if health <= 0:
			healthbar.value = 0
		else:
			healthbar.value = health
		lbl_health.text = "{0} / {1}".format([str(health), str(max_health)])
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(hurtbar, "value", healthbar.value, hurtbar_animation_time)
	#顯示護盾
	if shield > 0:
		show_shield()
	else:
		hide_shield()

func show_shield() -> void:
	shield_effect.show()
	shield_icon.show()
	lbl_shield.show()
	lbl_shield.text = str(shield)

func hide_shield() -> void:
	shield_effect.hide()
	shield_icon.hide()
	lbl_shield.hide()

#補血
func heal(heal: int) -> int:
	var over_heal = health + heal - max_health
	if over_heal > 0:
		health = max_health
		emit_signal("on_over_heal", over_heal)
		shielded(over_heal / 2)
		return over_heal
	else:
		health += heal
		return 0

#獲得護盾
func shielded(value: int) -> void:
	shield += value

#承受傷害
func take_damaged(damage: int) -> bool:
	health_display.show()
	timer.wait_time = healthbar_wait_time
	timer.start()
	#盾先承受，生命再承受
	if shield >= damage:
		shield -= damage
	else:
		health -= (damage - shield)
		shield = 0
	#若生命降為0，則死亡
	if health <= 0:
		get_parent().is_dead = true
		return true
	return false

#血條顯示時間長
func _on_timer_timeout() -> void:
	if not always_show:
		health_display.hide()
	if health <= 0:
		emit_signal("death")
