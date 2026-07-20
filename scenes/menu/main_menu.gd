# P2-5 主選單（見 docs/rebuild/06 P2-5/P7-6、08 §3）。本機對戰 → BP → 對戰 → 終局 → 回選單。
# 戰役/爬塔為佔位（Phase 3–5）。設定頁存 user://settings.json（提示/動畫開關）。
#
# P7-6：UI 骨架（背景/標題/五選單鈕/訊息/版本/設定面板）宣告於 main_menu.tscn（編輯器可視可編輯，
# 美術可接手）；本腳本只用場景唯一名稱（`%NodeName`）綁定既有節點、連接信號，不再程序建構。
extends Node2D

const DRAFT_SCENE := "res://scenes/draft/draft.tscn"
const ENCYCLOPEDIA_SCENE := "res://scenes/encyclopedia/encyclopedia.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const ONLINE_SCENE := "res://scenes/online/online_lobby.tscn"   # P12-7 線上對戰大廳

# P14-3：回放清單列的樣式抽成 item 模板場景（美術可單開檔案調樣式）。
const ReplayRowScene := preload("res://scenes/menu/replay_row_button.tscn")

# P10-5 單人對戰（vs CPU）。v1：雙方用固定預設牌組（含 B/G/C/DKG 以顯示四種資源列），
# AI 關卡色只決定「策略/難度」不決定牌組；玩家執先手 P1，CPU 執後手 P2。
# 每個 AI 對手＝AIController 的一個關卡（見 AIController.KNOWN_STAGES）＋顯示標籤。
const AI_OPPONENTS := [
	{"stage": "white", "node": "WhiteAIBtn", "label": "白 · 新手（基礎評分）"},
	{"stage": "red", "node": "RedAIBtn", "label": "紅 · 攻擊滾雪球"},
	{"stage": "blue", "node": "BlueAIBtn", "label": "藍 · 藍球經濟"},
	{"stage": "green", "node": "GreenAIBtn", "label": "綠 · 運氣（起手好運）"},
	{"stage": "orange", "node": "OrangeAIBtn", "label": "橙 · 機動壓制"},
	{"stage": "boss", "node": "BossAIBtn", "label": "Boss · 最強（起手優勢）"},
]
const SP_DECK_P1 := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]
const SP_DECK_P2 := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]

var _hud: CanvasLayer
var _ui_built: bool = false          # 節點綁定完成旗標（沿用舊名，供測試斷言）
var _msg_label: Label
var _settings_panel: Panel
var _ai_panel: Panel
var _replay_panel: Panel             # P11-2 回放紀錄瀏覽
var _replay_list: VBoxContainer
var _hint_btn: Button
var _anim_btn: Button

var _hints_on: bool = true
var _animations_on: bool = true

# P11-1 計時設定。單一鈕循環：關 → 各秒數 → 關（0＝關）。
const TURN_SECONDS_CYCLE := [0, 30, 45, 60, 90]
const DRAFT_SECONDS_CYCLE := [0, 30, 45, 60]
var _turn_timer_on: bool = false
var _turn_seconds: int = 60
var _draft_timer_on: bool = false
var _draft_seconds: int = 45
var _turn_timer_btn: Button
var _draft_timer_btn: Button


func _ready() -> void:
	_bind_nodes()


func _bind_nodes() -> void:
	if _ui_built:
		return
	_ui_built = true

	# P14-5：有 img/UI/bg/main_menu.png 才蓋圖，否則維持 .tscn 的純色 Background（現況）。
	ArtSlots.apply_background(get_node_or_null("%BackgroundImage") as TextureRect, "main_menu")

	var s := SettingsStore.load_settings()
	_hints_on = bool(s.get("hints_on", true))
	_animations_on = bool(s.get("animations_on", true))
	_turn_timer_on = bool(s.get("turn_timer_on", false))
	_turn_seconds = int(s.get("turn_seconds", 60))
	_draft_timer_on = bool(s.get("draft_timer_on", false))
	_draft_seconds = int(s.get("draft_seconds", 45))

	_hud = %HUD
	_msg_label = %MsgLabel
	(%VersionLabel as Label).text = "平衡資料：" + Balance.data_version()

	# 選單鈕（爬塔於 .tscn 已 disabled）。
	(%LocalBattleBtn as Button).pressed.connect(_on_local_battle)
	(%SinglePlayerBtn as Button).pressed.connect(_on_single_player)
	(%OnlineBtn as Button).pressed.connect(_on_online)
	(%EncyclopediaBtn as Button).pressed.connect(_on_encyclopedia)
	(%ReplayBtn as Button).pressed.connect(_on_open_replays)
	(%EndlessBtn as Button).pressed.connect(_on_not_ready)
	(%SettingsBtn as Button).pressed.connect(_on_open_settings)
	(%QuitBtn as Button).pressed.connect(_on_quit)

	# 回放紀錄瀏覽面板。
	_replay_panel = %ReplayPanel
	_replay_list = %ReplayList
	(%ReplayBackBtn as Button).pressed.connect(_on_close_replays)

	# 單人對戰：CPU 對手選擇面板（每鈕＝一個 AI 關卡）。
	_ai_panel = %AIPanel
	for opp: Dictionary in AI_OPPONENTS:
		var b := get_node("%" + String(opp["node"])) as Button
		b.text = String(opp["label"])
		b.pressed.connect(_on_pick_ai.bind(String(opp["stage"])))
	(%AIBackBtn as Button).pressed.connect(_on_close_ai)

	# 設定面板。
	_settings_panel = %SettingsPanel
	_hint_btn = %HintBtn
	_hint_btn.pressed.connect(_on_toggle_hint)
	_anim_btn = %AnimBtn
	_anim_btn.pressed.connect(_on_toggle_anim)
	_turn_timer_btn = %TurnTimerBtn
	_turn_timer_btn.pressed.connect(_on_cycle_turn_timer)
	_draft_timer_btn = %DraftTimerBtn
	_draft_timer_btn.pressed.connect(_on_cycle_draft_timer)
	(%BackBtn as Button).pressed.connect(_on_close_settings)

	_refresh_settings_labels()


func _refresh_settings_labels() -> void:
	_hint_btn.text = "戰鬥提示（card_hints）：%s" % ("開" if _hints_on else "關")
	_anim_btn.text = "戰鬥動畫：%s" % ("開" if _animations_on else "關（瞬時）")
	_turn_timer_btn.text = "回合計時：%s" % ("關" if not _turn_timer_on else "%d 秒" % _turn_seconds)
	_draft_timer_btn.text = "選秀計時：%s" % ("關" if not _draft_timer_on else "%d 秒" % _draft_seconds)


# ---------------- 回呼 ----------------

func _on_local_battle() -> void:
	_change_scene(DRAFT_SCENE)


# 單人對戰入口：開 CPU 對手選擇面板。
func _on_single_player() -> void:
	if _ai_panel != null:
		_ai_panel.visible = true


func _on_close_ai() -> void:
	if _ai_panel != null:
		_ai_panel.visible = false


# 選定 CPU 對手 → 用固定預設牌組開一局（玩家 P1、CPU（stage）控制 P2）。
# 仿 draft._start_battle：手動 instantiate battle 以帶入 boot 參數（含 ai_stage）。
func _on_pick_ai(stage: String) -> void:
	if _ai_panel != null:
		_ai_panel.visible = false
	var tree := get_tree()
	if tree == null:
		return   # headless：不做場景切換
	var battle: Node = load(BATTLE_SCENE).instantiate()
	battle.boot(SP_DECK_P1.duplicate(), SP_DECK_P2.duplicate(), randi(), Balance, stage)
	tree.root.add_child(battle)
	tree.current_scene = battle
	queue_free()


func _on_online() -> void:
	_change_scene(ONLINE_SCENE)


func _on_encyclopedia() -> void:
	_change_scene(ENCYCLOPEDIA_SCENE)


# ---------------- P11-2 回放紀錄瀏覽 ----------------

func _on_open_replays() -> void:
	if _replay_panel == null:
		return
	_populate_replays()
	_replay_panel.visible = true


func _on_close_replays() -> void:
	if _replay_panel != null:
		_replay_panel.visible = false


# 列出 user://replays/ 內的紀錄檔為按鈕（新到舊）；無則顯示提示。
func _populate_replays() -> void:
	if _replay_list == null:
		return
	for c in _replay_list.get_children():
		c.queue_free()
	var paths: Array = ReplayLog.list_replays()
	if paths.is_empty():
		var empty := Label.new()
		empty.text = "（尚無紀錄。打一局結束後會自動存檔於 user://replays/）"
		_replay_list.add_child(empty)
		return
	for path: String in paths:
		var b: Button = ReplayRowScene.instantiate()   # 樣式在 item 場景
		b.text = _replay_label(path)
		b.pressed.connect(_on_pick_replay.bind(path))
		_replay_list.add_child(b)


# 從檔名擷取顯示標籤（去目錄與副檔名）。
func _replay_label(path: String) -> String:
	return path.get_file().trim_suffix(".jsonl")


func _on_pick_replay(path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var log: ReplayLog = ReplayLog.load_from_file(path)
	if log == null:
		_msg_label.text = "紀錄檔讀取失敗：" + path
		return
	if _replay_panel != null:
		_replay_panel.visible = false
	var battle: Node = load(BATTLE_SCENE).instantiate()
	battle.boot_replay(log, Balance)
	tree.root.add_child(battle)
	tree.current_scene = battle
	queue_free()


func _on_not_ready() -> void:
	_msg_label.text = "該模式將於後續階段開放（爬塔 Phase 13）。"


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


# 回合計時循環：關 → 30 → 45 → 60 → 90 → 關。0＝關。
func _on_cycle_turn_timer() -> void:
	var cur: int = _turn_seconds if _turn_timer_on else 0
	var nxt: int = _next_in_cycle(TURN_SECONDS_CYCLE, cur)
	_turn_timer_on = nxt != 0
	if nxt != 0:
		_turn_seconds = nxt
	_persist()
	_refresh_settings_labels()


# 選秀計時循環：關 → 30 → 45 → 60 → 關。
func _on_cycle_draft_timer() -> void:
	var cur: int = _draft_seconds if _draft_timer_on else 0
	var nxt: int = _next_in_cycle(DRAFT_SECONDS_CYCLE, cur)
	_draft_timer_on = nxt != 0
	if nxt != 0:
		_draft_seconds = nxt
	_persist()
	_refresh_settings_labels()


func _next_in_cycle(cycle: Array, current: int) -> int:
	var idx: int = cycle.find(current)
	if idx < 0:
		idx = 0
	return int(cycle[(idx + 1) % cycle.size()])


func _on_quit() -> void:
	var tree := get_tree()
	if tree != null:
		tree.quit()


func _persist() -> void:
	SettingsStore.save_settings({
		"hints_on": _hints_on,
		"animations_on": _animations_on,
		"turn_timer_on": _turn_timer_on,
		"turn_seconds": _turn_seconds,
		"draft_timer_on": _draft_timer_on,
		"draft_seconds": _draft_seconds,
	})


func _change_scene(path: String) -> void:
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(path)
