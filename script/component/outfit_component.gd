extends Node2D
class_name OutfitComponent

signal card_selected(card: Card)
signal piece_attack(piece: Piece)
signal piece_move_pressed(piece: Piece)
signal mouse_in_attack(piece: Piece)
signal mouse_out_attack(piece: Piece)
signal mouse_in_icon(card: Card)
signal mouse_out_icon(card: Card)
signal spell_cast(spell: Spell)

@onready var txt_value: RichTextLabel = $txt_value
@onready var control_panel: Control = $ControlPanel
@onready var move_button: Button = $ControlPanel/btn_move
@onready var attack_button: Button = $ControlPanel/btn_attack
@onready var cast_button: Button = $ControlPanel/btn_cast
@onready var player_effect: Sprite2D = $click_box/player_effect
@onready var icon: Sprite2D = $click_box/Icon
@onready var hit_flash_animation_player: AnimationPlayer = $HitFlashAnimationPlayer

@export var icon_texture : CompressedTexture2D
@export var frame : int = 0

var txt_size = 14

func _ready() -> void:
	var card: Card = get_parent()
	if card.card_type == Global.CardType.PIECE:
		attack_button.show()
	elif card.card_type == Global.CardType.SPELL:
		if card.target_type == Global.TargetType.NONE:
			cast_button.show()
	#非選定狀態時隱藏
	if control_panel:
		control_panel.hide()
	#圖示
	if icon_texture:
		icon.texture = icon_texture
		icon.frame = frame
	#按鈕
	hide_move()

#套用玩家特效
func set_player_effect(player: int) -> void:
	if player == 0:
		Global.change_color(player_effect, Color.WHITE, Color.RED)
	if player == 1:
		Global.change_color(player_effect, Color.WHITE, Color.BLUE)

#開啟選取特效
func show_control_panel() -> void:
	control_panel.show()
#關閉選取特效
func hide_control_panel() -> void:
	control_panel.hide()
#無效攻擊
func enable_attack() -> void:
	attack_button.disabled = false
func disable_attack() -> void:
	attack_button.disabled = true
#不會攻擊的單位
func hide_attack() -> void:
	attack_button.hide()
#顯示移動
func show_move() -> void:
	move_button.show()
func hide_move() -> void:
	move_button.hide()
#無效攻擊
func enable_move() -> void:
	move_button.disabled = false
func disable_move() -> void:
	move_button.disabled = true

#圖示互動
func _on_icon_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse_left"):
		emit_signal("card_selected", get_parent())

func _on_icon_mouse_entered() -> void:
	emit_signal("mouse_in_icon", get_parent())

func _on_icon_mouse_exited() -> void:
	emit_signal("mouse_out_icon", get_parent())

#攻擊鍵互動
func _on_btn_attack_pressed() -> void:
	emit_signal("piece_attack", get_parent())

func _on_btn_attack_mouse_entered() -> void:
	emit_signal("mouse_in_attack", get_parent())

func _on_btn_attack_mouse_exited() -> void:
	emit_signal("mouse_out_attack", get_parent())

#移動鍵互動
func _on_btn_move_pressed() -> void:
	emit_signal("piece_move_pressed", get_parent())

#施放鍵互動
func _on_btn_cast_pressed() -> void:
	emit_signal("spell_cast", get_parent())

#擊中特效
func play_hit_flash() -> void:
	hit_flash_animation_player.play("hit_flash")

func refresh_value(atk: int, default: int) -> void:
	if txt_value == null:
		return
	var text = str(atk)
	var colored = Global.set_font_color(text, Global.get_font_color(atk, default))
	txt_value.text = Global.set_font_center(Global.set_font_size(colored, txt_size))
