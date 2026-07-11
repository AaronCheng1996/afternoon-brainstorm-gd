# P2-5 主選單（見 docs/rebuild/06 P2-5/P7-6、08 §3）。本機對戰 → BP → 對戰 → 終局 → 回選單。
# 戰役/爬塔為佔位（Phase 3–5）。設定頁存 user://settings.json（提示/動畫開關）。
#
# P7-6：UI 骨架（背景/標題/五選單鈕/訊息/版本/設定面板）宣告於 main_menu.tscn（編輯器可視可編輯，
# 美術可接手）；本腳本只用場景唯一名稱（`%NodeName`）綁定既有節點、連接信號，不再程序建構。
extends Node2D

const DRAFT_SCENE := "res://scenes/draft/draft.tscn"

var _hud: CanvasLayer
var _ui_built: bool = false          # 節點綁定完成旗標（沿用舊名，供測試斷言）
var _msg_label: Label
var _settings_panel: Panel
var _hint_btn: Button
var _anim_btn: Button

var _hints_on: bool = true
var _animations_on: bool = true


func _ready() -> void:
	_bind_nodes()


func _bind_nodes() -> void:
	if _ui_built:
		return
	_ui_built = true

	var s := SettingsStore.load_settings()
	_hints_on = bool(s.get("hints_on", true))
	_animations_on = bool(s.get("animations_on", true))

	_hud = %HUD
	_msg_label = %MsgLabel
	(%VersionLabel as Label).text = "平衡資料：" + Balance.data_version()

	# 選單鈕（戰役/爬塔於 .tscn 已 disabled）。
	(%LocalBattleBtn as Button).pressed.connect(_on_local_battle)
	(%CampaignBtn as Button).pressed.connect(_on_not_ready)
	(%EndlessBtn as Button).pressed.connect(_on_not_ready)
	(%SettingsBtn as Button).pressed.connect(_on_open_settings)
	(%QuitBtn as Button).pressed.connect(_on_quit)

	# 設定面板。
	_settings_panel = %SettingsPanel
	_hint_btn = %HintBtn
	_hint_btn.pressed.connect(_on_toggle_hint)
	_anim_btn = %AnimBtn
	_anim_btn.pressed.connect(_on_toggle_anim)
	(%BackBtn as Button).pressed.connect(_on_close_settings)

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
