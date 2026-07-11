# P2-5 主選單（見 docs/rebuild/06 P2-5）。本機對戰 → BP → 對戰 → 終局 → 回選單。
# 戰役/爬塔為佔位（Phase 3–5）。設定頁存 user://settings.json（提示/動畫開關）。
extends Node2D

const DRAFT_SCENE := "res://scenes/draft/draft.tscn"

var _hud: CanvasLayer
var _ui_built: bool = false
var _msg_label: Label
var _settings_panel: Panel
var _hint_btn: Button
var _anim_btn: Button

var _hints_on: bool = true
var _animations_on: bool = true


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	var s := SettingsStore.load_settings()
	_hints_on = bool(s.get("hints_on", true))
	_animations_on = bool(s.get("animations_on", true))

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13)
	bg.size = Vector2(1024, 768)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_hud = CanvasLayer.new()
	add_child(_hud)

	var title := _mk_label(Vector2(0, 120), 44, 1024)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "午 後 激 盪"
	_hud.add_child(title)

	var subtitle := _mk_label(Vector2(0, 180), 18, 1024)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	subtitle.text = "Afternoon Brainstorming — Godot 重構版"
	_hud.add_child(subtitle)

	var buttons := [
		["本機對戰", _on_local_battle, false],
		["戰役模式（尚未開放）", _on_not_ready, true],
		["爬塔模式（尚未開放）", _on_not_ready, true],
		["設定", _on_open_settings, false],
		["離開", _on_quit, false],
	]
	var by := 260.0
	for entry in buttons:
		var b := _mk_button(entry[0], Vector2(392, by), Vector2(240, 52))
		b.disabled = entry[2]
		b.pressed.connect(entry[1])
		_hud.add_child(b)
		by += 64.0

	_msg_label = _mk_label(Vector2(0, 600), 15, 1024)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	_hud.add_child(_msg_label)

	var version := _mk_label(Vector2(16, 738), 13, 700)
	version.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	version.text = "平衡資料：" + Balance.data_version()
	_hud.add_child(version)

	_build_settings_panel()


func _build_settings_panel() -> void:
	_settings_panel = Panel.new()
	_settings_panel.position = Vector2(312, 240)
	_settings_panel.size = Vector2(400, 260)
	_settings_panel.visible = false
	_hud.add_child(_settings_panel)

	var t := _mk_label(Vector2(24, 20), 22, 360)
	t.text = "設定"
	_settings_panel.add_child(t)

	_hint_btn = _mk_button("", Vector2(40, 70), Vector2(320, 44))
	_hint_btn.pressed.connect(_on_toggle_hint)
	_settings_panel.add_child(_hint_btn)

	_anim_btn = _mk_button("", Vector2(40, 124), Vector2(320, 44))
	_anim_btn.pressed.connect(_on_toggle_anim)
	_settings_panel.add_child(_anim_btn)

	var back := _mk_button("返回", Vector2(40, 190), Vector2(320, 44))
	back.pressed.connect(_on_close_settings)
	_settings_panel.add_child(back)

	_refresh_settings_labels()


func _refresh_settings_labels() -> void:
	_hint_btn.text = "戰鬥提示（card_hints）：%s" % ("開" if _hints_on else "關")
	_anim_btn.text = "戰鬥動畫：%s" % ("開" if _animations_on else "關（瞬時）")


# ---------------- 回呼 ----------------

func _on_local_battle() -> void:
	_change_scene(DRAFT_SCENE)


func _on_not_ready() -> void:
	_msg_label.text = "該模式將於後續階段開放（戰役 Phase 3–4／爬塔 Phase 5）。"


func _on_open_settings() -> void:
	_settings_panel.visible = true


func _on_close_settings() -> void:
	_settings_panel.visible = false


func _on_toggle_hint() -> void:
	_hints_on = not _hints_on
	_persist()
	_refresh_settings_labels()


func _on_toggle_anim() -> void:
	_animations_on = not _animations_on
	_persist()
	_refresh_settings_labels()


func _on_quit() -> void:
	var tree := get_tree()
	if tree != null:
		tree.quit()


func _persist() -> void:
	SettingsStore.save_settings(_hints_on, _animations_on)


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(path)


# ---------------- 小工具 ----------------

func _mk_label(pos: Vector2, font_size: int, width: float) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.93, 0.94, 0.96))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	return l


func _mk_button(text: String, pos: Vector2, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_size_override("font_size", 16)
	return b
