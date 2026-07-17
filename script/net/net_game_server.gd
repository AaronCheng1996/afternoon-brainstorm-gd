# P12-5 大廳／房間伺服器（見 docs/rebuild/10_連線版本.md §5，D18）。
# 在 NetServer（握手／版本閘）之上接大廳：把已認證客端的房間訊息翻成 RoomManager 呼叫，
# 並把結果廣播給相關成員。伺服器端輸入全部當不可信——未認證忽略、payload 只讀不信、
# 非法請求回 lobby_error（不斷線，有別於握手層的 rejected）。
# 每房一顆權威 GameCore 於「對戰起」建立（P12-6/P12-8 於此擴充；本任務只到房間狀態機）。
class_name NetGameServer
extends NetServer

var rooms: RoomManager = RoomManager.new()
# room_id -> NetGameSession（每房一顆權威 GameCore；於「對戰起」建立，P12-6）。
var _sessions: Dictionary = {}


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
		NetMessage.T_START_BATTLE:
			_do_start_battle(sender_id, payload)
		NetMessage.T_GAME_ACTION:
			_do_game_action(sender_id, payload)
		_:
			pass   # BP 訊息在 P12-8 於此擴充


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


# --- 對戰（P12-6，§4/§6）---

# 開發旗標：跳過 BP、以預設牌組開戰，先驗證對戰鏈路（正式流程走 P12-8 的連線 BP，見 §6）。
# 前提：請求者為房內玩家、兩席就緒。seed 可由 payload 指定（測試決定性用），否則隨機。
# 房間 waiting →（begin_draft）→ drafting →（begin_battle）→ battling（跳過 BP 的行動）。
func _do_start_battle(sender_id: int, payload: Dictionary) -> void:
	var room_id := rooms.room_of(sender_id)
	if room_id == "":
		_lobby_error(sender_id, NetMessage.REASON_NOT_IN_ROOM)
		return
	if rooms.player_seat(sender_id) == "":
		_lobby_error(sender_id, NetMessage.REASON_NOT_A_PLAYER)
		return
	if rooms.state_of(room_id) != RoomManager.STATE_WAITING or not rooms.both_ready(room_id):
		_lobby_error(sender_id, NetMessage.REASON_NOT_READY)
		return
	rooms.begin_draft(room_id)   # waiting → drafting
	rooms.begin_battle(room_id)  # drafting → battling（開發旗標跳過 BP 行動）
	var seed_value := int(payload.get("seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ randi()
	var session := NetGameSession.new()
	# db=null → GameCore.setup 用 autoload Balance；回合計時預設關（§6 對戰計時本任務只到權威骨幹）。
	var events: Array = session.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK,
		seed_value, null)
	_sessions[room_id] = session
	# 開局快照（全房同一份，D19）＋開局事件流。
	_broadcast_to_room(room_id, NetMessage.T_SNAPSHOT, {"snapshot": session.snapshot()})
	if not events.is_empty():
		_broadcast_to_room(room_id, NetMessage.T_GAME_EVENTS,
			{"events": NetCodec.encode_events(events)})


# 席位玩家的行動：席位歸屬由 server 認定（不採 client 宣稱值）；旁觀者一律拒（唯讀由 server 保證）。
# 成功→廣播事件流＋（回合交接時）公開快照；失敗→只回行動者 action_rejected（不斷線）。
func _do_game_action(sender_id: int, payload: Dictionary) -> void:
	var room_id := rooms.room_of(sender_id)
	if room_id == "" or not _sessions.has(room_id) \
			or rooms.state_of(room_id) != RoomManager.STATE_BATTLING:
		_action_rejected(sender_id, NetMessage.REASON_NOT_BATTLING)
		return
	var seat := rooms.player_seat(sender_id)
	if seat == "":
		_action_rejected(sender_id, NetMessage.REASON_SPECTATOR_ACTION)
		return
	var action := NetCodec.decode_action(payload.get("action", null), seat)
	if action == null:
		_action_rejected(sender_id, NetMessage.REASON_BAD_ACTION)
		return
	var session: NetGameSession = _sessions[room_id]
	# 回合閘（在 dispatch 前明確擋，回清楚原因；dispatch 內另有一層守衛）。
	if session.core.current_player() != seat:
		_action_rejected(sender_id, NetMessage.REASON_NOT_YOUR_TURN)
		return
	var res := session.apply_action(seat, action)
	if not res["ok"]:
		_action_rejected(sender_id, String(res["message"]))
		return
	_broadcast_room_result(room_id, session, res)


# 廣播一次 apply_action/tick 的結果：事件流恆送；終局→game_over（含終局快照）；
# 否則回合交接→送校正快照（§4：關鍵點下發單一公開快照）。
func _broadcast_room_result(room_id: String, session: NetGameSession, res: Dictionary) -> void:
	_broadcast_to_room(room_id, NetMessage.T_GAME_EVENTS,
		{"events": NetCodec.encode_events(res["events"])})
	if bool(res["over"]):
		_finish_battle(room_id, session)
	elif bool(res["turn_changed"]):
		_broadcast_to_room(room_id, NetMessage.T_SNAPSHOT, {"snapshot": session.snapshot()})


# 終局：廣播 game_over（含完整統計於快照）＋房間 battling→ended（可重開或解散）。
# 保留 session 至房間重開／解散（供終局統計檢視）。
func _finish_battle(room_id: String, session: NetGameSession) -> void:
	_broadcast_to_room(room_id, NetMessage.T_GAME_OVER,
		{"snapshot": session.snapshot(), "winner": session.core.winner_name()})
	rooms.end_battle(room_id)


# 伺服器主迴圈每幀推進所有房間的回合計時（權威）；逾時由 session 自行 end_turn，本函式廣播結果。
# server_main 於運行樹呼叫（_process）；測試以 RefCounted 手動呼叫驗證。
func tick_sessions(delta: float) -> void:
	for room_id in _sessions.keys():
		var session: NetGameSession = _sessions[room_id]
		if session.is_over():
			continue
		var res := session.tick(delta)
		if res["ok"]:
			_broadcast_room_result(room_id, session, res)


func _process(delta: float) -> void:
	tick_sessions(delta)


func _broadcast_to_room(room_id: String, type: String, payload: Dictionary) -> void:
	for pid in rooms.room_members(room_id):
		send_to(int(pid), type, payload)


func _action_rejected(sender_id: int, reason: String, message: String = "") -> void:
	send_to(sender_id, NetMessage.T_ACTION_REJECTED, {"reason": reason, "message": message})


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
		_sessions.erase(room_id)   # 房解散 → 丟棄權威 session
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
	_sessions.clear()
	super()
