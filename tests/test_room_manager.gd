# P12-5 驗收：伺服器程序與房間管理（script/net/room_manager.gd、net_game_server.gd、server_main.gd）。
# 見 docs/rebuild/10_連線版本.md §5。分三層，各自忠實：
#   (A) RoomManager 純邏輯：建房/列表(上鎖標記)/密碼錯拒/兩人入座就緒/滿房第三人退旁觀或拒/離開解散
#       ＋生命週期轉換＋房碼格式（決定性 seed）。
#   (B) NetGameServer 大廳訊息（同程序 NetTestBus，覆寫 _transmit）：認證後的 create/list/join/ready/leave
#       廣播與 lobby_error；斷線自動離房。
#   (C) server_main.parse_config：預設→JSON→命令列覆蓋、型別強制。
# 純 RefCounted／Node free 乾淨 → 維持零新洩漏。@rpc-over-ENet 整合待運行樹（P12-6+）。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")


func run(t: Object) -> void:
	_test_manager_flow(t)
	_test_spectator_rules(t)
	_test_lifecycle(t)
	_test_room_code_format(t)
	_test_server_bus_lobby(t)
	_test_server_disconnect_leaves(t)
	_test_parse_config(t)


# ---------------- (A) RoomManager 純邏輯：主流程 ----------------

func _test_manager_flow(t: Object) -> void:
	var rm := RoomManager.new(16, 111)

	# 建房（上鎖＋密碼）：房主入座 P1、狀態 waiting。
	var c := rm.create_room(100, {"name": "阿明的房", "locked": true, "password": "pw"})
	t.ok(c["ok"], "flow：建房成功")
	var rid: String = c["room_id"]
	t.eq(rm.room_of(100), rid, "flow：房主歸屬該房")
	var view := rm.member_view(rid)
	t.eq(int(view["seats"]["player1"]), 100, "flow：房主入座 P1")
	t.eq(int(view["seats"]["player2"]), 0, "flow：P2 空位")
	t.eq(String(view["state"]), RoomManager.STATE_WAITING, "flow：初始 waiting")

	# 大廳列表：可見、上鎖標記，且不外洩密碼。
	var pubs := rm.list_public()
	t.eq(pubs.size(), 1, "flow：大廳列出 1 房")
	t.ok(bool(pubs[0]["locked"]), "flow：上鎖房標記 locked")
	t.ok(not pubs[0].has("password"), "flow：列表不含密碼")
	t.ok(not rm.member_view(rid).has("password"), "flow：成員視圖不含密碼")

	# 密碼錯誤被拒。
	var bad := rm.join(101, rid, "nope", false)
	t.ok(not bad["ok"], "flow：密碼錯誤被拒")
	t.eq(String(bad["error"]), NetMessage.REASON_BAD_PASSWORD, "flow：原因＝bad_password")
	t.eq(rm.room_of(101), "", "flow：被拒者未入房")

	# 正確密碼入座 P2。
	var j := rm.join(101, rid, "pw", false)
	t.ok(j["ok"] and String(j["role"]) == "player", "flow：正確密碼入座為玩家")
	t.eq(int(rm.member_view(rid)["seats"]["player2"]), 101, "flow：入座 P2")

	# 兩人就緒 → both_ready；未就緒前 begin_draft 應失敗。
	t.ok(not rm.begin_draft(rid), "flow：未就緒不可開始 BP")
	rm.set_ready(100, true)
	rm.set_ready(101, true)
	t.ok(rm.both_ready(rid), "flow：兩席就緒")

	# 滿座第三人（想當玩家）→ allow_spectators 預設 true → 退為旁觀。
	var third := rm.join(102, rid, "pw", false)
	t.ok(third["ok"] and String(third["role"]) == "spectator", "flow：滿座第三人退為旁觀")
	t.eq((rm.member_view(rid)["spectators"] as Array).size(), 1, "flow：旁觀者 1")

	# P2 離開：不解散（房主 P1 仍在），席位清空＋就緒歸零。
	var lv := rm.leave(101)
	t.ok(lv["ok"] and not bool(lv["dissolved"]), "flow：P2 離開不解散")
	t.eq(int(rm.member_view(rid)["seats"]["player2"]), 0, "flow：P2 席位清空")
	t.ok(not bool(rm.member_view(rid)["ready"]["player2"]), "flow：離席清就緒")

	# 房主也離開 → 無玩家 → 解散（旁觀者一併移出）。
	var lv2 := rm.leave(100)
	t.ok(bool(lv2["dissolved"]), "flow：無玩家即解散")
	t.ok((lv2["members_before"] as Array).has(102), "flow：解散通知含旁觀者")
	t.ok(not rm.has_room(rid), "flow：房間已移除")
	t.eq(rm.room_of(102), "", "flow：旁觀者一併移出")


# ---------------- (A) 旁觀規則：關閉觀戰／上限 ----------------

func _test_spectator_rules(t: Object) -> void:
	# 關閉觀戰的滿座房：第三人被拒（room_full）。
	var rm := RoomManager.new(16, 222)
	var rid: String = rm.create_room(1, {"allow_spectators": false})["room_id"]
	rm.join(2, rid, "", false)   # 入座 P2 → 滿座
	var third := rm.join(3, rid, "", false)
	t.ok(not third["ok"] and String(third["error"]) == NetMessage.REASON_ROOM_FULL,
		"spec：關觀戰滿座第三人被拒 room_full")
	# 明確想旁觀但房關觀戰 → spectate_disabled。
	var s := rm.join(4, rid, "", true)
	t.eq(String(s["error"]), NetMessage.REASON_NO_SPECTATE, "spec：關觀戰旁觀請求被拒")

	# 觀戰上限＝1：第二位旁觀者被拒 room_full。
	var rm2 := RoomManager.new(16, 333)
	var rid2: String = rm2.create_room(1, {"allow_spectators": true, "spectator_limit": 1})["room_id"]
	t.ok(rm2.join(2, rid2, "", true)["ok"], "spec：第一位旁觀者可加入")
	t.eq(String(rm2.join(3, rid2, "", true)["error"]), NetMessage.REASON_ROOM_FULL,
		"spec：逾觀戰上限被拒")

	# 建房上限：max_rooms=1 → 第二間建房被拒。
	var rm3 := RoomManager.new(1, 444)
	rm3.create_room(1, {})
	t.eq(String(rm3.create_room(2, {})["error"]), NetMessage.REASON_TOO_MANY_ROOMS,
		"spec：逾房間上限被拒")

	# locked 但無密碼 → 視為公開（locked=false）。
	var rm4 := RoomManager.new(16, 555)
	var rid4: String = rm4.create_room(1, {"locked": true, "password": ""})["room_id"]
	t.ok(not bool(rm4.member_view(rid4)["locked"]), "spec：上鎖無密碼視為公開")
	t.ok(rm4.join(2, rid4, "", false)["ok"], "spec：公開房免密碼加入")


# ---------------- (A) 生命週期轉換 ----------------

func _test_lifecycle(t: Object) -> void:
	var rm := RoomManager.new(16, 666)
	var rid: String = rm.create_room(1, {})["room_id"]
	rm.join(2, rid, "", false)
	rm.set_ready(1, true)
	rm.set_ready(2, true)
	t.ok(rm.begin_draft(rid), "life：waiting→drafting（兩席就緒）")
	t.eq(String(rm.member_view(rid)["state"]), RoomManager.STATE_DRAFTING, "life：狀態 drafting")
	t.ok(not rm.begin_draft(rid), "life：重複 begin_draft 無效（狀態閘）")
	t.ok(rm.begin_battle(rid), "life：drafting→battling")
	t.ok(rm.end_battle(rid), "life：battling→ended")
	t.ok(rm.reopen(rid), "life：ended→waiting（重開）")
	t.ok(not bool(rm.member_view(rid)["ready"]["player1"]), "life：重開清就緒")
	# 就緒須在 waiting；drafting 中 set_ready 被擋。
	rm.set_ready(1, true); rm.set_ready(2, true); rm.begin_draft(rid)
	t.eq(String(rm.set_ready(1, false)["error"]), NetMessage.REASON_BAD_STATE,
		"life：非 waiting 不可改就緒")


# ---------------- (A) 房碼格式（決定性 seed）----------------

func _test_room_code_format(t: Object) -> void:
	var rm := RoomManager.new(64, 777)
	var codes := {}
	for i in 20:
		var rid: String = rm.create_room(1000 + i, {})["room_id"]
		t.eq(rid.length(), RoomManager.CODE_LENGTH, "code：房碼長度＝%d" % RoomManager.CODE_LENGTH)
		for ch in rid:
			t.ok(RoomManager.CODE_ALPHABET.contains(ch), "code：字元在字母表內（%s）" % rid)
		t.ok(not codes.has(rid), "code：房碼不重複（%s）" % rid)
		codes[rid] = true
	t.eq(rm.room_count(), 20, "code：20 房並行")


# ---------------- (B) 同程序訊息匯流排：串接真正的 NetGameServer/NetClient ----------------


class _WiredServer extends NetGameServer:
	var bus: NetTestBus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


# 記錄收到之大廳信號的用戶端。
class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var last_list: Array = []
	var last_error: String = ""
	var closed_room: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		room_list_received.connect(func(l): last_list = l)
		lobby_error.connect(func(reason): last_error = reason)
		room_closed.connect(func(rid, _reason): closed_room = rid)


func _mk_client(bus: NetTestBus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


func _test_server_bus_lobby(t: Object) -> void:
	var bus := NetTestBus.new()
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 888)   # 決定性房碼
	bus.add(NetPeerBase.SERVER_ID, server)

	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	var spec := _mk_client(bus, 102, "看客", true)
	for c in [host, p2, spec]:
		bus.add(c.my_id, c)
		c._on_connected()   # 握手認證（送 hello → welcome）
	t.eq(server.authenticated_peers().size(), 3, "bus：三客端完成握手")

	# 建房（上鎖）→ 房主收到 room_state。
	host.create_room("測試房", true, "pw", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	t.ok(rid != "", "bus：建房後房主收到 room_state")
	t.eq(int(host.last_room["seats"]["player1"]), 100, "bus：房主入座 P1")

	# 列表：p2 查詢 → 收 room_list（上鎖標記、無密碼）。
	p2.list_rooms()
	t.eq(p2.last_list.size(), 1, "bus：大廳列出 1 房")
	t.ok(bool(p2.last_list[0]["locked"]), "bus：列表上鎖標記")
	t.ok(not p2.last_list[0].has("password"), "bus：列表不含密碼")

	# 密碼錯誤 → p2 收 lobby_error（不斷線）。
	p2.join_room(rid, "wrong", false)
	t.eq(p2.last_error, NetMessage.REASON_BAD_PASSWORD, "bus：密碼錯誤回 lobby_error")

	# 正確密碼入座 → 房主與 p2 都收到更新（P2 就座）。
	p2.join_room(rid, "pw", false)
	t.eq(int(host.last_room["seats"]["player2"]), 101, "bus：房主收到 P2 入座更新")
	t.eq(int(p2.last_room["seats"]["player2"]), 101, "bus：p2 收到自身入座")

	# 兩席就緒 → 廣播 ready；server 認定 both_ready。
	host.set_ready(true)
	p2.set_ready(true)
	t.ok(bool(host.last_room["ready"]["player2"]), "bus：房主看到 P2 就緒")
	t.ok(server.rooms.both_ready(rid), "bus：server 認定兩席就緒")

	# 旁觀者以 spectate 加入（上鎖同樣驗密碼）→ 入旁觀清單、收到房態。
	spec.join_room(rid, "pw", true)
	t.eq((host.last_room["spectators"] as Array).size(), 1, "bus：旁觀者加入廣播")
	# 經 JSON 廣播後 peer id 為浮點（102.0），成員判定須 int 轉換（用戶端顯示層須留意）。
	var spec_list: Array = spec.last_room["spectators"]
	t.ok(spec_list.size() == 1 and int(spec_list[0]) == 102, "bus：旁觀者自身收到房態（含自己）")

	# p2 離開 → 房主收到 P2 席位清空更新（未解散）。
	p2.leave_room()
	t.eq(int(host.last_room["seats"]["player2"]), 0, "bus：p2 離開後房主看到席位清空")

	# 房主離開 → 無玩家 → 解散 → 旁觀者收 room_closed。
	host.leave_room()
	t.eq(spec.closed_room, rid, "bus：解散通知旁觀者 room_closed")
	t.ok(not server.rooms.has_room(rid), "bus：房間已解散")

	server.free()
	host.free(); p2.free(); spec.free()


func _test_server_disconnect_leaves(t: Object) -> void:
	var bus := NetTestBus.new()
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 999)
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	for c in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	var rid: String = String(server.rooms.create_room(100, {})["room_id"])
	# 直接用 RoomManager 建房＋入座（省訊息），再驗斷線清理。
	server.rooms.join(101, rid, "", false)
	t.eq(server.rooms.member_view(rid)["seats"]["player2"], 101, "disc：p2 已入座")

	# 模擬 p2 斷線（傳輸層 peer_disconnected → NetGameServer._on_peer_left）。
	server._on_peer_left(101)
	t.eq(int(server.rooms.member_view(rid)["seats"]["player2"]), 0, "disc：斷線自動離席")
	t.ok(server.rooms.has_room(rid), "disc：仍有房主，房間存續")
	# 房主斷線 → 無玩家 → 解散。
	server._on_peer_left(100)
	t.ok(not server.rooms.has_room(rid), "disc：房主斷線後房間解散")

	server.free()
	host.free(); p2.free()


# ---------------- (C) server_main.parse_config ----------------

func _test_parse_config(t: Object) -> void:
	var ServerMain := load("res://script/net/server_main.gd")

	# 預設值。
	var d: Dictionary = ServerMain.parse_config(PackedStringArray(), "")
	t.eq(int(d["port"]), NetTransport.DEFAULT_PORT, "cfg：預設埠 24242")
	t.eq(int(d["max_rooms"]), 16, "cfg：預設 max_rooms 16")
	t.ok(bool(d["save_replays"]), "cfg：預設 save_replays true")

	# JSON 檔覆蓋。
	var f: Dictionary = ServerMain.parse_config(PackedStringArray(),
		'{"port": 30000, "max_rooms": 4, "save_replays": false}')
	t.eq(int(f["port"]), 30000, "cfg：JSON 覆蓋埠")
	t.eq(int(f["max_rooms"]), 4, "cfg：JSON 覆蓋 max_rooms")
	t.ok(not bool(f["save_replays"]), "cfg：JSON 覆蓋 bool")

	# 命令列再覆蓋 JSON（key=value）。
	var a: Dictionary = ServerMain.parse_config(PackedStringArray(["port=25555", "max_rooms=8", "save_replays=true"]),
		'{"port": 30000, "max_rooms": 4, "save_replays": false}')
	t.eq(int(a["port"]), 25555, "cfg：命令列覆蓋 JSON 埠")
	t.eq(int(a["max_rooms"]), 8, "cfg：命令列覆蓋 max_rooms")
	t.ok(bool(a["save_replays"]), "cfg：命令列 bool 字串→true")

	# 未知鍵忽略、格式錯的 JSON 退回預設。
	var u: Dictionary = ServerMain.parse_config(PackedStringArray(["unknown=9", "port=127"]), "not json")
	t.eq(int(u["port"]), 127, "cfg：合法鍵套用")
	t.ok(not u.has("unknown"), "cfg：未知鍵忽略")
