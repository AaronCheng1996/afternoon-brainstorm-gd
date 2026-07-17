# P12-5 大廳／房間伺服器（見 docs/rebuild/10_連線版本.md §5，D18）。
# 在 NetServer（握手／版本閘）之上接大廳：把已認證客端的房間訊息翻成 RoomManager 呼叫，
# 並把結果廣播給相關成員。伺服器端輸入全部當不可信——未認證忽略、payload 只讀不信、
# 非法請求回 lobby_error（不斷線，有別於握手層的 rejected）。
# 每房一顆權威 GameCore 於「對戰起」建立（P12-6/P12-8 於此擴充；本任務只到房間狀態機）。
class_name NetGameServer
extends NetServer

var rooms: RoomManager = RoomManager.new()


# 開伺服器：沿用 NetServer.start，另接斷線→離房清理。
func start(port: int = NetTransport.DEFAULT_PORT,
		max_clients: int = NetTransport.DEFAULT_MAX_CLIENTS) -> Dictionary:
	var r := super(port, max_clients)
	if r["ok"] and not transport_peer_disconnected.is_connected(_on_peer_left):
		transport_peer_disconnected.connect(_on_peer_left)
	return r


# --- 訊息路由（握手層沿用父類；認證後才進大廳）---

func _on_message(sender_id: int, type: String, payload: Dictionary) -> void:
	if type == NetMessage.T_HELLO:
		_handle_hello(sender_id, payload)
		return
	if not is_authenticated(sender_id):
		return   # 未握手前忽略（不可信）
	_handle_lobby(sender_id, type, payload)


func _handle_lobby(sender_id: int, type: String, payload: Dictionary) -> void:
	match type:
		NetMessage.T_CREATE_ROOM:
			_do_create(sender_id, payload)
		NetMessage.T_JOIN_ROOM:
			_do_join(sender_id, payload)
		NetMessage.T_LEAVE_ROOM:
			_do_leave(sender_id)
		NetMessage.T_SET_READY:
			_do_set_ready(sender_id, payload)
		NetMessage.T_LIST_ROOMS:
			send_to(sender_id, NetMessage.T_ROOM_LIST, {"rooms": rooms.list_public()})
		_:
			pass   # 對戰／BP 訊息在 P12-6/P12-8 於此擴充


func _do_create(sender_id: int, payload: Dictionary) -> void:
	var opts := {
		"name": String(payload.get("name", "")),
		"locked": bool(payload.get("locked", false)),
		"password": String(payload.get("password", "")),
		"allow_spectators": bool(payload.get("allow_spectators", true)),
		"spectator_limit": int(payload.get("spectator_limit", RoomManager.DEFAULT_SPECTATOR_LIMIT)),
	}
	var res := rooms.create_room(sender_id, opts)
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_broadcast_room_state(res["room_id"])


func _do_join(sender_id: int, payload: Dictionary) -> void:
	# 旁觀意圖：payload.spectate 優先，否則沿用握手 intent。
	var spectate := bool(payload.get("spectate", _intent_is_spectate(sender_id)))
	var res := rooms.join(sender_id, String(payload.get("room_id", "")),
		String(payload.get("password", "")), spectate)
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_broadcast_room_state(res["room_id"])


func _do_leave(sender_id: int) -> void:
	var res := rooms.leave(sender_id)
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_after_leave(res)


func _do_set_ready(sender_id: int, payload: Dictionary) -> void:
	var res := rooms.set_ready(sender_id, bool(payload.get("ready", false)))
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_broadcast_room_state(res["room_id"])


# 斷線＝自動離房（玩家全走則解散）。
func _on_peer_left(peer_id: int) -> void:
	if rooms.room_of(peer_id) == "":
		return
	var res := rooms.leave(peer_id)
	if res["ok"]:
		_after_leave(res)


# 離房後的通知：解散→通知原成員 room_closed；否則→廣播新房態給留下成員。
func _after_leave(res: Dictionary) -> void:
	var room_id: String = res["room_id"]
	if bool(res["dissolved"]):
		for pid in res["members_before"]:
			send_to(int(pid), NetMessage.T_ROOM_CLOSED, {"room_id": room_id, "reason": "empty"})
	else:
		_broadcast_room_state(room_id)


# --- 廣播 ---

func _broadcast_room_state(room_id: String) -> void:
	if not rooms.has_room(room_id):
		return
	var view := rooms.member_view(room_id)
	for pid in rooms.room_members(room_id):
		send_to(int(pid), NetMessage.T_ROOM_STATE, {"room": view})


# 大廳錯誤（不斷線）。握手層的 T_REJECTED 才會斷線。
func _lobby_error(sender_id: int, reason: String) -> void:
	send_to(sender_id, NetMessage.T_LOBBY_ERROR, {"reason": reason})


func _intent_is_spectate(peer_id: int) -> bool:
	return _clients.has(peer_id) and String(_clients[peer_id].get("intent", "")) == NetMessage.INTENT_SPECTATE


func stop() -> void:
	rooms = RoomManager.new()
	super()
