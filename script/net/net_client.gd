# P12-3 用戶端端點（見 docs/rebuild/10_連線版本.md §3）。
# 職責（本任務範圍＝骨架）：連上伺服器、送握手（遊戲版本＋Balance.data_version()＋意圖／暱稱／
# 可選重連 token）、收 welcome/rejected、心跳量 RTT、轉發斷線。房間/對戰在 P12-6+ 擴充。
class_name NetClient
extends NetPeerBase

# 握手通過（payload＝server 的 welcome 內容）。
signal welcomed(info: Dictionary)
# 握手/請求被拒（reason 為 NetMessage.REASON_* 之一）。
signal rejected(reason: String)
# 連線建立失敗（連不上伺服器）。
signal connection_failed()
# 與伺服器的連線中斷。
signal server_disconnected()

# --- 大廳／房間（P12-5，§5）---
# 房態更新（自己所在房，payload＝member_view）。
signal room_updated(room: Dictionary)
# 大廳房間列表回覆。
signal room_list_received(list: Array)
# 所在房解散。
signal room_closed(room_id: String, reason: String)
# 大廳請求失敗（不斷線）。
signal lobby_error(reason: String)

var _intent := NetMessage.INTENT_PLAY
var _nickname := ""
var _token := ""
var _welcomed := false

# 對外宣告的遊戲版本；空＝用 NetMessage.GAME_VERSION。
# 供測試/相容性診斷刻意宣告錯版本以驗證伺服器的版本閘（見 §3）。
var advertised_game_version := ""


# 連往伺服器端點。回傳 {ok: bool, error: String}（僅表示「開 peer」成功，連上與否走信號）。
func start(host: String, port: int = NetTransport.DEFAULT_PORT,
		intent: String = NetMessage.INTENT_PLAY,
		nickname: String = "", token: String = "") -> Dictionary:
	var made := NetTransport.create_client(host, port)
	if not made["ok"]:
		return {"ok": false, "error": made["error"]}
	_peer = made["peer"]
	_intent = intent
	_nickname = nickname
	_token = token
	_welcomed = false
	multiplayer.multiplayer_peer = _peer
	_bind_multiplayer_signals()
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
	if not multiplayer.connection_failed.is_connected(_on_conn_failed):
		multiplayer.connection_failed.connect(_on_conn_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_gone):
		multiplayer.server_disconnected.connect(_on_server_gone)
	_started = true
	return {"ok": true, "error": ""}


func is_welcomed() -> bool:
	return _welcomed


# 連上後立刻送握手。
func _on_connected() -> void:
	var gv := advertised_game_version if not advertised_game_version.is_empty() else NetMessage.GAME_VERSION
	var hello := {
		"game_version": gv,
		"data_version": Balance.data_version(),
		"intent": _intent,
		"nickname": _nickname,
	}
	if not _token.is_empty():
		hello["token"] = _token   # 重連（P12-10）用
	send_to(SERVER_ID, NetMessage.T_HELLO, hello)


# --- 大廳／房間請求（送往伺服器）---

func create_room(name: String, locked: bool = false, password: String = "",
		allow_spectators: bool = true, spectator_limit: int = 8) -> void:
	send_to(SERVER_ID, NetMessage.T_CREATE_ROOM, {
		"name": name, "locked": locked, "password": password,
		"allow_spectators": allow_spectators, "spectator_limit": spectator_limit,
	})


func join_room(room_id: String, password: String = "", spectate: bool = false) -> void:
	send_to(SERVER_ID, NetMessage.T_JOIN_ROOM,
		{"room_id": room_id, "password": password, "spectate": spectate})


func leave_room() -> void:
	send_to(SERVER_ID, NetMessage.T_LEAVE_ROOM, {})


func set_ready(ready: bool) -> void:
	send_to(SERVER_ID, NetMessage.T_SET_READY, {"ready": ready})


func list_rooms() -> void:
	send_to(SERVER_ID, NetMessage.T_LIST_ROOMS, {})


func _on_message(_sender_id: int, type: String, payload: Dictionary) -> void:
	match type:
		NetMessage.T_WELCOME:
			_welcomed = true
			welcomed.emit(payload)
		NetMessage.T_REJECTED:
			rejected.emit(String(payload.get("reason", "")))
		NetMessage.T_ROOM_STATE:
			room_updated.emit(payload.get("room", {}))
		NetMessage.T_ROOM_LIST:
			room_list_received.emit(payload.get("rooms", []))
		NetMessage.T_ROOM_CLOSED:
			room_closed.emit(String(payload.get("room_id", "")), String(payload.get("reason", "")))
		NetMessage.T_LOBBY_ERROR:
			lobby_error.emit(String(payload.get("reason", "")))


func _on_conn_failed() -> void:
	connection_failed.emit()


func _on_server_gone() -> void:
	server_disconnected.emit()
