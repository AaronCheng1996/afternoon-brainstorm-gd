# P2-3 對戰場景（本機雙人 hot-seat）。見 docs/rebuild/06 P2-3/P7-4、04 §7、08 §3。
# 一切行動經 GameCore.dispatch；core 吐事件 → CombatScheduler 播動畫 → 動畫結束後
# 由 core 最終狀態「重建棋盤」重新同步（sim/view 分離，見 D1）。
#
# P7-4：UI 骨架（背景/格線/圖層/HUD/勝負面板）宣告於 battle.tscn（編輯器可視可編輯，美術可接手）；
# 本腳本只用場景唯一名稱（`%NodeName`）綁定既有節點、連接信號，不再程序建構。
# 動態集合生成到宣告好的容器：棋子視圖 → BoardLayer、投射物/飄字 → FxLayer、手牌鈕 → HandBox。
# 換美術：棋子視覺在 PieceView 的 SpriteSlot；本場景不含任何美術資源。
extends Node2D

# P12-15 連線終局：對局結束（動畫播完）後 emit，交由 online_lobby 釋放本子場景、嵌入終局統計畫面
# （資料源＝終局快照的 stats/score_history/winner/score；不 change_scene，§11.2-2/7）。
signal net_game_finished(winner: int, score: int, win_threshold: int, score_history: Array,
	stats: Dictionary, reason: String)

const PieceViewScript := preload("res://scenes/battle/piece_view.gd")   # 常數（CELL_SIZE）用
const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")   # 實例化用
const SchedulerScript := preload("res://script/view/combat_scheduler.gd")
const AnimLibScript := preload("res://script/view/piece_animation_library.gd")   # P9-3：職業攻擊演出

const BOARD := 4

const COL_BG := Color(0.10, 0.11, 0.13)
const COL_GRID := Color(0.30, 0.32, 0.36)
const COL_HOVER := Color(1.0, 1.0, 1.0, 0.10)
const COL_RANGE := Color(0.95, 0.35, 0.30, 0.28)
const COL_SELECTED := Color(1.0, 0.9, 0.3, 0.30)
const COL_MOVING := Color(0.4, 0.9, 1.0, 0.22)
const COL_AI_FOCUS := Color(1.0, 0.85, 0.2, 0.95)   # P10-5：單人對戰 AI 目標圈（黃）
const P1_COL := Color(0.95, 0.4, 0.4)
const P2_COL := Color(0.45, 0.6, 1.0)

const MAGIC_CARDS := ["HEAL", "MOVE", "MOVEO", "CUBES"]


# --- 設定 / 狀態 ---
var _p1_deck: Array = []
var _p2_deck: Array = []
var _seed: int = 1
var _db: Object = null

var _core: GameCore = null
var _scheduler: Node = null
var _world_base := Vector2.ZERO      # 鏡頭震動（P9-2）的世界根基準位

var _mode: String = "attack"        # attack / move / heal / cube
var _placing_index: int = -1        # 手牌待放置的單位卡索引（-1=無）
var _busy: bool = false             # 動畫播放中：鎖輸入
var _instant: bool = false          # 動畫開關（true=瞬時）
var _hints_on: bool = true
var _hover_cell: Vector2i = Vector2i(-1, -1)

# P10-5：單人對戰。ai_stage=""＝本機雙人（無 AI）；非空＝該關卡 CPU 控制 player2。
var _ai_stage: String = ""
var _ai: AIController = null
var _ai_focus_key: String = ""      # AI 目標圈狀態指紋（變動才重繪 persist 層）

# P11-1：對戰回合計時（可選）。逾時自動結束當前（人類）玩家回合；AI 回合不計時、動畫忙碌時暫停。
var _turn_timer := CountdownTimer.new()
var _turn_for_timer: int = -1       # 已為哪個 turn_number 啟動過計時（偵測換手重啟）

# P11-2：對戰紀錄與回放。
var _recorder: ReplayLog = null     # 對局中：記錄 seed＋牌組＋action 流（回放模式為 null＝不錄）
var _saved_replay_path: String = "" # 本局存檔路徑（終局時寫入，傳給 end_game 供「回放本局」）
var _replay: ReplayLog = null       # 非 null＝回放模式（禁玩家輸入，依 action 流自動/單步重播）
var _replay_idx: int = 0
var _replay_playing: bool = true
var _replay_speed: float = 1.0
var _replay_accum: float = 0.0
const REPLAY_STEP_INTERVAL := 0.55  # 連續播放時兩步之間的基礎間隔（秒，再除以速度）
const REPLAY_SPEEDS := [0.5, 1.0, 2.0, 4.0]

# 座標換算器（P9-1）：正交/等距雙模式，統一 cell↔pixel。預設等距。
var _view := BoardView.new()

# 視圖層 / 節點（皆綁定自 battle.tscn 內宣告的 `%` 唯一名稱節點）
var _grid_layer: Node2D              # 格線容器（10 條 Line2D，依模式重排為方格/菱形）
var _persist_layer: BattleDrawLayer  # 選取/移動中高亮（隨棋盤重建）
var _board_layer: Node2D             # 棋子視圖容器
var _preview_layer: BattleDrawLayer  # 滑鼠懸停/攻擊範圍預覽
var _fx_layer: Node2D                # 投射物 / 飄字容器
var _views: Dictionary = {}         # Vector2i -> PieceView（真實棋子+neutral）
var _shadow_views: Array = []       # Fuchsia 鏡像視圖（僅顯示）
# P12-4：盤面資料源。空＝即時由 core 編碼；非空＝以公開快照重建（連線客端/旁觀/重連）。
var _snapshot: Dictionary = {}

# P12-12 連線對戰（第四種模式：本機/AI/回放 之外）。net 模式下 `_core` 為 NetMirror 顯示鏡像
# （唯讀、嚴禁 dispatch），輸入一律 encode 送 server、絕不本地 dispatch（§11.2-3/5）。
var _is_net: bool = false
var _net_client: NetClient = null   # 連線客端（由 online_lobby 常駐持有，此處只引用）
var _net_seat: String = ""          # 我的席位（player1/player2；旁觀者為空字串）
var _net_spectator: bool = false    # 旁觀＝永久唯讀（P12-14 專屬變體，本任務先支援 gating）
var _last_net_snapshot: Dictionary = {}   # 最近一次套用的公開快照（測試斷言「兩端＝server」）
var _net_message: String = ""       # 最近一次被拒/提示訊息（顯示於 HUD 狀態列）
var _net_remaining: int = -1        # 回合剩餘秒（server 於快照附 remaining 才顯示；<0＝不顯示）
var _net_spectator_count: int = 0   # P12-14：房內觀戰人數（lobby 依房態轉入，顯示於狀態列）
var _net_opp_held: bool = false     # P12-16：對手斷線等待重連（held），對戰畫面顯示等待提示
var _net_opp_hold_remaining: int = 0   # P12-16：對手 held 剩餘秒（server 權威、客端顯示性）
var _net_opp_name: String = ""      # P12-17：對手暱稱（lobby 依房態轉入；空＝退回席位標示）
var _net_rtt: int = -1              # P12-17：連線延遲 ms（<0＝未量測、不顯示）
var _net_quality: String = ""       # P12-17：連線品質文字（良好/普通/偏高/不穩）
var _net_event_queue: Array = []    # 待播事件批次佇列（動畫忙碌時暫存，播完依序取出）
var _net_pending_snapshot: Dictionary = {}  # 動畫忙碌時到達的校正快照（播完再套用）
var _net_has_pending_snapshot: bool = false
var _net_pending_game_over: bool = false    # 動畫忙碌時到達的終局（播完再收尾）
var _net_pending_winner: String = ""
var _net_pending_reason: String = ""        # P12-15：終局原因（opponent_forfeit 等），隨終局傳給 lobby

# HUD
var _hud: CanvasLayer
var _ui_built: bool = false         # 節點綁定完成旗標（沿用舊名，供測試斷言）
var _scoreboard: Scoreboard         # P8-5：分差 meter／門檻進度／回合／趨勢的獨立記分板
var _res_label: Label
var _counts_label: Label
var _hint_label: KeywordLabel   # P8-3：RichTextLabel 子類，機制詞高亮＋懸停備註
var _mode_buttons: Dictionary = {}  # mode -> Button
var _hand_box: HBoxContainer
var _opponent_hand_box: Container   # D19：對手手牌唯讀公開列（P12-2）
var _toggle_hint_btn: Button
var _toggle_anim_btn: Button
var _view_toggle_btn: Button        # P9-1：俯視／45 度視角切換
var _upgrade_btn: Button
var _end_turn_btn: Button            # P12-14：旁觀模式隱藏（唯讀）
var _win_panel: Panel
var _win_label: Label
var _show_luck: bool = false
var _show_token: bool = false
var _show_totem: bool = false
var _show_coin: bool = false

# P9-3：資源事件飄字。行動前於 _do 快照、_resync 後比對正向變化並飄字（派別色＋標籤）。
var _res_snapshot: Dictionary = {}

# 資源類別 → 顯示標籤與取色用色碼（飄字染派別色）。
const RES_KINDS := {
	"luck": {"label": "運氣", "code": "G"},
	"token": {"label": "藍球", "code": "B"},
	"totem": {"label": "圖騰", "code": "DKG"},
	"coin": {"label": "金幣", "code": "C"},
}


func _ready() -> void:
	if _core == null:
		# 編輯器 F6 直接執行：用預設牌組開一局（含 B/G/C/DKG 以顯示四種資源列）。
		boot(_default_deck_a(), _default_deck_b(), 1)


# 對外啟動：設定牌組並開一局（供主選單/BP 之後呼叫，或 headless 測試直接呼叫）。
# ai_stage 非空（見 AIController.KNOWN_STAGES）＝單人對戰：CPU 以該關卡策略控制 player2。
func boot(p1_deck: Array, p2_deck: Array, seed_value: int, db: Object = null, ai_stage: String = "") -> void:
	_p1_deck = p1_deck
	_p2_deck = p2_deck
	_seed = seed_value
	_db = db if db != null else Balance
	_ai_stage = ai_stage
	_replay = null
	_bind_nodes()
	_apply_settings()
	_new_game()


# P11-2：以錄影紀錄開啟回放模式（禁玩家輸入，依 action 流自動/單步重播）。
func boot_replay(log: ReplayLog, db: Object = null) -> void:
	_p1_deck = log.p1_deck.duplicate()
	_p2_deck = log.p2_deck.duplicate()
	_seed = log.seed
	_db = db if db != null else Balance
	_ai_stage = ""
	_replay = log
	_replay_idx = 0
	_replay_playing = true
	_replay_speed = 1.0
	_replay_accum = 0.0
	_bind_nodes()
	_apply_settings()
	_new_game()
	set_process(true)


# P12-12：以連線客端開啟「連線對戰」模式（見 10 §11）。不建本地權威 core——盤面/HUD 全由
# server 的公開快照（NetMirror 顯示鏡像）與事件流驅動；輸入只 encode 送 server（絕不本地 dispatch）。
#   client：online_lobby 常駐的 NetClient（RPC 路徑鐵則：不得搬移，見 10 §11.2-1）。
#   my_seat：我的席位（player1/player2；旁觀者為空字串）。
#   opening_snapshot：開局公開快照（server 於 battling 起下發的首份）。
func boot_net(client: NetClient, my_seat: String, opening_snapshot: Dictionary,
		spectator: bool = false) -> void:
	_is_net = true
	_net_client = client
	_net_seat = my_seat
	_net_spectator = spectator or my_seat == ""
	_db = Balance
	_replay = null
	_ai_stage = ""
	_recorder = null
	_core = null
	_snapshot = {}
	_bind_nodes()
	_apply_settings()
	set_process(false)   # net 模式為信號驅動（client 於運行樹輪詢 ENet）；本地不跑 AI/計時/回放
	_apply_net_spectator_controls()   # P12-14：旁觀＝隱藏所有行動控制
	_connect_net_signals()
	_apply_net_snapshot(opening_snapshot)


# P12-14：旁觀者唯讀變體——隱藏行動控制（模式工具列/升級/結束回合）。手牌恆唯讀由 _rebuild_hand
# 依 _net_spectator 決定（雙列皆 disabled）。輸入本就由 _net_input_allowed() 恆拒（零送信）。
func _apply_net_spectator_controls() -> void:
	if not (_is_net and _net_spectator) or not _ui_built:
		return
	for m: String in _mode_buttons:
		(_mode_buttons[m] as Button).visible = false
	if _upgrade_btn != null:
		_upgrade_btn.visible = false
	if _end_turn_btn != null:
		_end_turn_btn.visible = false


# 套用 user://settings.json（提示/動畫開關）。戰鬥中自身的切換為 session 內；
# 跨場次持久由主選單設定頁負責。
func _apply_settings() -> void:
	var s := SettingsStore.load_settings()
	_hints_on = bool(s.get("hints_on", true))
	if _toggle_hint_btn != null:
		_toggle_hint_btn.text = "提示：開" if _hints_on else "提示：關"
	set_animation_enabled(bool(s.get("animations_on", true)))
	_turn_timer.configure(bool(s.get("turn_timer_on", false)), float(s.get("turn_seconds", 60)))


func set_animation_enabled(on: bool) -> void:
	_instant = not on
	if _scheduler != null:
		_scheduler.instant = _instant
	if _toggle_anim_btn != null:
		_toggle_anim_btn.text = "動畫：開" if on else "動畫：關"


# ---------------- 開局 ----------------

func _new_game() -> void:
	if _is_net:
		return   # net 模式無本地權威 core；重開由 server（P12-15 再戰閉環）主導
	_core = GameCore.new()
	_core.setup(_p1_deck, _p2_deck, _seed, _db)
	_snapshot = {}                     # P12-4：本機/重開一律以 core 為盤面資料源
	_placing_index = -1
	_mode = "attack"
	_busy = false
	_hover_cell = Vector2i(-1, -1)
	_compute_resource_visibility()
	_setup_ai()
	# P11-2：非回放模式才錄影（記 seed＋牌組，action 於 _do 累積）。
	_recorder = null
	_saved_replay_path = ""
	if _replay == null:
		_recorder = ReplayLog.new(_seed, _p1_deck, _p2_deck)
	_hide_win()
	_resync()


# P10-5：單人對戰時建立控制 player2 的 AIController，並開啟 _process 逐幀驅動。
# 本機雙人（_ai_stage 空）則清空 AI、關閉 process。KEY_R 重開局亦沿用同一關卡。
func _setup_ai() -> void:
	_ai = null
	_ai_focus_key = ""
	if _ai_stage != "" and AIController.is_known_stage(_ai_stage):
		_ai = AIController.new(_ai_stage, _db, "player2")
	_turn_for_timer = -1
	# 有 AI、回合計時、或回放模式任一為真就開 _process。
	set_process(_ai != null or _turn_timer.enabled or _replay != null)


# 依雙方牌組決定要顯示哪些色資源列（G=運氣 / B=藍球 / DKG=圖騰 / C=金幣）。
func _compute_resource_visibility() -> void:
	_show_luck = false
	_show_token = false
	_show_totem = false
	_show_coin = false
	for cid in (_p1_deck + _p2_deck):
		match _db.color_code_of(cid):
			"G": _show_luck = true
			"B": _show_token = true
			"DKG": _show_totem = true
			"C": _show_coin = true


# ---------------- 行動分派（唯一入口）----------------

func _do(action_type: String, x: int, y: int, idx: int = -1) -> void:
	if _is_net:
		_net_do(action_type, x, y, idx)   # net 模式：只 encode 送 server，絕不本地 dispatch（§11.2-3）
		return
	if _busy or _core == null or _core.is_over():
		return
	var a := GameAction.new(action_type, _core.current_player())
	a.board_x = x
	a.board_y = y
	a.hand_index = idx
	if _recorder != null:
		_recorder.record(a)   # P11-2：錄影（回放模式 _recorder 為 null，不錄）
	_res_snapshot = _snapshot_resources()   # P9-3：記錄行動前資源，_resync 時比對變化飄字
	_core.dispatch(a)
	_post_dispatch()


func _post_dispatch() -> void:
	var events: Array = _core.drain_events()
	if events.is_empty():
		_resync()
		return
	_prespawn(events)
	_busy = true
	_scheduler.instant = _instant
	_scheduler.finished.connect(_on_anim_finished, CONNECT_ONE_SHOT)
	_scheduler.play_events(events)


func _on_anim_finished() -> void:
	_busy = false
	_resync()


# ---------------- 單人對戰 AI 驅動（P10-5）----------------

# 只在 AI 回合且非動畫忙碌時，把 AIController 吐出的 GameAction（0/1 個）經既有 _do 分派。
# 節奏（回合開始停頓、行動間隔）與合法性由 AIController 負責（A §1，`is_busy`＝renderer_busy）。
# 本機雙人（_ai 為 null）時 set_process(false)，本函式不運作。
func _process(delta: float) -> void:
	if _core == null:
		return
	if _replay != null:
		_tick_replay(delta)
		return
	_tick_turn_timer(delta)
	# 單人對戰 AI 驅動（見上）。
	if _ai == null or _busy or _core.is_over():
		return
	if _core.current_player() != _ai.player_name:
		return
	var actions: Array = _ai.tick(_core, Time.get_ticks_msec(), _busy)
	for a: GameAction in actions:
		_do(a.action_type, a.board_x, a.board_y, a.hand_index)
	_refresh_ai_focus()


# P11-1：對戰回合計時。只在「人類回合、非動畫忙碌、未結束」時倒數；換手重啟；逾時自動 end_turn。
# AI 回合（單人對戰的 player2）不計時。瞬時模式仍計時（以真實時間倒數）。
func _tick_turn_timer(delta: float) -> void:
	if not _turn_timer.enabled or _core.is_over():
		return
	# AI 控制的回合不計時。
	if _ai != null and _core.current_player() == _ai.player_name:
		_turn_timer.stop()
		return
	if _busy:
		return   # 動畫播放中暫停倒數（不扣時、不逾時）
	if _turn_for_timer != _core.turn_number:
		_turn_for_timer = _core.turn_number
		_turn_timer.start()
	if _turn_timer.advance(delta):
		_do("end_turn", -1, -1)
	elif _counts_label != null:
		_counts_label.text = _counts_text(_core.current_player())   # 每幀更新剩餘秒


# AI 目標圈（focus_position）狀態變動時重繪 persist 層（黃圈畫在 _persist_draw）。
func _refresh_ai_focus() -> void:
	if _ai == null:
		return
	var key: String = "%s:%d,%d" % [_ai.has_focus, _ai.focus_position.x, _ai.focus_position.y]
	if key != _ai_focus_key:
		_ai_focus_key = key
		if _persist_layer != null:
			_persist_layer.queue_redraw()


# ---------------- 回放播放（P11-2）----------------

# 連續播放：等動畫播完（非 _busy）後，依間隔（除以速度）自動推進下一步。
func _tick_replay(delta: float) -> void:
	if _busy or _core.is_over() or _replay_idx >= _replay.actions.size():
		if _replay_idx >= _replay.actions.size():
			_replay_playing = false
		_update_replay_hud()
		return
	if not _replay_playing:
		_update_replay_hud()
		return
	_replay_accum += delta * _replay_speed
	if _replay_accum >= REPLAY_STEP_INTERVAL:
		_replay_accum = 0.0
		_replay_step()
	_update_replay_hud()


# 推進一步：把第 _replay_idx 筆錄影 action 走既有 _do 管線（事件→動畫→重建）。
func _replay_step() -> void:
	if _busy or _core.is_over() or _replay_idx >= _replay.actions.size():
		return
	var a: GameAction = _replay.action_at(_replay_idx)
	_replay_idx += 1
	_do(a.action_type, a.board_x, a.board_y, a.hand_index)


func _replay_toggle_play() -> void:
	_replay_playing = not _replay_playing
	_replay_accum = 0.0
	_update_replay_hud()


func _replay_cycle_speed() -> void:
	var i: int = REPLAY_SPEEDS.find(_replay_speed)
	_replay_speed = REPLAY_SPEEDS[(i + 1) % REPLAY_SPEEDS.size()] if i >= 0 else 1.0
	_update_replay_hud()


func _update_replay_hud() -> void:
	if _counts_label == null:
		return
	var state: String = "▶ 播放中" if _replay_playing else "⏸ 暫停"
	if _replay_idx >= _replay.actions.size():
		state = "⏹ 結束"
	_counts_label.text = "── 回放 ──\n%s　%d/%d 步　速度 x%s\n[空白]播放/暫停　[→]單步　[S]速度" % [
		state, _replay_idx, _replay.actions.size(), str(_replay_speed)]


# ---------------- 連線對戰（P12-12，見 10 §4/§6/§11）----------------

func _connect_net_signals() -> void:
	if _net_client == null:
		return
	if not _net_client.battle_events.is_connected(_on_net_events):
		_net_client.battle_events.connect(_on_net_events)
	if not _net_client.snapshot_received.is_connected(_on_net_snapshot):
		_net_client.snapshot_received.connect(_on_net_snapshot)
	if not _net_client.game_over.is_connected(_on_net_game_over):
		_net_client.game_over.connect(_on_net_game_over)
	if not _net_client.action_rejected.is_connected(_on_net_action_rejected):
		_net_client.action_rejected.connect(_on_net_action_rejected)


func _disconnect_net_signals() -> void:
	if _net_client == null:
		return
	if _net_client.battle_events.is_connected(_on_net_events):
		_net_client.battle_events.disconnect(_on_net_events)
	if _net_client.snapshot_received.is_connected(_on_net_snapshot):
		_net_client.snapshot_received.disconnect(_on_net_snapshot)
	if _net_client.game_over.is_connected(_on_net_game_over):
		_net_client.game_over.disconnect(_on_net_game_over)
	if _net_client.action_rejected.is_connected(_on_net_action_rejected):
		_net_client.action_rejected.disconnect(_on_net_action_rejected)


# 子場景離樹（online_lobby 釋放連線對戰子場景時）：斷開對 client 的信號連結，
# 連線本身（NetClient）由 online_lobby 常駐管理，不在此關閉（RPC 路徑鐵則，§11.2-1）。
func _exit_tree() -> void:
	if _is_net:
		_disconnect_net_signals()


# 校正快照到達（D20：server 每次成功行動後即下發）：非忙碌立即套用，行動結果即時反映於
# 手牌/資源/盤面；動畫忙碌時暫存，待本批事件播完再套用（避免打斷動畫）。
# 防呆（P12-19）：若本地 _busy 與排程器實況不一致（finished 信號在某時序下漏觸發，
# 實機「busy 旗標未解除」假說），以排程器為準先解除，避免快照無限暫存、行動結果無聲遺失。
func _on_net_snapshot(snap: Dictionary) -> void:
	if _busy and _scheduler != null and not _scheduler.is_busy():
		_busy = false
	if _busy:
		_net_pending_snapshot = snap
		_net_has_pending_snapshot = true
	else:
		_apply_net_snapshot(snap)


# 套用公開快照＝重建顯示鏡像 core（NetMirror）＋重畫盤面＋刷新 HUD。net 模式盤面資料源＝鏡像 core
# （_snapshot 保持空，_board_pieces 走即時 encode_piece 路徑），單一事實來源，讀取碼原樣重用。
func _apply_net_snapshot(snap: Dictionary) -> void:
	_last_net_snapshot = snap
	_net_remaining = int(snap.get("remaining", -1))   # server 未附則 <0＝不顯示（回合計時預設關）
	_core = NetMirror.build(snap, _db)
	_snapshot = {}
	_placing_index = -1
	if not _ui_built:
		return
	_compute_resource_visibility_from_core()
	_rebuild_board()
	_refresh_hud()
	# net 模式的終局不用 battle 內建勝負面板：改由 _finish_net_game emit net_game_finished，
	# 交 online_lobby 開終局統計畫面（P12-15，§11.2-7）。此處只保持面板隱藏。
	_hide_win()


# net 模式無 _p1_deck/_p2_deck（跳過本地 setup）：依鏡像 core 現有棋子決定要顯示哪些色資源列。
func _compute_resource_visibility_from_core() -> void:
	_show_luck = _core.players_luck["player1"] != GameConfig.LUCK_INITIAL \
		or _core.players_luck["player2"] != GameConfig.LUCK_INITIAL
	_show_token = _core.players_token["player1"] > 0 or _core.players_token["player2"] > 0
	_show_totem = _core.players_totem["player1"] > 0 or _core.players_totem["player2"] > 0
	_show_coin = _core.players_coin["player1"] > 0 or _core.players_coin["player2"] > 0
	for p: PieceState in _core.get_all_pieces():
		match p.color_code:
			"G": _show_luck = true
			"B": _show_token = true
			"DKG": _show_totem = true
			"C": _show_coin = true


# 一批事件到達：排入佇列後嘗試播放（忙碌時等當前批播完再取下一批）。
func _on_net_events(events: Array) -> void:
	_net_event_queue.append(events)
	_drain_net_events()


func _drain_net_events() -> void:
	if _busy or _net_event_queue.is_empty():
		return
	var events: Array = _net_event_queue.pop_front()
	if events.is_empty():
		_drain_net_events()
		return
	_prespawn(events)
	_busy = true
	_scheduler.instant = _instant
	_scheduler.finished.connect(_on_net_anim_finished, CONNECT_ONE_SHOT)
	_scheduler.play_events(events)


# 一批事件播完：解鎖 → 若有暫存校正快照先套用（D20：server 每次行動皆下發，故一般每批播完
# 都會有一份→立即以權威快照重建盤面/手牌/資源，行動結果即時呈現、不待回合交接）→ 否則只
# 刷新 HUD（無快照可用的少數情形，如 server 尚未送達；此時不從鏡像重建盤面以免回捲已演出的
# 變化）→ 再取下一批事件。
func _on_net_anim_finished() -> void:
	_busy = false
	if _net_pending_game_over:
		_net_pending_game_over = false
		var s := _net_pending_snapshot
		_net_pending_snapshot = {}
		_net_has_pending_snapshot = false
		_finish_net_game(s, _net_pending_winner, _net_pending_reason)
		return
	if _net_has_pending_snapshot:
		_net_has_pending_snapshot = false
		var snap := _net_pending_snapshot
		_net_pending_snapshot = {}
		_apply_net_snapshot(snap)
	elif _ui_built:
		_refresh_hud()
	_drain_net_events()


# 終局：套最終快照（含勝方/統計）後交由 lobby 開終局統計。動畫忙碌時暫存、播完再收尾。
func _on_net_game_over(info: Dictionary) -> void:
	var reason := String(info.get("reason", ""))
	if reason == NetMessage.REASON_OPPONENT_FORFEIT:
		_net_message = "對手離線逾時，你獲勝。"
	var snap: Dictionary = info.get("snapshot", {})
	var winner_name := String(info.get("winner", ""))
	if _busy:
		_net_pending_snapshot = snap
		_net_has_pending_snapshot = not snap.is_empty()
		_net_pending_game_over = true
		_net_pending_winner = winner_name
		_net_pending_reason = reason
		return
	_finish_net_game(snap, winner_name, reason)


# 收尾：套最終快照（含統計 export/score_history/勝方）；forfeit 等快照未必 over，以 game_over 的
# winner 強制標記。完成後 emit net_game_finished 交 online_lobby 開終局統計畫面（P12-15，§11.2-7）。
func _finish_net_game(snap: Dictionary, winner_name: String, reason: String = "") -> void:
	if not snap.is_empty():
		_apply_net_snapshot(snap)
	if _core != null and not _core.is_over():
		_core.mark_over(winner_name)
	if _ui_built:
		_refresh_hud()
	var s := _last_net_snapshot
	net_game_finished.emit(
		_core.winner() if _core != null else -1,
		int(s.get("score", _core.score if _core != null else 0)),
		_core.config.win_threshold if _core != null else GameConfig.WIN_THRESHOLD_DEFAULT,
		s.get("score_history", []),
		s.get("stats", {}),
		reason)


# 我方行動被 server 拒（回合閘/次數不足…）：顯示原因於狀態列（不斷線）。
# server 端 action_rejected 的 reason 有時為穩定常數、有時直接是 dispatch 的訊息（如「攻擊次數不足」）；
# 有 message 優先顯示 message，否則對常見常數給中文、其餘回顯 reason 原字串。
func _on_net_action_rejected(reason: String, message: String) -> void:
	if message != "":
		_net_message = message
	else:
		match reason:
			NetMessage.REASON_NOT_YOUR_TURN: _net_message = "還沒輪到你行動。"
			NetMessage.REASON_SPECTATOR_ACTION: _net_message = "旁觀者無法行動。"
			NetMessage.REASON_NOT_BATTLING: _net_message = "目前不在對戰中。"
			NetMessage.REASON_BAD_ACTION: _net_message = "行動非法。"
			_: _net_message = reason
	if _ui_built:
		_refresh_hud()


# net 模式輸入單點閘（§11.2-5）：我的席位＝當前玩家、非動畫忙碌、非旁觀、對局未結束。
func _net_input_allowed() -> bool:
	return _is_net and not _net_spectator and not _busy \
		and _core != null and not _core.is_over() \
		and _core.current_player() == _net_seat


# net 模式的行動出口（§11.2-3）：**只 encode 送 server，絕不本地 dispatch**。gating 不通過＝零送信。
func _net_do(action_type: String, x: int, y: int, idx: int) -> void:
	if not _net_input_allowed() or _net_client == null:
		return
	_net_message = ""
	var a := GameAction.new(action_type, _net_seat)
	a.board_x = x
	a.board_y = y
	a.hand_index = idx
	_net_client.send_action(a)


# net 模式 HUD 狀態列（回合歸屬/旁觀/剩餘秒/被拒訊息）——取代本機的「當前玩家可用」計數塊。
func _net_status_text() -> String:
	var lines: Array = []
	if _net_spectator:
		lines.append("👁 旁觀中")
	elif _core.is_over():
		lines.append("對戰結束。")
	elif _core.current_player() == _net_seat:
		lines.append("▶ 你的回合，請行動。")
	else:
		lines.append("⏳ 對方回合…")
	if not _net_spectator:
		var me_line := "你＝%s" % ("先手 P1" if _net_seat == "player1" else "後手 P2")
		if _net_opp_name != "":
			me_line += "　對手：%s" % _net_opp_name
		lines.append(me_line)
	if _net_remaining >= 0:
		lines.append("回合剩餘：%d 秒" % _net_remaining)
	if _net_rtt >= 0:
		lines.append("延遲：%d ms（%s）" % [_net_rtt, _net_quality])
	if _net_spectator_count > 0:
		lines.append("👁 觀戰：%d 人" % _net_spectator_count)
	# P12-16：對手斷線等待重連——顯示等待提示（server 權威保留席位；逾時則對手判勝，見 §8）。
	if _net_opp_held:
		if _net_opp_hold_remaining > 0:
			lines.append("⏳ 對方斷線，等待重連（剩餘 %d 秒）…" % _net_opp_hold_remaining)
		else:
			lines.append("⏳ 對方斷線，等待重連…")
	if _net_message != "":
		lines.append("⚠ %s" % _net_message)
	return "\n".join(lines)


# P12-16：對手 held（斷線等待重連）狀態更新（lobby 於房態轉入時呼叫）。顯示於狀態列。
func set_opponent_held(held: bool, remaining: int) -> void:
	_net_opp_held = held
	_net_opp_hold_remaining = remaining
	_refresh_net_status()


# P12-17：對手暱稱更新（lobby 於房態轉入時呼叫）。
func set_opponent_name(name: String) -> void:
	_net_opp_name = name
	_refresh_net_status()


# P12-17：連線延遲/品質更新（lobby 週期心跳 rtt_measured 轉入）。
func set_rtt(rtt_ms: int) -> void:
	_net_rtt = rtt_ms
	_net_quality = net_quality_text(rtt_ms) if rtt_ms >= 0 else ""
	_refresh_net_status()


# RTT → 連線品質文字（純函式，與 draft/大廳一致的門檻）。
static func net_quality_text(rtt_ms: int) -> String:
	if rtt_ms < 80:
		return "良好"
	if rtt_ms < 160:
		return "普通"
	if rtt_ms < 300:
		return "偏高"
	return "不穩"


func _refresh_net_status() -> void:
	if _is_net and _ui_built and _counts_label != null:
		_counts_label.text = _net_status_text()


# P12-14：房內觀戰人數更新（lobby 於房態轉入時呼叫）。只輕量更新狀態列。
func set_spectator_count(n: int) -> void:
	_net_spectator_count = n
	if _is_net and _ui_built and _counts_label != null:
		_counts_label.text = _net_status_text()


# 為 SPAWN 事件先建立視圖（動畫連續性：deploy 引發的傷害可解析到新棋子/既有棋子）。
func _prespawn(events: Array) -> void:
	for e: GameEvent in events:
		if e.kind == GameEvent.Kind.SPAWN:
			var at: Vector2i = e.data["at"]
			if _views.has(at):
				continue
			var v: Node2D = _make_piece_view(e.data["card_id"], _owner_int(e.data["owner"]), at)
			v.instant = _instant
			_views[at] = v
			v.play_cast()


# ---------------- 同步（動畫結束後以 core 最終狀態重建）----------------

func _resync() -> void:
	_drain_logic()
	_rebuild_board()
	_refresh_hud()
	_flush_resource_feedback()   # P9-3：資源正向變化飄字
	if _core.is_over():
		_show_win()


# 消化 logic_step：回收死亡棋子 + 逐步抽牌（card_to_draw 可 >1，迴圈至清空）。
func _drain_logic() -> void:
	_core.logic_step()
	var guard: int = 0
	while (_core.card_to_draw["player1"] > 0 or _core.card_to_draw["player2"] > 0) and guard < 128:
		guard += 1
		_core.logic_step()


# P12-4：盤面資料源一般化——快照非空時取快照 pieces，否則即時由 core 編碼；
# 兩路皆回傳 GameSnapshot 的棋子欄位 Dictionary，_rebuild_board 統一消費。
func _board_pieces() -> Array:
	if not _snapshot.is_empty():
		return _snapshot.get("pieces", [])
	var out: Array = []
	for p: PieceState in _core.get_all_pieces():
		out.append(GameSnapshot.encode_piece(p))
	return out


# P12-4：以公開快照為盤面資料源並重畫（連線客端/旁觀/重連用；本機不呼叫）。
# 傳空 Dictionary 還原為 core 資料源。
func apply_snapshot(snap: Dictionary) -> void:
	_snapshot = snap
	if _ui_built:
		_rebuild_board()


func _rebuild_board() -> void:
	for c in _board_layer.get_children():
		c.free()
	_views.clear()
	_shadow_views.clear()
	_persist_layer.queue_redraw()

	for pd: Dictionary in _board_pieces():
		var cell := Vector2i(int(pd["board_x"]), int(pd["board_y"]))
		var v: Node2D = _make_piece_view(String(pd["card_id"]), _owner_int(String(pd["owner"])), cell)
		v.update_stats(int(pd["health"]), int(pd["damage"]), int(pd["armor"]), int(pd["extra_damage"]))
		var st: Dictionary = pd["statuses"]
		v.set_status("numbness", _status_on(st, "numbness"))
		v.set_status("moving", _status_on(st, "moving"))
		v.set_status("anger", _status_on(st, "anger"))
		_views[cell] = v
		# Fuchsia 鏡像（僅顯示，不進 _views）。
		for shd: Dictionary in pd.get("shadows", []):
			var scell := Vector2i(int(shd["board_x"]), int(shd["board_y"]))
			var job: String = String(shd.get("linker_job", ""))
			if job == "":
				job = "ADC"
			var sv: Node2D = PieceViewScene.instantiate()
			sv.position = _cell_topleft(scell)
			sv.z_index = _view.depth(scell)
			sv.fx_layer = _fx_layer
			_board_layer.add_child(sv)
			sv.configure("SHADOW", _owner_int(String(shd["owner"])), _db, true, job)
			_shadow_views.append(sv)


# 快照 statuses（{id:{value,duration}}）某狀態是否為真。
func _status_on(statuses: Dictionary, id: String) -> bool:
	return statuses.has(id) and bool(statuses[id].get("value", false))


func _make_piece_view(card_id: String, owner_int: int, cell: Vector2i) -> Node2D:
	var v: Node2D = PieceViewScene.instantiate()
	v.position = _cell_topleft(cell)
	v.z_index = _view.depth(cell)   # 等距遮擋：畫面越前（x+y 越大）越後畫、疊在上層（P9-1）
	v.fx_layer = _fx_layer          # P9-2：命中/死亡粒子與殘影掛 fx 層（本視圖釋放後仍存活）
	_board_layer.add_child(v)
	v.configure(card_id, owner_int, _db)
	v.set_animation_set(AnimLibScript.for_card(card_id, _db))   # P9-3：遠程投射物／近戰撲擊＋派別色特效
	return v


# ---------------- 輸入（棋盤點擊 / 懸停 / 鍵盤）----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = _cell_from_global(event.position)
		if cell.x >= 0:
			_board_click(cell)
	elif event is InputEventMouseMotion:
		_hover_cell = _cell_from_global(event.position)
		_update_preview()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)


func _board_click(cell: Vector2i) -> void:
	if _replay != null or _busy or _core.is_over():
		return
	if _is_net and not _net_input_allowed():
		return   # 非我回合/旁觀：完全不處理（連 _placing_index 都不動，確保零送信）
	if _placing_index >= 0:
		_do("play_card", cell.x, cell.y, _placing_index)
		_placing_index = -1
		return
	match _mode:
		"attack": _do("attack", cell.x, cell.y)
		"move": _do("move_to", cell.x, cell.y)
		"heal": _do("heal", cell.x, cell.y)
		"cube": _do("spawn_cube", cell.x, cell.y)


func _handle_key(keycode: int) -> void:
	if _replay != null:
		# 回放模式：鍵盤只控播放（空白＝播放/暫停、→/.＝單步、S＝速度），保留 I/V/T 觀看選項。
		match keycode:
			KEY_SPACE: _replay_toggle_play()
			KEY_RIGHT, KEY_PERIOD: _replay_step()
			KEY_S: _replay_cycle_speed()
			KEY_I: set_animation_enabled(_instant)
			KEY_T: _on_toggle_hints()
			KEY_V: _toggle_board_mode()
		return
	match keycode:
		KEY_A: _set_mode("attack")
		KEY_M: _set_mode("move")
		KEY_H: _set_mode("heal")
		KEY_C: _set_mode("cube")
		KEY_SPACE, KEY_ENTER: _do("end_turn", -1, -1)
		KEY_I: set_animation_enabled(_instant)   # 切換
		KEY_T: _on_toggle_hints()
		KEY_V: _toggle_board_mode()              # 正交／等距視角切換（P9-1，供對照）
		KEY_R: _new_game()


# ---------------- HUD 回呼 ----------------

func _on_hand_pressed(index: int) -> void:
	if _replay != null or _busy or _core.is_over():
		return
	if _is_net and not _net_input_allowed():
		return
	var hand: Array = _core.get_player(_core.current_player()).hand
	if index < 0 or index >= hand.size():
		return
	var card: String = hand[index]
	var base_name: String = card.trim_suffix(" (+)")
	if MAGIC_CARDS.has(base_name):
		_placing_index = -1
		_do("play_card", -1, -1, index)   # 魔法卡：即時打出（獲得次數），無需目標格
	else:
		_placing_index = -1 if _placing_index == index else index
		_refresh_hud()


func _on_toggle_upgrade() -> void:
	if _replay != null or _busy or _core.is_over() or _placing_index < 0:
		return
	_do("toggle_upgrade", -1, -1, _placing_index)   # 只改手牌名（無事件）→ _resync 重繪


func _set_mode(m: String) -> void:
	_mode = m
	_placing_index = -1
	_refresh_hud()
	_update_preview()


func _on_toggle_hints() -> void:
	_hints_on = not _hints_on
	if _toggle_hint_btn != null:
		_toggle_hint_btn.text = "提示：開" if _hints_on else "提示：關"
	_update_preview()


func _on_win_restart() -> void:
	if _replay != null:
		# 回放模式：從頭重播（保留同一份紀錄）。
		_replay_idx = 0
		_replay_playing = true
		_replay_accum = 0.0
	_new_game()


func _on_win_menu() -> void:
	if _is_net:
		return   # net 子場景不自行 change_scene（會拆掉常駐連線）；回房/離開由 online_lobby 主導（P12-15）
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file("res://scenes/menu/main_menu.tscn")


# 轉到終局統計畫面（帶勝者/分數/每回合分數/主要統計前幾名）。
func _open_end_game() -> void:
	if _is_net:
		return   # net 終局統計＋再戰閉環於 P12-15 由 online_lobby 主導（資料源＝終局快照統計 export）
	var tree := get_tree()
	if tree == null:
		return
	var end_scene: Node = load("res://scenes/end_game/end_game.tscn").instantiate()
	# P8-6：傳完整統計 export（{stat_name: {owner_cardid: int}}）；摘要長條與表格由 end_game 派生。
	# P11-2：附本局紀錄路徑（非回放時才有），供終局畫面「回放本局」。
	end_scene.configure(_core.winner(), _core.score, _core.config.win_threshold,
		_core.stats.score_history.duplicate(), _core.stats.export_for_charts(), _saved_replay_path)
	tree.root.add_child(end_scene)
	tree.current_scene = end_scene
	queue_free()


# ---------------- 座標換算（統一委派 BoardView，P9-1）----------------

func _cell_topleft(cell: Vector2i) -> Vector2:
	return _view.cell_topleft(cell)


func _cell_center(cell: Vector2i) -> Vector2:
	return _view.cell_center(cell)


# P9-2 擊殺鏡頭震動：對世界根（Node2D）做衰減隨機位移，震完歸位。
# HUD 為 CanvasLayer，不受父 Node2D 變換影響，故不跟著晃。瞬時模式（動畫關）不震。
# 用全域 randf（純表現），不動 RngService，不影響對局決定性。
func _camera_shake(strength: float = 6.0) -> void:
	if _instant:
		return
	var tw := create_tween()
	var steps := 5
	for i in steps:
		var damp := strength * (1.0 - float(i) / float(steps))
		var off := Vector2(randf_range(-damp, damp), randf_range(-damp, damp))
		tw.tween_property(self, "position", _world_base + off, 0.03)
	tw.tween_property(self, "position", _world_base, 0.04)


func _cell_from_global(p: Vector2) -> Vector2i:
	return _view.cell_from_pixel(p)


# 依當前模式把 10 條格線（.tscn 預置的 H0..H4 / V0..V4）重排為方格或菱形。
func _layout_grid() -> void:
	if _grid_layer == null:
		return
	for i in range(BOARD + 1):
		var h: Line2D = _grid_layer.get_node("H%d" % i)
		h.points = PackedVector2Array([_view.corner(0, i), _view.corner(BOARD, i)])
		var v: Line2D = _grid_layer.get_node("V%d" % i)
		v.points = PackedVector2Array([_view.corner(i, 0), _view.corner(i, BOARD)])


# 切換俯視（正交）／45 度（等距）視角（HUD「視角」鈕或 V 鍵；即時重排、不影響對局）。
func _toggle_board_mode() -> void:
	_view.mode = BoardView.Mode.ORTHO if _view.mode == BoardView.Mode.ISO else BoardView.Mode.ISO
	_layout_grid()
	if _core != null:
		_rebuild_board()
	_persist_layer.queue_redraw()
	_update_preview()
	_update_view_toggle_text()


# 視角鈕文字反映當前模式（沿用 提示/動畫 鈕的「當前狀態」慣例）。
func _update_view_toggle_text() -> void:
	if _view_toggle_btn != null:
		_view_toggle_btn.text = "視角：俯視" if _view.mode == BoardView.Mode.ORTHO else "視角：45度"


# 取該格棋子視圖；已被釋放（如死亡動畫中 queue_free 但 _views 尚未重建）回 null 並剔除，
# 避免懸停/排程器取用已釋放實例（_view_at 亦為 scheduler resolver）。
func _view_at(cell: Vector2i) -> Object:
	var v: Variant = _views.get(cell, null)
	if v == null:
		return null
	if not is_instance_valid(v):
		_views.erase(cell)
		return null
	return v


func _in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < BOARD and c.y >= 0 and c.y < BOARD


func _owner_int(owner: String) -> int:
	if owner == "player1":
		return 1
	if owner == "player2":
		return 2
	return 0


# ---------------- 攻擊範圍預覽（含鏡像）----------------

func _update_preview() -> void:
	if _preview_layer == null:
		return
	_preview_layer.queue_redraw()
	_update_hint_text()


func _preview_draw() -> void:
	# 懸停格外框（依模式為方形/菱形，走 BoardView 頂點）。
	if _in_board(_hover_cell):
		_fill_cell(_preview_layer, _hover_cell, COL_HOVER)
		_outline_cell(_preview_layer, _hover_cell, Color(1, 1, 1, 0.5), 2.0)
	# 攻擊模式：懸停在我方棋子上 → 顯示其攻擊範圍（含 Fuchsia 鏡像）。
	if _mode == "attack" and _in_board(_hover_cell):
		var piece: PieceState = _my_piece_at(_hover_cell)
		if piece != null:
			for cell: Vector2i in _footprint_cells(piece):
				_fill_cell(_preview_layer, cell, COL_RANGE)


func _persist_draw() -> void:
	if _core == null:
		return
	for piece: PieceState in _core.get_both_player_pieces():
		# 選取中（selected）與移動中（moving）棋子的持續高亮（格內填色）。
		if piece.has_status("selected"):
			_fill_cell(_persist_layer, piece.pos(), COL_SELECTED)
		elif piece.is_moving():
			_fill_cell(_persist_layer, piece.pos(), COL_MOVING)
		# 擁有者標示：棋子所在格的地格外框上色（先手紅／後手藍）——取代舊的棋子本體外框環。
		var oc: Color = P1_COL if piece.owner == "player1" else P2_COL
		_outline_cell(_persist_layer, piece.pos(), oc, 3.5)
	# P10-5：單人對戰時，AI 決策鎖定的格畫黃色目標圈。
	if _ai != null and _ai.has_focus and _in_board(_ai.focus_position):
		_outline_cell(_persist_layer, _ai.focus_position, COL_AI_FOCUS, 3.0)


# 格填色 / 格外框（統一走 BoardView.cell_polygon，正交＝方形、等距＝菱形）。
func _fill_cell(layer: BattleDrawLayer, cell: Vector2i, color: Color) -> void:
	layer.draw_colored_polygon(_view.cell_polygon(cell), color)


func _outline_cell(layer: BattleDrawLayer, cell: Vector2i, color: Color, width: float) -> void:
	var poly: PackedVector2Array = _view.cell_polygon(cell)
	poly.append(poly[0])   # 閉合
	layer.draw_polyline(poly, color, width)


func _my_piece_at(cell: Vector2i) -> PieceState:
	for piece: PieceState in _core.get_player(_core.current_player()).on_board:
		if piece.pos() == cell:
			return piece
	return null


# 計算攻擊命中格（本體 + 各鏡像；nearest/farthest 取同距候選，不消耗 rng）。
func _footprint_cells(piece: PieceState) -> Array:
	var cells: Array = []
	_add_pattern(piece.attack_types, piece.pos(), piece.owner, cells)
	for sh: PieceState in piece.shadows:
		_add_pattern(sh.get_shadow_attack_types(), sh.pos(), sh.owner, cells)
	return cells


func _add_pattern(attack_types: String, origin: Vector2i, owner: String, cells: Array) -> void:
	for at: String in attack_types.split(" ", false):
		match at:
			"small_cross":
				_push_cells(cells, origin, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
			"small_x":
				_push_cells(cells, origin, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
			"large_cross":
				for i in BOARD:
					_push_one(cells, Vector2i(origin.x, i), origin)
					_push_one(cells, Vector2i(i, origin.y), origin)
			"nearest", "farthest":
				_push_distance_cells(cells, origin, owner, at == "farthest")
			_:
				pass   # large_x / None：無命中


func _push_cells(cells: Array, origin: Vector2i, offsets: Array) -> void:
	for off: Vector2i in offsets:
		_push_one(cells, origin + off, origin)


func _push_one(cells: Array, cell: Vector2i, origin: Vector2i) -> void:
	if cell != origin and _in_board(cell) and not cells.has(cell):
		cells.append(cell)


func _push_distance_cells(cells: Array, origin: Vector2i, owner: String, farthest: bool) -> void:
	var enemies: Array = _core.get_enemies_of(owner).filter(func(c: PieceState) -> bool: return c.health > 0)
	if enemies.is_empty():
		return
	var best: int = -1
	for c: PieceState in enemies:
		var d: int = abs(c.board_x - origin.x) + abs(c.board_y - origin.y)
		if best < 0 or (farthest and d > best) or (not farthest and d < best):
			best = d
	for c: PieceState in enemies:
		var d2: int = abs(c.board_x - origin.x) + abs(c.board_y - origin.y)
		if d2 == best and not cells.has(c.pos()):
			cells.append(c.pos())


# ---------------- 提示文字 ----------------

func _update_hint_text() -> void:
	if _hint_label == null:
		return
	if not _hints_on:
		_hint_label.set_source("")
		return
	var txt: String = ""
	if _in_board(_hover_cell):
		var v: Object = _view_at(_hover_cell)
		if v != null:
			var cid: String = v.card_id
			var info: Dictionary = _db.text(cid)
			# 提示列高度有限：多行提示以全形空白併為單行；機制詞由 KeywordLabel 高亮＋懸停解釋。
			var hint: String = String(info.get("hint", "")).replace("\n", "　")
			txt = "[b]%s[/b]：%s" % [String(info.get("name", cid)), hint]
	_hint_label.set_source(txt)


# ---------------- HUD 建構與刷新 ----------------

# 綁定 battle.tscn 內宣告的節點（場景唯一名稱 `%`）並連接信號 + 建立排程器。
# idempotent：_ready 與 boot 皆呼叫，首次生效。`%` 於 instantiate 後即可解析（不需先進場景樹），
# 故 headless 亦適用（見 P7-3 進度日誌技術註記）。
func _bind_nodes() -> void:
	if _ui_built:
		return
	_ui_built = true

	# 世界層（Node2D）。
	_grid_layer = %GridLayer
	_layout_grid()   # 依 _view 模式把格線排成方格/菱形（P9-1）
	_persist_layer = %PersistLayer
	_persist_layer.cb = _persist_draw
	_preview_layer = %PreviewLayer
	_preview_layer.cb = _preview_draw
	_board_layer = %BoardLayer
	_fx_layer = %FxLayer

	# 排程器（非視覺、不在 .tscn；建為子節點以供動畫；瞬時模式無需進場景樹）。
	_scheduler = SchedulerScript.new()
	add_child(_scheduler)
	_scheduler.setup(Callable(self, "_view_at"), _fx_layer, Callable(self, "_cell_center"))
	_scheduler.instant = _instant
	_scheduler.on_kill = Callable(self, "_camera_shake")   # P9-2：擊殺時輕微鏡頭震動
	_world_base = position                                  # 鏡頭震動的基準位（震完歸位）

	# HUD 標籤。
	_hud = %HUD
	_scoreboard = %Scoreboard
	_res_label = %ResLabel
	_counts_label = %CountsLabel
	_hint_label = %HintLabel

	# 模式工具列。
	_mode_buttons = {
		"attack": %AttackBtn,
		"move": %MoveBtn,
		"heal": %HealBtn,
		"cube": %CubeBtn,
	}
	for m: String in _mode_buttons:
		_mode_buttons[m].pressed.connect(_set_mode.bind(m))

	_upgrade_btn = %UpgradeBtn
	_upgrade_btn.pressed.connect(_on_toggle_upgrade)
	_toggle_hint_btn = %HintToggle
	_toggle_hint_btn.pressed.connect(_on_toggle_hints)
	_toggle_anim_btn = %AnimToggle
	_toggle_anim_btn.pressed.connect(func() -> void: set_animation_enabled(_instant))
	_view_toggle_btn = %ViewToggle
	_view_toggle_btn.pressed.connect(_toggle_board_mode)
	_update_view_toggle_text()
	_end_turn_btn = %EndTurnBtn
	_end_turn_btn.pressed.connect(_do.bind("end_turn", -1, -1, -1))

	# 手牌容器（動態手牌鈕生成於此）。己方＝可點手牌列；對手＝唯讀公開列（D19，P12-2）。
	_hand_box = %HandBox
	_opponent_hand_box = %OpponentHandBox

	# 勝負面板。
	_win_panel = %WinPanel
	_win_label = %WinLabel
	(%RestartBtn as Button).pressed.connect(_on_win_restart)
	(%StatsBtn as Button).pressed.connect(_open_end_game)
	(%MenuBtn as Button).pressed.connect(_on_win_menu)


func _refresh_hud() -> void:
	if not _ui_built:
		return
	var cur: String = _core.current_player()
	_scoreboard.update_board(_core.score, _core.config.win_threshold, _core.turn_number,
		cur, _core.stats.score_history)

	_res_label.text = _resource_text()
	# net 模式以「回合歸屬/旁觀/被拒訊息」取代本機的可用次數塊（次數仍隨快照更新於資源列旁）。
	_counts_label.text = _net_status_text() if _is_net else _counts_text(cur)

	# 模式按鈕高亮。
	for m: String in _mode_buttons:
		_mode_buttons[m].modulate = Color(1, 1, 0.6) if m == _mode else Color(1, 1, 1)

	_rebuild_hand(cur)
	_update_hint_text()


func _resource_text() -> String:
	var lines: Array = ["資源　　　P1　P2"]
	if _show_luck:
		lines.append("運氣　　　%d　%d" % [_core.players_luck["player1"], _core.players_luck["player2"]])
	if _show_token:
		lines.append("藍球　　　%d　%d" % [_core.players_token["player1"], _core.players_token["player2"]])
	if _show_totem:
		lines.append("圖騰　　　%d　%d" % [_core.players_totem["player1"], _core.players_totem["player2"]])
	if _show_coin:
		lines.append("金幣　　　%d　%d" % [_core.players_coin["player1"], _core.players_coin["player2"]])
	if lines.size() == 1:
		lines.append("（本局牌組無色資源）")
	return "\n".join(lines)


# --- P9-3 資源事件飄字（token/金幣/圖騰/運氣 獲得回饋）---

# 快照當前雙方各色資源計數（行動前於 _do 呼叫）。
func _snapshot_resources() -> Dictionary:
	return {
		"luck": _core.players_luck.duplicate(),
		"token": _core.players_token.duplicate(),
		"totem": _core.players_totem.duplicate(),
		"coin": _core.players_coin.duplicate(),
	}


# 計算資源正向變化（純函式，供 headless 測）。回傳 [{kind, owner, delta}]（僅 delta>0）。
static func resource_deltas(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for kind: String in ["luck", "token", "totem", "coin"]:
		var b: Dictionary = before.get(kind, {})
		var a: Dictionary = after.get(kind, {})
		for owner: String in ["player1", "player2"]:
			var d: int = int(a.get(owner, 0)) - int(b.get(owner, 0))
			if d > 0:
				out.append({"kind": kind, "owner": owner, "delta": d})
	return out


# 依 _do 前的快照比對，對正向資源變化飄字。瞬時模式或 HUD 未建時只清快照不演出。
func _flush_resource_feedback() -> void:
	if _res_snapshot.is_empty():
		return
	var deltas := resource_deltas(_res_snapshot, _snapshot_resources())
	_res_snapshot = {}
	if _instant or not _ui_built or _hud == null or _res_label == null:
		return
	var slot := 0
	for d: Dictionary in deltas:
		_float_resource(d["kind"], d["owner"], d["delta"], slot)
		slot += 1


func _float_resource(kind: String, owner: String, delta: int, slot: int) -> void:
	var info: Dictionary = RES_KINDS.get(kind, {})
	var code: String = info.get("code", "")
	var col: Color = _db.color_rgb(code) if code != "" else Color.WHITE
	var who := "P1" if owner == "player1" else "P2"
	var l := Label.new()
	l.text = "%s +%d %s" % [who, delta, String(info.get("label", kind))]
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 50
	_hud.add_child(l)
	var base: Vector2 = _res_label.global_position + Vector2(150, 4 + slot * 22)
	l.global_position = base
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", base + Vector2(0, -26), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)


func _counts_text(cur: String) -> String:
	var p: PlayerState = _core.get_player(cur)
	var lines: Array = [
		"── 當前玩家可用 ──",
		"攻擊次數：%d" % _core.number_of_attacks[cur],
		"移動次數：%d" % _core.number_of_movings[cur],
		"治療次數：%d" % _core.number_of_heals[cur],
		"方塊次數：%d" % _core.number_of_cubes[cur],
		"牌庫：%d　棄牌：%d　手牌：%d" % [p.draw_pile.size(), p.discard_pile.size(), p.hand.size()],
	]
	if _placing_index >= 0 and _placing_index < p.hand.size():
		lines.append("放置中：%s（點空格放置）" % p.hand[_placing_index])
	if _turn_timer.running:
		lines.append("⏳ 回合剩餘：%d 秒" % _turn_timer.remaining_seconds())
	return "\n".join(lines)


# D19 手牌公開（P12-2）：己方（當前操作方）渲染為可點手牌列、對手渲染為唯讀公開列。
# hot-seat 換手時因每次 _refresh_hud 都以 cur/對手重建，兩列內容自然互換；
# 單人對戰對手＝AI（其手牌亦公開）；回放模式兩列同時顯示（bottom 為當前 replay 玩家）。
func _rebuild_hand(cur: String) -> void:
	# 旁觀＝雙方手牌皆唯讀（無可點列）；本機/對戰參與者＝當前操作方可點、對手唯讀（D19，P12-2）。
	var interactive := not (_is_net and _net_spectator)
	_rebuild_hand_into(_hand_box, cur, interactive)
	var opp: String = "player2" if cur == "player1" else "player1"
	_rebuild_hand_into(_opponent_hand_box, opp, false)


# 把指定玩家手牌渲染到指定容器。
# interactive=true：可點列（放置/出牌/升級高亮，pressed → _on_hand_pressed）。
# interactive=false：唯讀列（disabled 鈕＝點擊無作用；派別色標示；懸停 tooltip 顯示名稱＋提示）。
func _rebuild_hand_into(container: Container, player_name: String, interactive: bool) -> void:
	if container == null:
		return
	# 用 queue_free（非 free）：手牌按鈕的 pressed 信號會觸發本重建，emit 期間該按鈕被鎖定，
	# 立即 free 會報「Object is locked」。queue_free 延到本幀 idle 釋放（繪製前已清，無殘影）。
	for c in container.get_children():
		c.queue_free()
	var hand: Array = _core.get_player(player_name).hand
	for i in hand.size():
		var card: String = hand[i]
		var base_name: String = card.trim_suffix(" (+)")
		var info: Dictionary = _db.text(base_name)
		var label_text: String = String(info.get("name", base_name))
		if card.ends_with(" (+)"):
			label_text += "＋"
		# 派別色（兩列共用）：手牌全為公開資訊，己方與對手皆以派別色標示卡名。
		var code: String = _db.color_code_of(base_name)
		var col: Color = _db.color_rgb(code) if code != "" else Color.WHITE
		var b := Button.new()
		if interactive:
			b.text = "%s\n%s" % [label_text, card]
			b.custom_minimum_size = Vector2(96, 64)
			b.add_theme_font_size_override("font_size", 12)
			if code != "":
				# 各互動態都套派別色，避免 hover/pressed 時字色跳回預設。
				for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
					b.add_theme_color_override(state, col)
			if i == _placing_index:
				b.modulate = Color(1, 1, 0.5)
			b.pressed.connect(_on_hand_pressed.bind(i))
		else:
			# 唯讀公開列：只顯示名稱＋派別色；disabled 保證點擊無作用（樣式亦與可點列區別）。
			b.text = label_text
			b.custom_minimum_size = Vector2(78, 48)
			b.add_theme_font_size_override("font_size", 11)
			b.disabled = true
			if code != "":
				b.add_theme_color_override("font_disabled_color", col)
			b.tooltip_text = "%s\n%s" % [String(info.get("name", base_name)), String(info.get("hint", ""))]
		container.add_child(b)


# ---------------- 勝負畫面 ----------------

func _show_win() -> void:
	var w: int = _core.winner()
	var who: String = "先手 P1" if w == 0 else ("後手 P2" if w == 1 else "平手")
	_win_label.text = "%s 獲勝！\n最終分數 %d" % [who, _core.score]
	# P11-2：非回放的對局結束時，把紀錄存到 user://replays/（供終局畫面「回放本局」與主選單載入）。
	# is_inside_tree 守：headless 場景測試 instantiate 但不進場景樹，不落檔（避免測試污染 user://）。
	if is_inside_tree() and _replay == null and _recorder != null and _saved_replay_path == "":
		_saved_replay_path = ReplayLog.new_path()
		ReplayLog.save_to_file(_recorder, _saved_replay_path)
	_win_panel.visible = true


func _hide_win() -> void:
	if _win_panel != null:
		_win_panel.visible = false


# ---------------- 小工具 ----------------

# 預設牌組（編輯器 F6 直接執行用；含 B/G/C/DKG 以顯示四種色資源列）。
func _default_deck_a() -> Array:
	return ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]


func _default_deck_b() -> Array:
	return ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]
