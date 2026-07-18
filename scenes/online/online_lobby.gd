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
# 內建預設伺服器位址（settings 可手動改，記住上次）。P12-11 部署時改為使用者主機固定 IP。
const DEFAULT_HOST := "127.0.0.1"
# 心跳間隔（秒）：連線後週期 ping 量 RTT 更新延遲顯示（§3）。
const PING_INTERVAL := 2.0

# UI 狀態（面板切換）。
const UI_CONNECT := "connect"   # 連線設定
const UI_LOBBY := "lobby"       # 大廳（房列表）
const UI_CREATE := "create"     # 建房表單
const UI_ROOM := "room"         # 房內

var _bound: bool = false
var _client: NetClient = null
var _my_id: int = 0
var _server_info: Dictionary = {}
var _current_room: Dictionary = {}
var _ui_state: String = UI_CONNECT
var _ping_accum: float = 0.0

# 節點（於 _bind_nodes 綁定）。
var _msg_label: Label
var _connect_panel: Panel
var _lobby_panel: Panel
var _create_panel: Panel
var _room_panel: Panel
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
	_room_list = %RoomList

	# --- 連線設定面板：欄位帶入上次設定 ---
	var s := SettingsStore.load_settings()
	(%NicknameEdit as LineEdit).text = String(s.get("net_nickname", ""))
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
	(%StartBtn as Button).pressed.connect(_on_start_battle)
	(%LeaveBtn as Button).pressed.connect(_on_leave_room)

	_show_state(UI_CONNECT)
	_msg_label.text = ""


# ---------------- UI 狀態切換 ----------------

func _show_state(state: String) -> void:
	_ui_state = state
	_connect_panel.visible = state == UI_CONNECT
	_lobby_panel.visible = state == UI_LOBBY
	_create_panel.visible = state == UI_CREATE
	_room_panel.visible = state == UI_ROOM


func set_message(text: String) -> void:
	if _msg_label != null:
		_msg_label.text = text


# ---------------- 連線 ----------------

func _on_connect() -> void:
	var nickname := (%NicknameEdit as LineEdit).text.strip_edges()
	var host := (%HostEdit as LineEdit).text.strip_edges()
	if host.is_empty():
		host = DEFAULT_HOST
	var port := int((%PortEdit as LineEdit).text)
	if port <= 0:
		port = NetTransport.DEFAULT_PORT
	_persist_net_settings(nickname, host, port)

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
	return c


func _teardown_client() -> void:
	if _client != null:
		_client.stop()
		_client.queue_free()
		_client = null
	_my_id = 0
	_server_info = {}
	_current_room = {}


func _process(delta: float) -> void:
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
	set_message("")
	_show_state(UI_LOBBY)
	_client.list_rooms()


func _on_rejected(reason: String) -> void:
	# 版本閘等握手層拒絕：給明確訊息並退回連線設定。
	(%ConnectStatus as Label).text = reason_text(reason)
	_teardown_client()
	_show_state(UI_CONNECT)


func _on_connection_failed() -> void:
	(%ConnectStatus as Label).text = "連不上伺服器（請確認位址／埠與伺服器是否運行）。"
	_teardown_client()
	_show_state(UI_CONNECT)


func _on_server_disconnected() -> void:
	set_message("與伺服器的連線已中斷。")
	_teardown_client()
	_show_state(UI_CONNECT)


func _on_room_list_received(list: Array) -> void:
	populate_room_list(list)


func _on_room_updated(room: Dictionary) -> void:
	apply_room_state(room)
	_show_state(UI_ROOM)


func _on_room_closed(_room_id: String, _reason: String) -> void:
	set_message("房間已解散。")
	_current_room = {}
	_show_state(UI_LOBBY)
	if _client != null:
		_client.list_rooms()


func _on_lobby_error(reason: String) -> void:
	set_message(reason_text(reason))


func _on_rtt_measured(_peer_id: int, rtt_ms: int) -> void:
	if _ui_state == UI_ROOM:
		(%LatencyLabel as Label).text = "延遲：%d ms" % rtt_ms


# P12-8 選秀狀態：以房內狀態列即時反映階段/當前選手/雙方張數（BP 全公開）。
# 連線選秀畫面（可點選牌、非編輯方鎖定「對方選牌中」）於後續任務把 draft.tscn 接上 NetClient。
func _on_draft_updated(draft: Dictionary) -> void:
	if _ui_state != UI_ROOM:
		_show_state(UI_ROOM)
	var editor := String(draft.get("editor", ""))
	var picking := "你" if (editor != "" and editor == _my_seat()) else "對手"
	(%RoomStatus as Label).text = "選秀中：目前 %s 選牌 · P1 %d/12　P2 %d/12（連線選秀畫面將於後續任務接入）" % [
		picking, int(draft.get("player1_count", 0)), int(draft.get("player2_count", 0))]


func _on_draft_rejected(reason: String, _message: String) -> void:
	set_message(reason_text(reason))


func _on_snapshot_received(_snapshot: Dictionary) -> void:
	# P12-7 範圍到房間 UI 為止：對戰開局／校正快照先以狀態提示；連線對戰畫面於後續任務接入。
	(%RoomStatus as Label).text = "對戰開始（連線對戰畫面將於後續任務接入）。"


func _on_game_over(_info: Dictionary) -> void:
	(%RoomStatus as Label).text = "對戰結束。"


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
	var ready := bool((_current_room.get("ready", {}) as Dictionary).get(seat, false))
	_client.set_ready(not ready)


func _on_start_battle() -> void:
	if _client != null:
		_client.start_battle()   # 開發旗標：跳過 BP、預設牌組（正式 BP 走 P12-8）


func _on_leave_room() -> void:
	if _client != null:
		_client.leave_room()
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
	var waiting := String(room.get("state", "")) == RoomManager.STATE_WAITING

	(%ReadyBtn as Button).visible = is_player
	if is_player:
		var my_ready := bool(ready.get(my_seat, false))
		(%ReadyBtn as Button).text = "取消就緒" if my_ready else "準備就緒"
		(%ReadyBtn as Button).disabled = not waiting
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
		var b := Button.new()
		b.text = _room_row_text(room)
		b.custom_minimum_size = Vector2(560, 40)
		b.add_theme_font_size_override("font_size", 14)
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
		return "（空位）"
	var who := "你" if pid == _my_id else "對手 #%d" % pid
	var rd := "✓ 就緒" if bool(ready.get(seat, false)) else "… 未就緒"
	return "%s — %s" % [who, rd]


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
			return "對戰結束。"
		_:
			return ""


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
