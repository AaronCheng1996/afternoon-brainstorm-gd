# P12-17 驗收：場景級 soak（連續多局＋旁觀進出，全程零洩漏、兩端一致）。見 10 §11.2-9。
# 沿用同程序匯流排（@rpc-over-ENet 跨機屬【人工】）：兩個 battle 場景經 server 連打多局
# （終局→再戰→新局），其中一局有第三個旁觀場景中途加入/退出，斷言——
#   每局：兩端最終公開快照＝server 且彼此一致；旁觀場景重建＝server；每局場景 .free() 乾淨。
# 中途重連的 held 顯示轉入子場景見 test_net_reconnect_scene；server 端重連 churn 見 test_net_soak。
# 全部場景/net 物件 .free() → 維持零新洩漏。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")
const BattleScene := preload("res://scenes/battle/battle.tscn")
const ROUNDS := 3


func run(t: Object) -> void:
	_test_scene_soak(t)


# ---------------- 同程序匯流排 ----------------


class _WiredServer extends NetGameServer:
	var bus: NetTestBus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var opening_snapshot: Dictionary = {}

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		snapshot_received.connect(func(s):
			if opening_snapshot.is_empty():
				opening_snapshot = s)


func _mk_client(bus: NetTestBus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


func _mk_battle(client: _WiredClient, seat: String, opening: Dictionary, spectator: bool = false) -> Node:
	var b: Node = BattleScene.instantiate()
	b.boot_net(client, seat, opening, spectator)
	b.set_animation_enabled(false)
	return b


func _strip_ids(snap: Dictionary) -> Dictionary:
	var s := snap.duplicate(true)
	for p in s.get("pieces", []):
		(p as Dictionary).erase("instance_id")
	return s


func _canon(snap: Dictionary) -> String:
	var norm: Variant = JSON.parse_string(JSON.stringify(snap))
	return JSON.stringify(_strip_ids(norm))


func _test_scene_soak(t: Object) -> void:
	var bus := NetTestBus.new()
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 24680)
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "阿宏", false)
	var p2 := _mk_client(bus, 101, "小美", false)
	var spec := _mk_client(bus, 102, "觀眾", true)
	for c in [host, p2, spec]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("soak 房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)

	for round in ROUNDS:
		# 開局：首局 start_battle；其後 rematch→兩席就緒→再開新局（新 seed）。
		host.opening_snapshot = {}
		p2.opening_snapshot = {}
		if round == 0:
			host.start_battle(30000 + round)
		else:
			host.rematch()
			p2.rematch()
			host.start_battle(30000 + round)
		t.ok(not host.opening_snapshot.is_empty() and not p2.opening_snapshot.is_empty(),
			"soak[%d]：兩端收到開局快照" % round)

		var hb: Node = _mk_battle(host, "player1", host.opening_snapshot)
		var pb: Node = _mk_battle(p2, "player2", p2.opening_snapshot)
		var sess: NetGameSession = server._sessions[rid]

		# 第 2 局：旁觀者中途加入 → 收補送快照、建旁觀場景＝server。
		var sb: Node = null
		if round == 1:
			spec.opening_snapshot = {}
			spec.join_room(rid, "", true)
			t.ok(not spec.opening_snapshot.is_empty(), "soak：旁觀者中途加入收到補送快照")
			sb = _mk_battle(spec, "", spec.opening_snapshot, true)
			t.eq(sb._views.size(), (spec.opening_snapshot.get("pieces", []) as Array).size(),
				"soak：旁觀場景盤面＝補送快照棋子數")

		# 強制終局（設分數過門檻→當前玩家 end_turn，server 權威判定）。
		sess.core.score = sess.core.config.win_threshold
		var cur: String = sess.core.current_player()
		(hb if cur == "player1" else pb)._do("end_turn", -1, -1)
		t.ok(sess.core.is_over(), "soak[%d]：server 權威終局" % round)

		# 兩端最終公開快照＝server 且彼此一致。
		var sc := _canon(sess.snapshot())
		t.eq(_canon(hb._last_net_snapshot), sc, "soak[%d]：host 端＝server" % round)
		t.eq(_canon(pb._last_net_snapshot), sc, "soak[%d]：p2 端＝server" % round)
		if sb != null:
			t.eq(_canon(sb._last_net_snapshot), sc, "soak：旁觀端＝server")
			spec.leave_room()
			sb.free()
		hb.free()
		pb.free()

	# 多局後房間仍存續（末局 ended），成員未變。
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_ENDED, "soak：連打多局後房間存續（ended）")
	t.eq(int(server.rooms.member_view(rid)["seats"]["player1"]), 100, "soak：P1 席位不變")
	t.eq(int(server.rooms.member_view(rid)["seats"]["player2"]), 101, "soak：P2 席位不變")

	server.free()
	host.free()
	p2.free()
	spec.free()
