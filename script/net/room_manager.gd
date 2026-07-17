# P12-5 房間管理（見 docs/rebuild/10_連線版本.md §5，決策 D18）。
# 純邏輯（RefCounted、零 Node）：大廳／建房／加入／離開／座位就緒／房間生命週期，多房並行。
# 不碰網路（peer 只是 int id）、不碰 UI；NetGameServer 把網路訊息翻成本類呼叫並廣播結果。
# 每房一顆權威 GameCore 於「對戰起」建立（P12-6/P12-8 接線）；本任務只管房間狀態機與座位。
#
# 隱藏資訊（D19）：房間密碼只留伺服器端（server-only 欄位），對成員的 view／大廳列表皆不外送。
class_name RoomManager
extends RefCounted

# 房間狀態機（§5.2 生命週期）。
const STATE_WAITING := "waiting"     # 等人／就緒
const STATE_DRAFTING := "drafting"   # BP（P12-8）
const STATE_BATTLING := "battling"   # 對戰（P12-6）
const STATE_ENDED := "ended"         # 終局統計，可重開或解散

const SEAT_P1 := "player1"
const SEAT_P2 := "player2"
const SEATS := [SEAT_P1, SEAT_P2]

const DEFAULT_SPECTATOR_LIMIT := 8
# 房碼字母表：去除易混字（0/O、1/I/L）。4 碼 → 32^4 ≈ 百萬組，朋友圈綽綽有餘。
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4

var max_rooms: int = 16
var _rooms: Dictionary = {}       # room_id -> room dict
var _peer_room: Dictionary = {}   # peer_id -> room_id（成員索引，含玩家與旁觀者）
var _rng := RandomNumberGenerator.new()


# seed_value 非 0＝決定性房碼（測試用）；0＝randomize。
func _init(p_max_rooms: int = 16, seed_value: int = 0) -> void:
	max_rooms = maxi(1, p_max_rooms)
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


# ---------------- 建房 ----------------

# host_id 建一間房並入座 P1。opts：name/locked/password/allow_spectators/spectator_limit。
# 回傳 {ok, room_id, error}。
func create_room(host_id: int, opts: Dictionary = {}) -> Dictionary:
	if _peer_room.has(host_id):
		return _err(NetMessage.REASON_ALREADY_IN_ROOM)
	if _rooms.size() >= max_rooms:
		return _err(NetMessage.REASON_TOO_MANY_ROOMS)
	var room_id := _gen_room_id()
	var locked := bool(opts.get("locked", false))
	var password := String(opts.get("password", ""))
	var room := {
		"room_id": room_id,
		"name": _clean_name(String(opts.get("name", ""))),
		"locked": locked and not password.is_empty(),  # 上鎖必須有密碼，否則視為公開
		"password": password,                          # server-only
		"allow_spectators": bool(opts.get("allow_spectators", true)),
		"spectator_limit": clampi(int(opts.get("spectator_limit", DEFAULT_SPECTATOR_LIMIT)), 0, 64),
		"host_id": host_id,
		"state": STATE_WAITING,
		"seats": {SEAT_P1: host_id, SEAT_P2: 0},
		"ready": {SEAT_P1: false, SEAT_P2: false},
		"spectators": [],
	}
	_rooms[room_id] = room
	_peer_room[host_id] = room_id
	return {"ok": true, "room_id": room_id, "error": ""}


# ---------------- 加入 ----------------

# peer_id 加入 room_id。want_spectate＝以旁觀身分（否則優先入座、滿座退為旁觀）。
# 回傳 {ok, room_id, role, error}；role∈{"player","spectator"}。
func join(peer_id: int, room_id: String, password: String = "", want_spectate: bool = false) -> Dictionary:
	if _peer_room.has(peer_id):
		return _err(NetMessage.REASON_ALREADY_IN_ROOM)
	if not _rooms.has(room_id):
		return _err(NetMessage.REASON_ROOM_NOT_FOUND)
	var room: Dictionary = _rooms[room_id]
	if bool(room["locked"]) and password != String(room["password"]):
		return _err(NetMessage.REASON_BAD_PASSWORD)

	if want_spectate:
		if not _can_spectate(room):
			return _err(NetMessage.REASON_NO_SPECTATE if not bool(room["allow_spectators"]) else NetMessage.REASON_ROOM_FULL)
		(room["spectators"] as Array).append(peer_id)
		_peer_room[peer_id] = room_id
		return {"ok": true, "room_id": room_id, "role": "spectator", "error": ""}

	# 想當玩家：找空位。
	var seat := _free_seat(room)
	if seat != "":
		room["seats"][seat] = peer_id
		_peer_room[peer_id] = room_id
		return {"ok": true, "room_id": room_id, "role": "player", "error": ""}
	# 滿座：依觀戰開關退為旁觀，否則拒絕。
	if _can_spectate(room):
		(room["spectators"] as Array).append(peer_id)
		_peer_room[peer_id] = room_id
		return {"ok": true, "room_id": room_id, "role": "spectator", "error": ""}
	return _err(NetMessage.REASON_ROOM_FULL)


# ---------------- 離開／斷線 ----------------

# peer_id 離開所在房。回傳 {ok, room_id, dissolved, members_before, error}。
# members_before＝離開前的房內成員（供 server 廣播 room_closed）；dissolved＝房因無玩家而解散。
func leave(peer_id: int) -> Dictionary:
	if not _peer_room.has(peer_id):
		return _err(NetMessage.REASON_NOT_IN_ROOM)
	var room_id: String = _peer_room[peer_id]
	var room: Dictionary = _rooms[room_id]
	var members_before := room_members(room_id)
	_peer_room.erase(peer_id)
	# 從座位或旁觀清單移除。
	var seat := _seat_of(room, peer_id)
	if seat != "":
		room["seats"][seat] = 0
		room["ready"][seat] = false
	else:
		(room["spectators"] as Array).erase(peer_id)
	# 房主離開 → 轉給留下的玩家（其一），無玩家則交給旁觀者充當名義房主。
	if int(room["host_id"]) == peer_id:
		room["host_id"] = _pick_new_host(room)
	# 無玩家即解散（旁觀者一併移出）。
	var dissolved := _player_count(room) == 0
	if dissolved:
		for s in room["spectators"]:
			_peer_room.erase(s)
		_rooms.erase(room_id)
	return {"ok": true, "room_id": room_id, "dissolved": dissolved,
		"members_before": members_before, "error": ""}


# ---------------- 座位就緒 ----------------

# 設定 peer_id（須為玩家、房在 waiting）的就緒狀態。回傳 {ok, room_id, error}。
func set_ready(peer_id: int, ready: bool) -> Dictionary:
	if not _peer_room.has(peer_id):
		return _err(NetMessage.REASON_NOT_IN_ROOM)
	var room_id: String = _peer_room[peer_id]
	var room: Dictionary = _rooms[room_id]
	var seat := _seat_of(room, peer_id)
	if seat == "":
		return _err(NetMessage.REASON_NOT_A_PLAYER)
	if String(room["state"]) != STATE_WAITING:
		return _err(NetMessage.REASON_BAD_STATE)
	room["ready"][seat] = ready
	return {"ok": true, "room_id": room_id, "error": ""}


# ---------------- 生命週期轉換（重物件接線在 P12-6/8）----------------

# 兩席皆有人且皆就緒。
func both_ready(room_id: String) -> bool:
	if not _rooms.has(room_id):
		return false
	var room: Dictionary = _rooms[room_id]
	return int(room["seats"][SEAT_P1]) != 0 and int(room["seats"][SEAT_P2]) != 0 \
		and bool(room["ready"][SEAT_P1]) and bool(room["ready"][SEAT_P2])


# waiting →（兩席就緒）→ drafting。回傳是否成功轉換。
func begin_draft(room_id: String) -> bool:
	return _transition(room_id, STATE_WAITING, STATE_DRAFTING) if both_ready(room_id) else false


func begin_battle(room_id: String) -> bool:
	return _transition(room_id, STATE_DRAFTING, STATE_BATTLING)


func end_battle(room_id: String) -> bool:
	return _transition(room_id, STATE_BATTLING, STATE_ENDED)


# ended → waiting（同成員重開；清就緒）。
func reopen(room_id: String) -> bool:
	if not _transition(room_id, STATE_ENDED, STATE_WAITING):
		return false
	var room: Dictionary = _rooms[room_id]
	room["ready"] = {SEAT_P1: false, SEAT_P2: false}
	return true


# ---------------- 查詢 ----------------

func has_room(room_id: String) -> bool:
	return _rooms.has(room_id)


func room_count() -> int:
	return _rooms.size()


func room_of(peer_id: int) -> String:
	return String(_peer_room.get(peer_id, ""))


# peer_id 若為某房玩家，回其席位名（player1/player2）；旁觀者或未入房回 ""。
# 供 NetGameServer 依席位指派行動歸屬（不採用 client 宣稱值，§6/§9）。
func player_seat(peer_id: int) -> String:
	var room_id := room_of(peer_id)
	if room_id == "":
		return ""
	return _seat_of(_rooms[room_id], peer_id)


# 房間目前生命週期狀態（waiting/drafting/battling/ended）；無此房回 ""。
func state_of(room_id: String) -> String:
	return String(_rooms[room_id]["state"]) if _rooms.has(room_id) else ""


# 房內全部成員 id（玩家＋旁觀者），供廣播。
func room_members(room_id: String) -> Array:
	if not _rooms.has(room_id):
		return []
	var room: Dictionary = _rooms[room_id]
	var out: Array = []
	for s in SEATS:
		if int(room["seats"][s]) != 0:
			out.append(int(room["seats"][s]))
	out.append_array(room["spectators"])
	return out


# 大廳列表（公開資訊，不含密碼、不含成員 id）。
func list_public() -> Array:
	var out: Array = []
	for room_id in _rooms.keys():
		out.append(public_room(room_id))
	return out


func public_room(room_id: String) -> Dictionary:
	var room: Dictionary = _rooms[room_id]
	return {
		"room_id": room_id,
		"name": room["name"],
		"locked": room["locked"],
		"state": room["state"],
		"player_count": _player_count(room),
		"spectator_count": (room["spectators"] as Array).size(),
		"spectator_limit": room["spectator_limit"],
		"allow_spectators": room["allow_spectators"],
	}


# 成員視圖（廣播給房內成員；不含 password）。
func member_view(room_id: String) -> Dictionary:
	var room: Dictionary = _rooms[room_id]
	return {
		"room_id": room_id,
		"name": room["name"],
		"locked": room["locked"],
		"allow_spectators": room["allow_spectators"],
		"spectator_limit": room["spectator_limit"],
		"host_id": room["host_id"],
		"state": room["state"],
		"seats": (room["seats"] as Dictionary).duplicate(),
		"ready": (room["ready"] as Dictionary).duplicate(),
		"spectators": (room["spectators"] as Array).duplicate(),
		"player_count": _player_count(room),
	}


# ---------------- 內部 ----------------

func _transition(room_id: String, from_state: String, to_state: String) -> bool:
	if not _rooms.has(room_id):
		return false
	var room: Dictionary = _rooms[room_id]
	if String(room["state"]) != from_state:
		return false
	room["state"] = to_state
	return true


func _free_seat(room: Dictionary) -> String:
	for s in SEATS:
		if int(room["seats"][s]) == 0:
			return s
	return ""


func _seat_of(room: Dictionary, peer_id: int) -> String:
	for s in SEATS:
		if int(room["seats"][s]) == peer_id:
			return s
	return ""


func _player_count(room: Dictionary) -> int:
	var n := 0
	for s in SEATS:
		if int(room["seats"][s]) != 0:
			n += 1
	return n


func _can_spectate(room: Dictionary) -> bool:
	return bool(room["allow_spectators"]) \
		and (room["spectators"] as Array).size() < int(room["spectator_limit"])


# 房主離開後接任者：優先留下的玩家，其次任一旁觀者，皆無回 0。
func _pick_new_host(room: Dictionary) -> int:
	for s in SEATS:
		if int(room["seats"][s]) != 0:
			return int(room["seats"][s])
	var specs: Array = room["spectators"]
	return int(specs[0]) if not specs.is_empty() else 0


func _gen_room_id() -> String:
	for _attempt in 200:
		var s := ""
		for _i in CODE_LENGTH:
			s += CODE_ALPHABET[_rng.randi() % CODE_ALPHABET.length()]
		if not _rooms.has(s):
			return s
	# 極端碰撞退路：序號房碼。
	return "R%04d" % _rooms.size()


func _clean_name(name: String) -> String:
	var n := name.strip_edges()
	if n.is_empty():
		return "房間"
	return n.substr(0, 24)


func _err(reason: String) -> Dictionary:
	return {"ok": false, "room_id": "", "error": reason}
