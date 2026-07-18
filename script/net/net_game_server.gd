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
# room_id -> NetDraftSession（每房一顆權威選秀狀態；於「選秀起」建立、完成後移除，P12-8）。
var _draft_sessions: Dictionary = {}
# 選秀計時（server 權威；預設關，正式部署由 server_config 開啟，P12-11）。
var _draft_timer_on: bool = false
var _draft_seconds: float = 45.0
# P12-10 席位保留秒數（掉線等待重連；server_config 可覆蓋，見 server_main）。
var seat_hold_seconds: float = 60.0
# P12-11 對局結束時 server 端存 ReplayLog（server_config.save_replays；測試預設關避免寫檔）。
var save_replays: bool = false


# 開伺服器：沿用 NetServer.start，另接斷線→離房清理。
func start(port: int = NetTransport.DEFAULT_PORT,
		max_clients: int = NetTransport.DEFAULT_MAX_CLIENTS) -> Dictionary:
	var r := super(port, max_clients)
	if r["ok"] and not transport_peer_disconnected.is_connected(_on_peer_left):
		transport_peer_disconnected.connect(_on_peer_left)
	return r


# --- 握手：先版本閘＋認證（父類），通過後若帶 token 則走重連（P12-10，§8）---

func _handle_hello(sender_id: int, payload: Dictionary) -> void:
	super(sender_id, payload)   # 版本閘＋意圖檢查＋welcome（失敗則已 reject＋斷線）
	if not is_authenticated(sender_id):
		return
	var token := String(payload.get("token", ""))
	if not token.is_empty():
		_handle_reconnect(sender_id, token)


# 帶 token 重連：驗證→逐出殘留舊連線→收復席位→補送快照＋此後事件自然續播（§8）。
# token 無效（席位已逾時放棄或亂填）→ lobby_error(bad_token)，客端留在大廳（可重新開/加房）。
func _handle_reconnect(sender_id: int, token: String) -> void:
	var res := rooms.reconnect(sender_id, token)
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	var room_id: String = res["room_id"]
	var old_peer := int(res["old_peer_id"])
	if old_peer != 0 and old_peer != sender_id:
		_clients.erase(old_peer)   # 清舊連線的認證追蹤
		_evict_peer(old_peer)      # 逐出殘留舊連線（傳輸層斷線）
	_broadcast_room_state(room_id)   # 對手看到席位恢復（held 清除）、計時恢復（has_held_seat 轉 false）
	_send_seat_token(sender_id, room_id, String(res["seat"]), token)   # 重發 token（供再次斷線重連）
	_send_catchup(sender_id, room_id)   # 補送當前對局公開狀態（同旁觀中途加入），此後事件續播


# 逐出一個 peer（僅實機 ENet 有意義；同程序測試 _peer 為 null 時 no-op）。
func _evict_peer(peer_id: int) -> void:
	if _peer is ENetMultiplayerPeer:
		(_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)


# 私下下發席位 token（只給該玩家；server-only 資訊，不進廣播房態）。
func _send_seat_token(peer_id: int, room_id: String, seat: String, token: String) -> void:
	send_to(peer_id, NetMessage.T_SEAT_TOKEN, {"token": token, "room_id": room_id, "seat": seat})


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
		NetMessage.T_REMATCH:
			_do_rematch(sender_id)
		NetMessage.T_START_DRAFT:
			_do_start_draft(sender_id)
		NetMessage.T_DRAFT_ACTION:
			_do_draft_action(sender_id, payload)
		NetMessage.T_START_BATTLE:
			_do_start_battle(sender_id, payload)
		NetMessage.T_GAME_ACTION:
			_do_game_action(sender_id, payload)
		_:
			pass


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
	_send_seat_token(sender_id, res["room_id"], RoomManager.SEAT_P1, String(res["token"]))


func _do_join(sender_id: int, payload: Dictionary) -> void:
	# 旁觀意圖：payload.spectate 優先，否則沿用握手 intent。
	var spectate := bool(payload.get("spectate", _intent_is_spectate(sender_id)))
	var res := rooms.join(sender_id, String(payload.get("room_id", "")),
		String(payload.get("password", "")), spectate)
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_broadcast_room_state(res["room_id"])
	if String(res.get("role", "")) == "player":
		_send_seat_token(sender_id, res["room_id"], rooms.player_seat(sender_id), String(res["token"]))
	_send_catchup(sender_id, res["room_id"])   # P12-9：中途加入者補送當前對局狀態，此後事件自然續播


# P12-9 旁觀中途加入補送（見 10_連線版本.md §7，D18/D19）。
# 新加入者（對戰/選秀中座位已滿→實務上為旁觀者）除房態外，另補送「當前對局公開狀態」以重建畫面；
# 此後事件流自然續播（已是房內成員，`_broadcast_to_room` 涵蓋，無需重放整局）。
#   drafting → 當前公開選秀 view；battling → 當前公開快照；ended → 終局快照＋勝方。
# **只送給該新加入者**（非全房廣播）；waiting 無對局狀態，房態已足夠、不補送。
# 全為 D19 公開資訊（含雙方手牌，不含 seed／牌庫序，見 GameSnapshot／NetDraftSession.view）。
func _send_catchup(sender_id: int, room_id: String) -> void:
	match rooms.state_of(room_id):
		RoomManager.STATE_DRAFTING:
			if _draft_sessions.has(room_id):
				send_to(sender_id, NetMessage.T_DRAFT_STATE,
					{"draft": (_draft_sessions[room_id] as NetDraftSession).view()})
		RoomManager.STATE_BATTLING:
			if _sessions.has(room_id):
				send_to(sender_id, NetMessage.T_SNAPSHOT,
					{"snapshot": (_sessions[room_id] as NetGameSession).snapshot()})
		RoomManager.STATE_ENDED:
			if _sessions.has(room_id):
				var session: NetGameSession = _sessions[room_id]
				send_to(sender_id, NetMessage.T_GAME_OVER,
					{"snapshot": session.snapshot(), "winner": session.core.winner_name()})


func _do_leave(sender_id: int) -> void:
	var res := rooms.leave(sender_id)
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_after_leave(res)


# P12-15 再戰（見 10 §11.2-7）：終局房（ended）玩家請求「再來一局」。
# 首位請求者把房間 ended→waiting（reopen 清就緒）並丟棄上一局權威 session；接著（含後續請求者）
# 標記本席就緒。雙方皆按＝兩席就緒 → 回到一般 waiting 流程（房主按開始 → 連線 BP → 對戰，新 seed）。
# 旁觀者無此權；非房內/非玩家/非 ended-或-waiting 皆回 lobby_error（不斷線）。
func _do_rematch(sender_id: int) -> void:
	var room_id := rooms.room_of(sender_id)
	if room_id == "":
		_lobby_error(sender_id, NetMessage.REASON_NOT_IN_ROOM)
		return
	if rooms.player_seat(sender_id) == "":
		_lobby_error(sender_id, NetMessage.REASON_NOT_A_PLAYER)
		return
	var state := rooms.state_of(room_id)
	if state == RoomManager.STATE_ENDED:
		rooms.reopen(room_id)          # ended → waiting（清雙方就緒）
		_sessions.erase(room_id)       # 丟棄上一局權威 session（統計已於終局送達；新局將重建）
		_draft_sessions.erase(room_id)
	elif state != RoomManager.STATE_WAITING:
		_lobby_error(sender_id, NetMessage.REASON_BAD_STATE)
		return
	rooms.set_ready(sender_id, true)   # 請求者＝我要再來一局（本席就緒）
	_broadcast_room_state(room_id)


func _do_set_ready(sender_id: int, payload: Dictionary) -> void:
	var res := rooms.set_ready(sender_id, bool(payload.get("ready", false)))
	if not res["ok"]:
		_lobby_error(sender_id, res["error"])
		return
	_broadcast_room_state(res["room_id"])


# --- 選秀 BP（P12-8，§6）---

# 兩席就緒 → 房間 waiting → drafting，建權威 NetDraftSession，廣播房態＋開局選秀狀態。
# 前提：請求者為房內玩家、兩席就緒。seed 於此產生（只存伺服器，D19），完成後傳給對戰 GameCore。
func _do_start_draft(sender_id: int) -> void:
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
	var draft := NetDraftSession.new()
	draft.start(int(Time.get_unix_time_from_system()) ^ randi(), _draft_timer_on, _draft_seconds)
	_draft_sessions[room_id] = draft
	_broadcast_room_state(room_id)   # 房態 → drafting（UI 更新）
	_broadcast_to_room(room_id, NetMessage.T_DRAFT_STATE, {"draft": draft.view()})


# 席位玩家的選秀行動：席位由 server 認定（不採 client 宣稱值）；旁觀者一律拒。
# 成功→廣播選秀狀態（全房同一份，BP 全公開）；完成→建 GameCore 進對戰；
# 失敗→只回行動者 draft_rejected（不斷線）。
func _do_draft_action(sender_id: int, payload: Dictionary) -> void:
	var room_id := rooms.room_of(sender_id)
	if room_id == "" or not _draft_sessions.has(room_id) \
			or rooms.state_of(room_id) != RoomManager.STATE_DRAFTING:
		_draft_rejected(sender_id, NetMessage.REASON_NOT_DRAFTING)
		return
	var seat := rooms.player_seat(sender_id)
	if seat == "":
		_draft_rejected(sender_id, NetMessage.REASON_SPECTATOR_ACTION)
		return
	var action := NetCodec.decode_draft_action(payload.get("action", null), seat)
	if action == null:
		_draft_rejected(sender_id, NetMessage.REASON_BAD_DRAFT_ACTION)
		return
	var draft: NetDraftSession = _draft_sessions[room_id]
	var res := draft.apply(seat, action)
	if not res["ok"]:
		_draft_rejected(sender_id, _draft_reason(String(res["message"])), String(res["message"]))
		return
	_broadcast_to_room(room_id, NetMessage.T_DRAFT_STATE, {"draft": draft.view()})
	if bool(res["done"]):
		_complete_draft(room_id, draft)


# 選秀完成：以雙方牌組建權威 GameCore（seed 沿用選秀階段 server 產生者）→ 房間 drafting→battling
# → 廣播開局快照＋事件（§6：完成後 server 建 GameCore 發首份快照進對戰）。
func _complete_draft(room_id: String, draft: NetDraftSession) -> void:
	var decks := draft.decks()
	var seed_value := draft.seed_value
	_draft_sessions.erase(room_id)
	rooms.begin_battle(room_id)   # drafting → battling
	_launch_battle(room_id, decks[0], decks[1], seed_value)


# 選秀行動拒絕原因對映（dispatcher 內部英文訊息 → 穩定 reason 常數；回合閘尤其明確）。
func _draft_reason(message: String) -> String:
	match message:
		"Not your turn":
			return NetMessage.REASON_NOT_YOUR_TURN
		_:
			return NetMessage.REASON_BAD_DRAFT_ACTION


func _draft_rejected(sender_id: int, reason: String, message: String = "") -> void:
	send_to(sender_id, NetMessage.T_DRAFT_REJECTED, {"reason": reason, "message": message})


# --- 對戰（P12-6，§4/§6）---

# 開發旗標：跳過 BP、以預設牌組開戰，先驗證對戰鏈路（正式流程走上方連線 BP，見 §6）。
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
	_launch_battle(room_id, NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, seed_value)


# 以指定牌組建權威 GameCore、存 session、廣播開局快照＋事件（開發旗標與選秀完成共用）。
# 前提：房間已轉入 battling（呼叫端負責 begin_battle）。db=null → GameCore.setup 用 autoload Balance。
func _launch_battle(room_id: String, p1_deck: Array, p2_deck: Array, seed_value: int) -> void:
	var session := NetGameSession.new()
	# 回合計時預設關（§6 對戰計時本任務只到權威骨幹）。
	var events: Array = session.start(p1_deck, p2_deck, seed_value, null)
	_sessions[room_id] = session
	_broadcast_room_state(room_id)   # 房態 → battling（UI 更新）
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
# 保留 session 至房間重開／解散（供終局統計檢視）。P12-11：存 server 端 ReplayLog。
func _finish_battle(room_id: String, session: NetGameSession) -> void:
	_broadcast_to_room(room_id, NetMessage.T_GAME_OVER,
		{"snapshot": session.snapshot(), "winner": session.core.winner_name()})
	rooms.end_battle(room_id)
	_save_replay(session)


# P12-11：對局結束存 ReplayLog（沿用 P11-2 格式；seed 只存於此、檔案在 server user://replays/）。
# save_replays 關（測試預設）或無 action 則略過。
func _save_replay(session: NetGameSession) -> void:
	if not save_replays or session == null or session.replay == null \
			or (session.replay.actions as Array).is_empty():
		return
	ReplayLog.save_to_file(session.replay, ReplayLog.new_path())


# 伺服器主迴圈每幀推進所有房間的回合計時（權威）；逾時由 session 自行 end_turn，本函式廣播結果。
# server_main 於運行樹呼叫（_process）；測試以 RefCounted 手動呼叫驗證。
func tick_sessions(delta: float) -> void:
	# P12-10：先推進重連保留倒數；逾時席位交給 _on_hold_expired 判定（可能解散房／erase session）。
	for exp in rooms.tick_holds(delta):
		_on_hold_expired(String(exp["room_id"]), String(exp["seat"]))
	for room_id in _sessions.keys():
		var session: NetGameSession = _sessions[room_id]
		if session.is_over():
			continue
		if rooms.has_held_seat(room_id):
			continue   # 等待重連期間暫停回合計時（不懲罰掉線方，§8）
		var res := session.tick(delta)
		if res["ok"]:
			_broadcast_room_result(room_id, session, res)
	# 選秀計時（P12-8）：逾時＝server 權威 auto_fill_and_advance→廣播狀態；完成→建 GameCore 進對戰。
	# keys 複本：_complete_draft 會於迴圈內移除該房的選秀 session。
	for room_id in _draft_sessions.keys().duplicate():
		if rooms.has_held_seat(room_id):
			continue   # 選秀中掉線等待重連→暫停選秀計時
		var draft: NetDraftSession = _draft_sessions[room_id]
		var dres := draft.tick(delta)
		if bool(dres["ok"]):
			_broadcast_to_room(room_id, NetMessage.T_DRAFT_STATE, {"draft": draft.view()})
			if bool(dres["done"]):
				_complete_draft(room_id, draft)


# 重連逾時判定（P12-10，§8）：放棄 held 席位後——
#   對戰中且對手仍在 → 判掉線方落敗（對手判勝）：廣播 game_over(winner=對手, reason=forfeit)、房 ended；
#   選秀中或無對局 session 但仍有玩家 → 中止對局回到 waiting（同成員重開），丟棄暫態 session；
#   無玩家 → 房解散，通知留下成員 room_closed(reconnect_timeout)。
func _on_hold_expired(room_id: String, seat: String) -> void:
	var state := rooms.state_of(room_id)
	var other_seat := RoomManager.SEAT_P2 if seat == RoomManager.SEAT_P1 else RoomManager.SEAT_P1
	var other_live := rooms.seat_peer(room_id, other_seat) != 0
	var res := rooms.vacate_held_seat(room_id, seat)
	if not res["ok"]:
		return
	if bool(res["dissolved"]):
		_sessions.erase(room_id)
		_draft_sessions.erase(room_id)
		for pid in res["members_before"]:
			send_to(int(pid), NetMessage.T_ROOM_CLOSED,
				{"room_id": room_id, "reason": NetMessage.REASON_RECONNECT_TIMEOUT})
		return
	if state == RoomManager.STATE_BATTLING and _sessions.has(room_id) and other_live:
		var session: NetGameSession = _sessions[room_id]
		_broadcast_to_room(room_id, NetMessage.T_GAME_OVER,
			{"snapshot": session.snapshot(), "winner": other_seat,
			"reason": NetMessage.REASON_OPPONENT_FORFEIT})
		rooms.end_battle(room_id)   # battling → ended（session 保留供統計，可重開／解散）
		_save_replay(session)   # P12-11：判勝終局也存紀錄（含掉線前的完整 action 流）
	else:
		# 選秀中掉線逾時／其他：中止暫態對局，回到 waiting 供同成員重開。
		_sessions.erase(room_id)
		_draft_sessions.erase(room_id)
		rooms.force_waiting(room_id)
		_broadcast_room_state(room_id)


func _process(delta: float) -> void:
	tick_sessions(delta)


func _broadcast_to_room(room_id: String, type: String, payload: Dictionary) -> void:
	for pid in rooms.room_members(room_id):
		send_to(int(pid), type, payload)


func _action_rejected(sender_id: int, reason: String, message: String = "") -> void:
	send_to(sender_id, NetMessage.T_ACTION_REJECTED, {"reason": reason, "message": message})


# 斷線處理（P12-10，§8）：對局中的玩家＝席位保留等待重連（held），其餘＝自動離房。
# held 時只廣播新房態（對手顯示「等待重連」；計時暫停由 tick_sessions 的 has_held_seat 守）。
func _on_peer_left(peer_id: int) -> void:
	if rooms.room_of(peer_id) == "":
		return
	var res := rooms.handle_disconnect(peer_id, seat_hold_seconds)
	if not res["ok"]:
		return
	if bool(res.get("held", false)):
		_broadcast_room_state(res["room_id"])
	else:
		_after_leave(res)


# 離房後的通知：解散→通知原成員 room_closed；否則→廣播新房態給留下成員。
func _after_leave(res: Dictionary) -> void:
	var room_id: String = res["room_id"]
	if bool(res["dissolved"]):
		_sessions.erase(room_id)   # 房解散 → 丟棄權威 session
		_draft_sessions.erase(room_id)   # 一併丟棄選秀 session（P12-8）
		for pid in res["members_before"]:
			send_to(int(pid), NetMessage.T_ROOM_CLOSED, {"room_id": room_id, "reason": "empty"})
	else:
		_broadcast_room_state(room_id)


# --- 廣播 ---

func _broadcast_room_state(room_id: String) -> void:
	if not rooms.has_room(room_id):
		return
	var view := rooms.member_view(room_id)
	# P12-17：附上成員暱稱（peer_id→nickname；握手時存於 _clients），供客端顯示對手暱稱而非 #peer-id。
	# RoomManager 純邏輯只知 peer id、不知暱稱，故由 server 這層注入（相容性追加，空暱稱客端退回 #id）。
	view["names"] = _member_names(room_id)
	for pid in rooms.room_members(room_id):
		send_to(int(pid), NetMessage.T_ROOM_STATE, {"room": view})


# 房內成員暱稱表 {str(peer_id): nickname}（僅 live 成員；held 席位 pid=0 無此鍵）。
func _member_names(room_id: String) -> Dictionary:
	var out: Dictionary = {}
	for pid in rooms.room_members(room_id):
		out[str(int(pid))] = String(_clients.get(int(pid), {}).get("nickname", ""))
	return out


# 大廳錯誤（不斷線）。握手層的 T_REJECTED 才會斷線。
func _lobby_error(sender_id: int, reason: String) -> void:
	send_to(sender_id, NetMessage.T_LOBBY_ERROR, {"reason": reason})


func _intent_is_spectate(peer_id: int) -> bool:
	return _clients.has(peer_id) and String(_clients[peer_id].get("intent", "")) == NetMessage.INTENT_SPECTATE


func stop() -> void:
	rooms = RoomManager.new()
	_sessions.clear()
	_draft_sessions.clear()
	super()
