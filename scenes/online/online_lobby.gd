# P12-7 大廳與房間 UI（見 docs/rebuild/10_連線版本.md §5，決策 D18）。
# 主選單「線上對戰」→ 連線設定（暱稱/位址/埠，存 settings 記住上次）→ 大廳（公開房列表＋
# 鎖標記＋人數/觀戰數、重新整理、房碼加入）→ 建房面板 → 房內畫面（席位/就緒/房碼/延遲/開始）。
#
# 職責界線（D1/§4）：本場景只是「大廳/房間的表現層薄殼」——持有一顆 NetClient（唯一 ENet
# 建立仍集中於 NetTransport 工廠，Steam 之路 §9.5）、把 NetClient 信號翻成面板更新、把玩家
# 操作翻成大廳/房間請求。權威永遠在 server。連線對戰畫面（收快照/事件播動畫）為後續任務接入。
#
# 編輯器化（08 §2）：靜態 UI 骨架宣告於 online_lobby.tscn，本腳本以 `%唯一名稱` 綁定既有節點。
# headless 可測：面板切換、房列表填充、房態套用、欄位驗證、拒絕原因文字皆為純方法（不需連線）；
# 實際連線流程屬【人工】跨機測（見 06 P12-7 驗收）。
extends Node2D

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
# P12-12：連線對戰畫面以「子場景嵌入本大廳」方式進場（不 change_scene；NetClient 全程存活，
# @rpc 路徑鐵則見 10 §11.2-1/2）。開戰時 instantiate battle、隱藏大廳 UI；離開/終局回房再釋放。
const BattleScene := preload("res://scenes/battle/battle.tscn")
# P12-13：連線選秀畫面同樣以子場景嵌入本大廳（不 change_scene；draft→battle 由開局快照切換）。
const DraftScene := preload("res://scenes/draft/draft.tscn")
# P12-15：連線終局統計畫面同樣以子場景嵌入本大廳（對戰結束後 battle→end_game；再戰/回房再釋放）。
const EndGameScene := preload("res://scenes/end_game/end_game.tscn")
# P14-3：房間清單列的樣式抽成 item 模板場景（美術可單開檔案調樣式）。
const RoomRowScene := preload("res://scenes/online/room_row_button.tscn")
# 內建預設伺服器位址（settings 可手動改，記住上次）。P12-11 部署時改為使用者主機固定 IP。
const DEFAULT_HOST := "127.0.0.1"
# 心跳間隔（秒）：連線後週期 ping 量 RTT 更新延遲顯示（§3）。
const PING_INTERVAL := 2.0
# P12-16 斷線重連 UX（§8/§11.2-8）：退避重試間隔（秒）與最大次數（逾則放棄回連線設定）。
const RECONNECT_INTERVAL := 2.0
const MAX_RECONNECT_ATTEMPTS := 8

# UI 狀態（面板切換）。
const UI_CONNECT := "connect"   # 連線設定
const UI_LOBBY := "lobby"       # 大廳（房列表）
const UI_CREATE := "create"     # 建房表單
const UI_ROOM := "room"         # 房內
const UI_RECONNECT := "reconnect"   # P12-16：斷線重連遮罩（自動帶 token 退避重試）

var _bound: bool = false
var _client: NetClient = null
var _my_id: int = 0
var _server_info: Dictionary = {}
var _current_room: Dictionary = {}
var _ui_state: String = UI_CONNECT
var _ping_accum: float = 0.0
# P12-16 斷線重連狀態：重連中旗標、席位 token、退避倒數、已試次數；連線參數（供重連沿用）。
var _reconnecting: bool = false
var _reconnect_token: String = ""
var _reconnect_accum: float = 0.0
var _reconnect_attempts: int = 0
var _conn_host: String = ""
var _conn_port: int = 0
var _conn_nick: String = ""
# P12-12：進行中的連線對戰子場景（null＝未在對戰畫面）。
var _battle_scene: Node = null
# P12-13：進行中的連線選秀子場景（null＝未在選秀畫面）。
var _draft_scene: Node = null
# P12-15：終局統計子場景（null＝未在終局畫面）。
var _end_scene: Node = null

# 節點（於 _bind_nodes 綁定）。
var _msg_label: Label
var _connect_panel: Panel
var _lobby_panel: Panel
var _create_panel: Panel
var _room_panel: Panel
var _reconnect_panel: Panel     # P12-16：斷線重連遮罩
var _reconnect_status: Label
var _room_list: VBoxContainer


func _ready() -> void:
	_bind_nodes()


# 安全網：NetClient 現掛在真正的樹根（見 _make_client 註解），不再隨本場景節點自動釋放——
# 場景以任何方式離開樹（意外路徑／未來新增的離開流程）都確保連線與 peer 節點一併清掉。
# 正常的「回主選單」已在 _on_back_to_menu 顯式呼叫過，這裡重複呼叫是安全的（_teardown_client 冪等）。
func _exit_tree() -> void:
	_teardown_client()


func _bind_nodes() -> void:
	if _bound:
		return
	_bound = true

	_msg_label = %MsgLabel
	_connect_panel = %ConnectPanel
	_lobby_panel = %LobbyPanel
	_create_panel = %CreatePanel
	_room_panel = %RoomPanel
	_reconnect_panel = %ReconnectPanel
	_reconnect_status = %ReconnectStatus
	_room_list = %RoomList

	# --- 連線設定面板：欄位帶入上次設定 ---
	var s := SettingsStore.load_settings()
	# P12-21：暱稱從未填過（預設空字串）時給一個「玩家NNNN」預設，避免空暱稱進 server
	# 導致房內/對戰顯示退回裸 peer id（實機「對手 #948868441」）。使用者可直接改寫。
	var saved_nick := String(s.get("net_nickname", ""))
	(%NicknameEdit as LineEdit).text = saved_nick if not saved_nick.is_empty() else default_nickname()
	var host := String(s.get("net_host", DEFAULT_HOST))
	(%HostEdit as LineEdit).text = host if not host.is_empty() else DEFAULT_HOST
	(%PortEdit as LineEdit).text = str(int(s.get("net_port", NetTransport.DEFAULT_PORT)))
	(%ConnectBtn as Button).pressed.connect(_on_connect)
	(%ConnectBackBtn as Button).pressed.connect(_on_back_to_menu)

	# --- 大廳面板 ---
	(%RefreshBtn as Button).pressed.connect(_on_refresh)
	(%CreateRoomBtn as Button).pressed.connect(_on_open_create)
	(%JoinBtn as Button).pressed.connect(_on_join_by_code)
	(%DisconnectBtn as Button).pressed.connect(_on_disconnect)

	# --- 建房面板 ---
	(%CreateConfirmBtn as Button).pressed.connect(_on_create_confirm)
	(%CreateCancelBtn as Button).pressed.connect(_on_create_cancel)

	# --- 房內面板 ---
	(%ReadyBtn as Button).pressed.connect(_on_toggle_ready)
	(%StartBtn as Button).pressed.connect(_on_start)
	(%LeaveBtn as Button).pressed.connect(_on_leave_room)

	# --- 斷線重連遮罩（P12-16）---
	(%ReconnectGiveUpBtn as Button).pressed.connect(_on_reconnect_give_up)

	_show_state(UI_CONNECT)
	_msg_label.text = ""


# ---------------- UI 狀態切換 ----------------

func _show_state(state: String) -> void:
	_ui_state = state
	_connect_panel.visible = state == UI_CONNECT
	_lobby_panel.visible = state == UI_LOBBY
	_create_panel.visible = state == UI_CREATE
	_room_panel.visible = state == UI_ROOM
	if _reconnect_panel != null:
		_reconnect_panel.visible = state == UI_RECONNECT


func set_message(text: String) -> void:
	if _msg_label != null:
		_msg_label.text = text


# ---------------- 連線 ----------------

func _on_connect() -> void:
	var nickname := (%NicknameEdit as LineEdit).text.strip_edges()
	if nickname.is_empty():
		# P12-21：使用者清空欄位時也補預設——server 端 names 永不為空字串（否則對手看到裸 peer id）。
		nickname = default_nickname()
		(%NicknameEdit as LineEdit).text = nickname
	var host := (%HostEdit as LineEdit).text.strip_edges()
	if host.is_empty():
		host = DEFAULT_HOST
	var port := int((%PortEdit as LineEdit).text)
	if port <= 0:
		port = NetTransport.DEFAULT_PORT
	_persist_net_settings(nickname, host, port)
	# P12-16：記住連線參數，供斷線後自動重連沿用（暱稱/位址/埠）。
	_conn_host = host
	_conn_port = port
	_conn_nick = nickname

	# 開新連線前先清掉舊的。
	_teardown_client()
	_client = _make_client(nickname)
	var r: Dictionary = _client.start(host, port, NetMessage.INTENT_PLAY, nickname)
	if not r["ok"]:
		(%ConnectStatus as Label).text = "無法建立連線：%s" % r["error"]
		_teardown_client()
		return
	(%ConnectStatus as Label).text = "連線中… %s" % NetTransport.endpoint(host, port)


# 建立並掛上 NetClient（in-tree 才能收送 @rpc）；連接全部信號。
# **掛在真正的樹根 `get_tree().root`（不是 `self`＝OnlineLobby 場景節點）**：伺服器的 NetPeer 是
# `/root` 的直接子節點，RPC 定址採「節點路徑相對於 MultiplayerAPI 根」，用戶端預設 API 的根即
# `/root`——若掛在場景節點下，相對路徑會變成 "OnlineLobby/NetPeer"，與伺服器對不上，RPC 會被
# 判定為 "Node not found"（P12-11 實機部署發現的 bug；見 net_peer_base.gd 開頭的路徑一致性說明）。
func _make_client(_nickname: String) -> NetClient:
	var c := NetClient.new()
	c.name = NetPeerBase.PEER_NODE_NAME   # 兩端同名，@rpc 路徑一致（見 NetPeerBase）
	get_tree().root.add_child(c)
	c.welcomed.connect(_on_welcomed)
	c.rejected.connect(_on_rejected)
	c.connection_failed.connect(_on_connection_failed)
	c.server_disconnected.connect(_on_server_disconnected)
	c.room_list_received.connect(_on_room_list_received)
	c.room_updated.connect(_on_room_updated)
	c.room_closed.connect(_on_room_closed)
	c.lobby_error.connect(_on_lobby_error)
	c.rtt_measured.connect(_on_rtt_measured)
	c.draft_updated.connect(_on_draft_updated)
	c.draft_rejected.connect(_on_draft_rejected)
	c.snapshot_received.connect(_on_snapshot_received)
	c.game_over.connect(_on_game_over)
	c.replay_received.connect(_on_replay_received)   # P12-18：終局回放下載
	return c


func _teardown_client() -> void:
	_exit_draft()    # 先釋放選秀/對戰/終局子場景（斷開其對 client 的連結），再關 client
	_exit_battle()
	_exit_end_game()
	if _client != null:
		_client.stop()
		_client.queue_free()
		_client = null
	_my_id = 0
	_server_info = {}
	_current_room = {}
	_reconnecting = false   # P12-16：完整清連線＝退出重連狀態


func _process(delta: float) -> void:
	# P12-16：重連中——退避倒數到 → 發起下一次帶 token 重連嘗試（不量 RTT）。
	if _reconnecting:
		_reconnect_accum += delta
		if _reconnect_accum >= RECONNECT_INTERVAL:
			_reconnect_accum = 0.0
			_reconnect_attempt()
		return
	# 連線後週期心跳量 RTT（更新延遲顯示）。未連線 → _client 為 null，headless 不觸發。
	if _client == null or not _client.is_welcomed():
		return
	_ping_accum += delta
	if _ping_accum >= PING_INTERVAL:
		_ping_accum = 0.0
		_client.ping()


# ---------------- NetClient 信號回呼 ----------------

func _on_welcomed(info: Dictionary) -> void:
	_my_id = int(info.get("peer_id", 0))
	_server_info = info
	(%LobbyServerLabel as Label).text = "已連線 · 遊戲版本 %s · 平衡 %s" % [
		String(info.get("game_version", "?")), String(info.get("data_version", "?"))]
	# P12-16：重連成功——不回大廳列表，改由 server 的 catchup（房態＋快照/選秀 view）自動把玩家
	# 帶回對戰/選秀子場景或房內面板續玩（§11.2-8）。清重連狀態、隱藏遮罩。
	if _reconnecting:
		_reconnecting = false
		_reconnect_attempts = 0
		set_message("已重新連線，正在恢復…")
		return
	set_message("")
	_show_state(UI_LOBBY)
	_client.list_rooms()


func _on_rejected(reason: String) -> void:
	# P12-16：重連嘗試遭握手層拒絕（版本閘等）＝無法恢復 → 放棄重連、退回連線設定。
	if _reconnecting:
		_fail_reconnect(reason_text(reason))
		return
	# 版本閘等握手層拒絕：給明確訊息並退回連線設定。
	(%ConnectStatus as Label).text = reason_text(reason)
	_teardown_client()
	_show_state(UI_CONNECT)


func _on_connection_failed() -> void:
	# P12-16：重連嘗試連不上 → 退避後再試（不回連線設定）。
	if _reconnecting:
		_schedule_reconnect_retry()
		return
	(%ConnectStatus as Label).text = "連不上伺服器（請確認位址／埠與伺服器是否運行）。"
	_teardown_client()
	_show_state(UI_CONNECT)


# P12-16：與伺服器連線中斷（§8/§11.2-8）。
# 若持有席位 token 且原在房內／對局中 → 進入自動重連（帶 token 退避重試）；否則回連線設定。
# 重連嘗試自身再度斷線 → 退避後續試（不重置整個流程）。
func _on_server_disconnected() -> void:
	if _reconnecting:
		_schedule_reconnect_retry()
		return
	if _can_reconnect():
		var token := _client.seat_token()
		_release_client_for_reconnect()   # 於 client 自身信號回呼中安全釋放（queue_free）
		_begin_reconnect(token)
		return
	set_message("與伺服器的連線已中斷。")
	_teardown_client()
	_show_state(UI_CONNECT)


# ---------------- 斷線重連（P12-16，見 10 §8/§11.2-8）----------------

# 可否自動重連：持有席位 token（只有玩家有；旁觀者斷線＝直接移除，§7）且原在某房。
func _can_reconnect() -> bool:
	return _client != null and not _client.seat_token().is_empty() and not _current_room.is_empty()


# 進入重連（純狀態；不碰 client——client 由 _on_server_disconnected 於呼叫前釋放）。
# 顯示重連遮罩，_process 退避倒數到即發首次帶 token 重連嘗試。headless 可直接測此狀態轉換。
func _begin_reconnect(token: String) -> void:
	_reconnect_token = token
	_exit_battle()    # 釋放子場景（避免其連到即將釋放的舊 client）；_current_room 保留供恢復判斷
	_exit_draft()
	_exit_end_game()
	_reconnecting = true
	_reconnect_attempts = 0
	_reconnect_accum = RECONNECT_INTERVAL   # 下一幀即發首次嘗試
	_show_state(UI_RECONNECT)
	_update_reconnect_status()


# 釋放舊 client（於自身信號回呼中安全＝queue_free，不即時 free）。
func _release_client_for_reconnect() -> void:
	if _client != null:
		_client.stop()
		_client.queue_free()
		_client = null


# 發起一次帶 token 的重連嘗試（runtime；建立新 client 掛 /root，@rpc 路徑鐵則不變）。
func _reconnect_attempt() -> void:
	_reconnect_attempts += 1
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		_fail_reconnect("重新連線失敗（多次嘗試後仍無法連上伺服器）。")
		return
	_update_reconnect_status()
	_release_client_for_reconnect()
	_client = _make_client(_conn_nick)
	var r: Dictionary = _client.start(_conn_host, _conn_port, NetMessage.INTENT_PLAY,
		_conn_nick, _reconnect_token)
	if not r["ok"]:
		_release_client_for_reconnect()   # 開 peer 失敗 → 等下輪退避再試


# 一次重連嘗試失敗（連不上／連上又斷）：釋放 client、重置退避倒數，_process 到點續試。
func _schedule_reconnect_retry() -> void:
	_release_client_for_reconnect()
	_reconnect_accum = 0.0
	_update_reconnect_status()


# 放棄重連（逾次／握手拒／席位逾時）：回連線設定並顯示原因。
func _fail_reconnect(msg: String) -> void:
	_reconnecting = false
	_teardown_client()
	_show_state(UI_CONNECT)
	(%ConnectStatus as Label).text = msg


func _update_reconnect_status() -> void:
	if _reconnect_status == null:
		return
	var suffix := "（第 %d 次嘗試）" % _reconnect_attempts if _reconnect_attempts > 0 else ""
	_reconnect_status.text = "與伺服器的連線中斷，正在自動重新連線…%s" % suffix


# 「放棄，回主選單」按鈕：中止重連、關連線、回主選單。
func _on_reconnect_give_up() -> void:
	_reconnecting = false
	_on_back_to_menu()


func _on_room_list_received(list: Array) -> void:
	populate_room_list(list)


func _on_room_updated(room: Dictionary) -> void:
	# P12-16：收到房態＝重連成功的恢復信號 → 清重連狀態（catchup 快照/view 隨後重建子場景）。
	if _reconnecting:
		_reconnecting = false
		_reconnect_attempts = 0
		set_message("已重新連線。")
	apply_room_state(room)
	# 對戰/選秀/終局子場景進行中：只更新房態資料（供席位查詢＋觀戰人數＋對手 held），不切回房內面板。
	# （終局子場景在場時，玩家可能還在看統計；房態＝ended/waiting 由玩家自行按「再來一局／回房間」離開。）
	var spec_count := (room.get("spectators", []) as Array).size()
	if _battle_scene != null:
		_battle_scene.set_spectator_count(spec_count)
		_forward_opponent_held(_battle_scene)
		_battle_scene.set_opponent_name(_opponent_display_name())
	elif _draft_scene != null:
		_draft_scene.set_spectator_count(spec_count)
		_forward_opponent_held(_draft_scene)
		_draft_scene.set_opponent_name(_opponent_display_name())
	elif _end_scene != null:
		pass
	else:
		_show_state(UI_ROOM)


# P12-16：把「對方席位斷線等待重連（held）」轉入活躍子場景顯示（對手／旁觀時任一非我席位）。
func _forward_opponent_held(scene: Node) -> void:
	var my := _my_seat()
	var held_map: Dictionary = _current_room.get("held", {})
	var hr_map: Dictionary = _current_room.get("hold_remaining", {})
	var held := false
	var remaining := 0
	for seat in RoomManager.SEATS:
		if seat == my:
			continue
		if bool(held_map.get(seat, false)):
			held = true
			remaining = maxi(remaining, int(hr_map.get(seat, 0)))
	scene.set_opponent_held(held, remaining)


func _on_room_closed(_room_id: String, _reason: String) -> void:
	set_message("房間已解散。")
	_exit_draft()
	_exit_battle()
	_exit_end_game()
	_current_room = {}
	_show_state(UI_LOBBY)
	if _client != null:
		_client.list_rooms()


func _on_lobby_error(reason: String) -> void:
	# P12-16：重連時 server 回 bad_token（席位保留已逾時、token 失效）＝無法恢復席位 → 放棄重連。
	if _reconnecting and reason == NetMessage.REASON_BAD_TOKEN:
		_fail_reconnect("重新連線失敗：席位保留已逾時，請重新加入房間。")
		return
	set_message(reason_text(reason))


func _on_rtt_measured(_peer_id: int, rtt_ms: int) -> void:
	(%LatencyLabel as Label).text = "延遲：%d ms（%s）" % [rtt_ms, _quality_text(rtt_ms)]
	# P12-17：對戰/選秀進行中→把 RTT/連線品質轉入子場景 HUD 顯示。
	if _battle_scene != null:
		_battle_scene.set_rtt(rtt_ms)
	elif _draft_scene != null:
		_draft_scene.set_rtt(rtt_ms)


# P12-17：RTT → 連線品質文字（純函式，供子場景 HUD 與大廳共用）。
static func _quality_text(rtt_ms: int) -> String:
	if rtt_ms < 80:
		return "良好"
	if rtt_ms < 160:
		return "普通"
	if rtt_ms < 300:
		return "偏高"
	return "不穩"


# P12-13 選秀狀態：首份選秀 view＝進場信號。尚未在選秀/對戰畫面 → 嵌入 draft 子場景並交棒；
# 已在畫面 → 後續 view 由子場景自身的 NetClient 連結渲染（此處不重複）。
func _on_draft_updated(draft: Dictionary) -> void:
	if _draft_scene == null and _battle_scene == null:
		_enter_draft(draft)


func _on_draft_rejected(reason: String, _message: String) -> void:
	set_message(reason_text(reason))


func _on_snapshot_received(snapshot: Dictionary) -> void:
	# P12-12/13：對戰開局快照＝進場信號。尚未在對戰畫面 → 嵌入 battle 子場景並交棒
	# （若正在選秀畫面則先釋放＝BP→對戰轉場）；已在對戰畫面 → 後續校正快照由子場景自身處理。
	if _battle_scene == null:
		_exit_draft()
		_enter_battle(snapshot)


func _on_game_over(info: Dictionary) -> void:
	# P12-15：對戰進行中＝由 battle 子場景播完動畫後 emit net_game_finished → _on_net_game_finished
	# 開終局統計（此處不動，避免打斷結尾動畫）。無對戰/選秀子場景＝旁觀者於終局後才加入
	# （catchup 直送 game_over，無 battle 場景）→ 直接開終局統計看勝負（P12-9(C)）。
	if _battle_scene == null and _draft_scene == null and _end_scene == null:
		_enter_end_game_from_info(info)


# ---------------- 連線對戰子場景（P12-12，見 10 §11.2-2）----------------

# 嵌入 battle 子場景（隱藏大廳 UI）。先 boot_net 再 add_child：boot_net 已建顯示鏡像 core，
# 隨後 add_child 觸發的 _ready 見 _core 非空 → 不會誤啟動本地預設對局。
func _enter_battle(opening_snapshot: Dictionary) -> void:
	if _battle_scene != null:
		return
	_battle_scene = BattleScene.instantiate()
	_battle_scene.boot_net(_client, _my_seat(), opening_snapshot, _my_seat() == "")
	# P12-15：對戰結束（動畫播完）後由 battle emit → 開終局統計（釋放 battle、嵌入 end_game）。
	_battle_scene.net_game_finished.connect(_on_net_game_finished)
	add_child(_battle_scene)
	_battle_scene.set_spectator_count((_current_room.get("spectators", []) as Array).size())
	_hide_lobby_ui()


# 嵌入 draft 子場景（隱藏大廳 UI）。先 boot_net 再 add_child（boot_net 已建顯示鏡像 _state，
# 隨後 add_child 觸發的 _ready 見 _state 非空 → 不會誤啟動本地預設選秀）。
func _enter_draft(opening_view: Dictionary) -> void:
	if _draft_scene != null or _battle_scene != null:
		return
	_draft_scene = DraftScene.instantiate()
	_draft_scene.boot_net(_client, _my_seat(), opening_view, _my_seat() == "")
	add_child(_draft_scene)
	_draft_scene.set_spectator_count((_current_room.get("spectators", []) as Array).size())
	_hide_lobby_ui()


# 釋放選秀子場景、恢復大廳 UI（離開/斷線/房解散／BP→對戰轉場時）。
func _exit_draft() -> void:
	if _draft_scene != null:
		_draft_scene.queue_free()
		_draft_scene = null
	if _msg_label != null:
		_msg_label.visible = true


# 釋放對戰子場景、恢復大廳 UI（離開/斷線/房解散時）。
func _exit_battle() -> void:
	if _battle_scene != null:
		_battle_scene.queue_free()
		_battle_scene = null
	if _msg_label != null:
		_msg_label.visible = true


# ---------------- 連線終局統計子場景（P12-15，見 10 §11.2-7）----------------

# 對戰子場景 emit net_game_finished（動畫播完）→ 釋放 battle、嵌入 end_game 子場景。
func _on_net_game_finished(winner: int, score: int, win_threshold: int,
		score_history: Array, stats: Dictionary, reason: String) -> void:
	_enter_end_game(winner, score, win_threshold, score_history, stats, reason)


# 旁觀者於終局後才加入（catchup 直送 game_over，無 battle 場景）→ 由 game_over payload 開終局統計。
func _enter_end_game_from_info(info: Dictionary) -> void:
	var snap: Dictionary = info.get("snapshot", {})
	var winner := _winner_name_to_int(String(info.get("winner", "")))
	_enter_end_game(winner, int(snap.get("score", 0)), GameConfig.WIN_THRESHOLD_DEFAULT,
		snap.get("score_history", []), snap.get("stats", {}), String(info.get("reason", "")))


# 嵌入 end_game 子場景（隱藏大廳 UI）。釋放對戰/選秀子場景後接手。旁觀者無「再來一局」。
func _enter_end_game(winner: int, score: int, win_threshold: int,
		score_history: Array, stats: Dictionary, reason: String) -> void:
	_exit_battle()
	_exit_draft()
	if _end_scene != null:
		return
	_end_scene = EndGameScene.instantiate()
	_end_scene.boot_net(winner, score, win_threshold, score_history, stats, _my_seat() == "", reason)
	_end_scene.net_rematch.connect(_on_end_rematch)
	_end_scene.net_back_to_room.connect(_on_end_back_to_room)
	_end_scene.net_download_replay.connect(_on_end_download_replay)   # P12-18
	add_child(_end_scene)
	_hide_lobby_ui()


# 釋放終局子場景、恢復大廳 UI（回房/再戰/離開/斷線時）。
func _exit_end_game() -> void:
	if _end_scene != null:
		_end_scene.queue_free()
		_end_scene = null
	if _msg_label != null:
		_msg_label.visible = true


# 終局「再來一局」：送 rematch（server 重開回 waiting＋本席就緒）→ 釋放終局子場景、回房內面板。
# 雙方皆按＝兩席就緒 → 房主按開始 → 新一局（同成員、新 seed）。
func _on_end_rematch() -> void:
	_exit_end_game()
	if _client != null:
		_client.rematch()
	_show_state(UI_ROOM)


# 終局「回房間」：釋放終局子場景、回房內面板（房態＝ended，可於房內按「再來一局」或離開）。
func _on_end_back_to_room() -> void:
	_exit_end_game()
	_show_state(UI_ROOM)


# P12-18：終局「下載本局回放」→ 向 server 索取（僅房態 ended 受理）。
func _on_end_download_replay() -> void:
	if _client != null:
		_client.request_replay()


# 收到 server 回放（JSONL，含 seed）→ 存到本地 user://replays/，回報終局子場景。
# 觀看沿用既有「主選單→回放紀錄」（P11-2）；net 子場景不 change_scene。
func _on_replay_received(jsonl: String) -> void:
	var log: ReplayLog = ReplayLog.from_jsonl(jsonl)
	var ok := false
	if log != null and not (log.actions as Array).is_empty():
		ok = ReplayLog.save_to_file(log, ReplayLog.new_path())
	if _end_scene != null:
		_end_scene.set_replay_saved(ok)


func _hide_lobby_ui() -> void:
	for panel in [_connect_panel, _lobby_panel, _create_panel, _room_panel]:
		if panel != null:
			(panel as Control).visible = false
	if _msg_label != null:
		_msg_label.visible = false


# ---------------- 大廳操作 ----------------

func _on_refresh() -> void:
	if _client != null:
		_client.list_rooms()


func _on_open_create() -> void:
	(%CreateNameEdit as LineEdit).text = ""
	(%CreatePasswordEdit as LineEdit).text = ""
	(%CreateLockedCheck as CheckBox).button_pressed = false
	(%CreateSpectateCheck as CheckBox).button_pressed = true
	(%CreateStatus as Label).text = ""
	_show_state(UI_CREATE)


func _on_join_by_code() -> void:
	var raw := (%JoinCodeEdit as LineEdit).text
	var err := validate_join_code(raw)
	if not err.is_empty():
		set_message(err)
		return
	var code := normalize_room_code(raw)
	var password := (%JoinPasswordEdit as LineEdit).text
	var spectate := (%JoinSpectateCheck as CheckBox).button_pressed
	set_message("")
	if _client != null:
		_client.join_room(code, password, spectate)


# 點列表中的房間 → 帶入房碼（上鎖房提示補密碼），使用者按「加入」送出。
func _prefill_join(room: Dictionary) -> void:
	(%JoinCodeEdit as LineEdit).text = String(room.get("room_id", ""))
	if bool(room.get("locked", false)):
		set_message("此房間已上鎖，請於下方輸入密碼後加入。")
		(%JoinPasswordEdit as LineEdit).grab_focus()
	else:
		set_message("")


func _on_disconnect() -> void:
	_teardown_client()
	_show_state(UI_CONNECT)
	(%ConnectStatus as Label).text = "已中斷連線。"


# ---------------- 建房 ----------------

func _on_create_confirm() -> void:
	var locked := (%CreateLockedCheck as CheckBox).button_pressed
	var password := (%CreatePasswordEdit as LineEdit).text
	var err := create_error(locked, password)
	if not err.is_empty():
		(%CreateStatus as Label).text = err
		return
	var name := (%CreateNameEdit as LineEdit).text
	var allow_spec := (%CreateSpectateCheck as CheckBox).button_pressed
	if _client != null:
		_client.create_room(name, locked, password, allow_spec)
	# 房建立成功後 server 會廣播 room_state → _on_room_updated 切到房內畫面。


func _on_create_cancel() -> void:
	_show_state(UI_LOBBY)


# ---------------- 房內 ----------------

func _on_toggle_ready() -> void:
	if _client == null:
		return
	var seat := _my_seat()
	if seat.is_empty():
		return   # 旁觀者無就緒
	# P12-15：終局房內按「再來一局」＝送 rematch（server 重開回 waiting＋本席就緒）。
	if String(_current_room.get("state", "")) == RoomManager.STATE_ENDED:
		_client.rematch()
		return
	var ready := bool((_current_room.get("ready", {}) as Dictionary).get(seat, false))
	_client.set_ready(not ready)


func _on_start() -> void:
	# P12-13 正式流程：房主開始 → 連線選秀（BP）→ 對戰。
	# 開發旗標 start_battle（跳過 BP、預設牌組）保留於 NetClient 供除錯，不再由 UI 觸發。
	if _client != null:
		_client.start_draft()


func _on_leave_room() -> void:
	if _client != null:
		_client.leave_room()
	_exit_draft()
	_exit_battle()
	_exit_end_game()
	_current_room = {}
	_show_state(UI_LOBBY)
	if _client != null:
		_client.list_rooms()


func _on_back_to_menu() -> void:
	_teardown_client()
	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_file(MENU_SCENE)


# ---------------- 純方法（headless 可測，不需連線）----------------

# 依 server member_view 更新房內面板（席位/就緒/房碼/旁觀數/開始鈕可用性）。
func apply_room_state(room: Dictionary) -> void:
	_current_room = room
	var seats: Dictionary = room.get("seats", {})
	var ready: Dictionary = room.get("ready", {})
	(%RoomTitle as Label).text = String(room.get("name", "房間"))
	(%RoomCodeLabel as Label).text = "房碼：%s（分享給朋友加入）" % String(room.get("room_id", ""))
	(%Seat1Label as Label).text = "P1：%s" % _seat_text(RoomManager.SEAT_P1, seats, ready)
	(%Seat2Label as Label).text = "P2：%s" % _seat_text(RoomManager.SEAT_P2, seats, ready)
	(%SpectatorLabel as Label).text = "旁觀：%d 人" % (room.get("spectators", []) as Array).size()

	var my_seat := _my_seat()
	var is_player := not my_seat.is_empty()
	var is_host := _my_id != 0 and _my_id == int(room.get("host_id", 0))
	var state := String(room.get("state", ""))
	var waiting := state == RoomManager.STATE_WAITING
	var ended := state == RoomManager.STATE_ENDED

	# P12-15：終局房（ended）ReadyBtn 變「再來一局」（送 rematch 重開＋就緒）；waiting 時為就緒切換。
	(%ReadyBtn as Button).visible = is_player and (waiting or ended)
	if is_player:
		if ended:
			(%ReadyBtn as Button).text = "再來一局"
			(%ReadyBtn as Button).disabled = false
		elif waiting:
			var my_ready := bool(ready.get(my_seat, false))
			(%ReadyBtn as Button).text = "取消就緒" if my_ready else "準備就緒"
			(%ReadyBtn as Button).disabled = false
	# 只有房主、雙方就位且皆就緒、且在等待中才可開戰。
	(%StartBtn as Button).visible = is_host
	(%StartBtn as Button).disabled = not (waiting and _both_ready(seats, ready))
	(%RoomStatus as Label).text = _room_status_text(room, is_player)


# 依大廳公開列表填充房間列（每列一個可點按鈕）；空則顯示提示。
func populate_room_list(rooms: Array) -> void:
	if _room_list == null:
		return
	# 立即 free（非 queue_free）：清空後 get_child_count 立刻歸零，重整時不殘留舊列；
	# 亦使 headless（無 idle 幀 flush 佇列）確定性、不留孤兒節點。
	for c in _room_list.get_children():
		c.free()
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "（目前沒有公開房間。可建立新房間，或用房碼加入。）"
		_room_list.add_child(empty)
		return
	for room: Dictionary in rooms:
		var b: Button = RoomRowScene.instantiate()   # 樣式在 item 場景
		b.text = _room_row_text(room)
		b.pressed.connect(_prefill_join.bind(room))
		_room_list.add_child(b)


# 房碼正規化：去空白、轉大寫（房碼字母表為大寫，見 RoomManager）。
static func normalize_room_code(code: String) -> String:
	return code.strip_edges().to_upper()


# 房碼欄位驗證：回傳錯誤訊息，合法則回空字串。
static func validate_join_code(code: String) -> String:
	var c := normalize_room_code(code)
	if c.is_empty():
		return "請輸入房碼。"
	if c.length() != RoomManager.CODE_LENGTH:
		return "房碼為 %d 碼。" % RoomManager.CODE_LENGTH
	for ch in c:
		if not RoomManager.CODE_ALPHABET.contains(ch):
			return "房碼含無效字元（僅限房碼字母表）。"
	return ""


# 建房欄位驗證：上鎖必須設定密碼。回傳錯誤訊息，合法則回空字串。
static func create_error(locked: bool, password: String) -> String:
	if locked and password.strip_edges().is_empty():
		return "上鎖房間需要設定密碼。"
	return ""


# 拒絕／錯誤原因常數 → 明確中文訊息（版本閘等，見 §3/§5）。
static func reason_text(reason: String) -> String:
	match reason:
		NetMessage.REASON_GAME_VERSION:
			return "遊戲版本不符，無法連線（請雙方更新到相同版本）。"
		NetMessage.REASON_DATA_VERSION:
			return "平衡資料版本不符，無法連線（請同步到相同資料版本）。"
		NetMessage.REASON_BAD_INTENT:
			return "連線意圖非法。"
		NetMessage.REASON_BAD_MESSAGE:
			return "訊息格式錯誤。"
		NetMessage.REASON_ALREADY_IN_ROOM:
			return "你已在一個房間內。"
		NetMessage.REASON_TOO_MANY_ROOMS:
			return "伺服器房間數已達上限，請稍後再試。"
		NetMessage.REASON_ROOM_NOT_FOUND:
			return "找不到房間（房碼錯誤或房間已解散）。"
		NetMessage.REASON_BAD_PASSWORD:
			return "房間密碼錯誤。"
		NetMessage.REASON_ROOM_FULL:
			return "房間已滿。"
		NetMessage.REASON_NO_SPECTATE:
			return "此房間未開放旁觀。"
		NetMessage.REASON_NOT_IN_ROOM:
			return "你目前不在任何房間內。"
		NetMessage.REASON_NOT_A_PLAYER:
			return "你不是玩家（旁觀者無法執行此操作）。"
		NetMessage.REASON_BAD_STATE:
			return "目前狀態無法執行此操作。"
		NetMessage.REASON_NOT_READY:
			return "雙方尚未就緒，無法開始。"
		NetMessage.REASON_NOT_DRAFTING:
			return "房間目前未在選秀中。"
		NetMessage.REASON_BAD_DRAFT_ACTION:
			return "選秀行動非法。"
		NetMessage.REASON_NOT_BATTLING:
			return "房間目前未在對戰中。"
		NetMessage.REASON_NOT_YOUR_TURN:
			return "還沒輪到你行動。"
		NetMessage.REASON_SPECTATOR_ACTION:
			return "旁觀者無法行動。"
		NetMessage.REASON_BAD_ACTION:
			return "行動非法。"
		NetMessage.REASON_NO_REPLAY:
			return "目前沒有可下載的回放（對局尚未結束或無紀錄）。"
		_:
			return "發生錯誤：%s" % reason


# ---------------- 內部小工具 ----------------

# 我在此房的席位（player1/player2）；旁觀或未入房回空字串。
func _my_seat() -> String:
	var seats: Dictionary = _current_room.get("seats", {})
	for seat in RoomManager.SEATS:
		if int(seats.get(seat, 0)) == _my_id and _my_id != 0:
			return seat
	return ""


func _seat_text(seat: String, seats: Dictionary, ready: Dictionary) -> String:
	var pid := int(seats.get(seat, 0))
	if pid == 0:
		# P12-16：held 席位（掉線等待重連）與真正空位區別顯示。
		if bool((_current_room.get("held", {}) as Dictionary).get(seat, false)):
			return "（斷線，等待重連…）"
		return "（空位）"
	var who := "你" if pid == _my_id else _peer_display_name(pid)
	var rd := "✓ 就緒" if bool(ready.get(seat, false)) else "… 未就緒"
	return "%s — %s" % [who, rd]


# P12-17：peer 顯示名＝暱稱（server 於房態附 `names`）。
# P12-21：保底不再顯示裸 peer id——空暱稱（或 server 版本過舊未送 `names`）改用短碼「玩家NNNN」。
func _peer_display_name(pid: int) -> String:
	return display_name_for(String((_current_room.get("names", {}) as Dictionary).get(str(pid), "")), pid)


# 新連線的預設暱稱（使用者可改寫）。P12-21：確保暱稱永不為空。
static func default_nickname() -> String:
	return "玩家%04d" % (randi() % 10000)


# 顯示名純函式（供測試）：有暱稱用暱稱；否則以 peer id 短碼保底，**不顯示裸 peer id**。
# 短碼取末四位，足以在房內區分兩人，且不像 `#948868441` 那樣難讀（實機截圖問題）。
static func display_name_for(nick: String, pid: int) -> String:
	var n := nick.strip_edges()
	return n if not n.is_empty() else "玩家%04d" % (absi(pid) % 10000)


# 我的對手席位的顯示名（供轉入子場景顯示）；無對手回空字串。
func _opponent_display_name() -> String:
	var my := _my_seat()
	var seats: Dictionary = _current_room.get("seats", {})
	for seat in RoomManager.SEATS:
		if seat == my:
			continue
		var pid := int(seats.get(seat, 0))
		if pid != 0:
			return _peer_display_name(pid)
	return ""


func _both_ready(seats: Dictionary, ready: Dictionary) -> bool:
	return int(seats.get(RoomManager.SEAT_P1, 0)) != 0 \
		and int(seats.get(RoomManager.SEAT_P2, 0)) != 0 \
		and bool(ready.get(RoomManager.SEAT_P1, false)) \
		and bool(ready.get(RoomManager.SEAT_P2, false))


func _room_status_text(room: Dictionary, is_player: bool) -> String:
	var state := String(room.get("state", ""))
	if not is_player:
		return "旁觀中"
	match state:
		RoomManager.STATE_WAITING:
			if _both_ready(room.get("seats", {}), room.get("ready", {})):
				return "雙方就緒，房主可開始。"
			return "等待雙方就緒…"
		RoomManager.STATE_DRAFTING:
			return "選秀中…"
		RoomManager.STATE_BATTLING:
			return "對戰進行中…"
		RoomManager.STATE_ENDED:
			return "對戰結束——按「再來一局」重開（雙方皆按），或離開房間。"
		_:
			return ""


# 席位名（player1/player2）→ 終局 winner int（-1 平／0 P1／1 P2；沿用 GameCore.winner()）。
func _winner_name_to_int(name: String) -> int:
	match name:
		"player1": return 0
		"player2": return 1
		_: return -1


func _room_row_text(room: Dictionary) -> String:
	var lock := "🔒 " if bool(room.get("locked", false)) else ""
	return "%s%s · %s · 玩家 %d/2 · 觀 %d/%d · [%s]" % [
		lock,
		String(room.get("room_id", "")),
		String(room.get("name", "房間")),
		int(room.get("player_count", 0)),
		int(room.get("spectator_count", 0)),
		int(room.get("spectator_limit", 0)),
		String(room.get("state", "")),
	]


# 存最近一次的連線設定（記住上次；並保留其他設定不被重置）。
func _persist_net_settings(nickname: String, host: String, port: int) -> void:
	var s := SettingsStore.load_settings()
	s["net_nickname"] = nickname
	s["net_host"] = host
	s["net_port"] = port
	SettingsStore.save_settings(s)
