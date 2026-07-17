# P12-11 驗收：長跑穩定性（soak）＋ server 端對局紀錄。見 docs/rebuild/10_連線版本.md §9。
# 沿用「同程序匯流排」（@rpc-over-ENet 實機跨機屬【人工】），聚焦「連續多局＋旁觀加入退出＋
# 重連 churn 全程零崩潰、Node free 乾淨」與「server 端 ReplayLog 忠實可重播」：
#   (A) 連續多局（AI 驅動打到終局/回合上限），每局中途 P2 掉線→帶 token 重連→續打到底；
#       全程房間存續、兩端最終公開快照一致；每局 free 乾淨。
#   (B) 旁觀者反覆加入/退出對局中的房：無崩潰、房間與權威核心不受影響、晚加入者收補送快照。
#   (C) server 端 ReplayLog：一局 AI 對戰後，用 ReplayLog.simulate 重播其紀錄→
#       最終分數/回合/統計 export 與權威核心逐位一致（決定性存檔，P11-2 格式，不寫檔）。
# 純 RefCounted／全部 free → 維持零新洩漏基準（39/78）。
extends RefCounted

const SOAK_ROUNDS := 3          # 連續局數（churn）
const SPECTATOR_CYCLES := 4     # 旁觀加入/退出次數
const MAX_TURNS := 200          # 單局回合上限（AI 白對白多半更早分勝負）


func run(t: Object) -> void:
	_test_reconnect_soak(t)
	_test_spectator_soak(t)
	_test_server_replay_determinism(t)


# ---------------- 同程序匯流排（沿用 test_net_battle）----------------

class _Bus extends RefCounted:
	var nodes: Dictionary = {}
	func add(id: int, node: Object) -> void:
		nodes[id] = node
	func route(from_id: int, to_id: int, text: String) -> void:
		var target: Object = nodes.get(to_id, null)
		if target != null:
			target._ingest(from_id, text)


class _WiredServer extends NetGameServer:
	var bus: _Bus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: _Bus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var last_snapshot: Dictionary = {}
	var got_over: bool = false
	var event_count: int = 0
	var last_reject: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		snapshot_received.connect(func(s): last_snapshot = s)
		battle_events.connect(func(e): event_count += (e as Array).size())
		game_over.connect(func(i): got_over = true; last_snapshot = i.get("snapshot", last_snapshot))
		action_rejected.connect(func(reason, _m): last_reject = reason)


func _mk_client(bus: _Bus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


func _boot_battle(bus: _Bus, seed_value: int) -> Dictionary:
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 33333)
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	for c: _WiredClient in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("soak房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_battle(seed_value)
	return {"server": server, "host": host, "p2": p2, "rid": rid}


# AI 驅動：以 server 權威核心的當前狀態產生行動，經對應席位的用戶端送出（重連後席位換人由
# get_client 提供）。驅動至終局或 until_turn；回傳最終 guard（未卡死驗證）。
func _drive(sess: NetGameSession, host: _WiredClient, get_p2: Callable, until_turn: int) -> int:
	var ai1 := AIController.new("white", Balance, "player1")
	var ai2 := AIController.new("white", Balance, "player2")
	var now := 0
	var guard := 0
	while not sess.core.is_over() and sess.core.turn_number < until_turn and guard < 20000:
		guard += 1
		now += 1000
		var cur: String = sess.core.current_player()
		var acts: Array = (ai1 if cur == "player1" else ai2).tick(sess.core, now, false)
		if acts.is_empty():
			continue
		var client: _WiredClient = host if cur == "player1" else (get_p2.call() as _WiredClient)
		client.send_action(acts[0])
	return guard


# ---------------- (A) 連續多局＋每局中途重連 ----------------

func _test_reconnect_soak(t: Object) -> void:
	for r in SOAK_ROUNDS:
		var bus := _Bus.new()
		var b := _boot_battle(bus, 4242 + r * 17)
		var server: _WiredServer = b["server"]
		var host: _WiredClient = b["host"]
		var rid: String = b["rid"]
		var sess: NetGameSession = server._sessions[rid]
		var p2_holder := {"c": b["p2"] as _WiredClient}
		var get_p2 := func() -> _WiredClient: return p2_holder["c"]

		# 打幾回合，讓盤面非開局原狀。
		_drive(sess, host, get_p2, mini(sess.core.turn_number + 5, MAX_TURNS))

		# 中途 P2 掉線→帶 token 重連（新 peer id），續打到底。
		if not sess.core.is_over():
			var token: String = (p2_holder["c"] as _WiredClient).seat_token()
			server._on_peer_left((p2_holder["c"] as _WiredClient).my_id)
			t.ok(server.rooms.has_held_seat(rid), "soak-rc[%d]：掉線→席位 held" % r)
			var p2b := _mk_client(bus, 200 + r, "p2重連", false)
			p2b._token = token
			bus.add(p2b.my_id, p2b)
			p2b._on_connected()
			t.eq(server.rooms.seat_peer(rid, RoomManager.SEAT_P2), p2b.my_id,
				"soak-rc[%d]：重連收復席位" % r)
			t.ok(not server.rooms.has_held_seat(rid), "soak-rc[%d]：重連後 held 清除" % r)
			t.ok(not p2b.last_snapshot.is_empty(), "soak-rc[%d]：重連者收補送快照" % r)
			p2_holder["c"] = p2b

		var guard := _drive(sess, host, get_p2, MAX_TURNS)
		t.ok(guard < 20000, "soak-rc[%d]：對局未卡死" % r)
		t.ok(host.event_count > 0, "soak-rc[%d]：對局有事件流" % r)
		t.ok(server.rooms.has_room(rid), "soak-rc[%d]：全程房間存續" % r)
		# 兩端最終公開快照一致（D19 單一公開快照）。
		t.eq(JSON.stringify(host.last_snapshot),
			JSON.stringify((get_p2.call() as _WiredClient).last_snapshot),
			"soak-rc[%d]：兩端最終快照一致" % r)

		server.free()
		host.free()
		b["p2"].free()
		if p2_holder["c"] != b["p2"]:
			(p2_holder["c"] as _WiredClient).free()


# ---------------- (B) 旁觀者反覆加入/退出 ----------------

func _test_spectator_soak(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_battle(bus, 909)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]
	var p2_holder := {"c": p2}
	var get_p2 := func() -> _WiredClient: return p2_holder["c"]

	var specs: Array = []
	for i in SPECTATOR_CYCLES:
		# 推進一小段對局。
		_drive(sess, host, get_p2, mini(sess.core.turn_number + 2, MAX_TURNS))
		if sess.core.is_over():
			break
		var turn_before := sess.core.turn_number
		# 旁觀者加入→收補送快照（＝server 逐位一致，同顆 core）。
		var spec := _mk_client(bus, 300 + i, "看客%d" % i, true)
		bus.add(spec.my_id, spec)
		spec._on_connected()
		spec.join_room(rid, "", true)
		t.ok(not spec.last_snapshot.is_empty(), "soak-sp[%d]：旁觀者收補送快照" % i)
		t.eq(JSON.stringify(spec.last_snapshot), _norm(sess.snapshot()),
			"soak-sp[%d]：補送快照＝server" % i)
		# 旁觀者行動被拒、權威核心不受影響。
		spec.send_action(GameAction.new("end_turn", sess.core.current_player()))
		t.eq(spec.last_reject, NetMessage.REASON_SPECTATOR_ACTION, "soak-sp[%d]：旁觀者行動被拒" % i)
		t.eq(sess.core.turn_number, turn_before, "soak-sp[%d]：核心未受旁觀者影響" % i)
		# 旁觀者退出（斷線移除）。
		server._on_peer_left(spec.my_id)
		t.eq(server.rooms.room_of(spec.my_id), "", "soak-sp[%d]：旁觀者退出移除" % i)
		t.ok(server.rooms.has_room(rid), "soak-sp[%d]：房間存續" % i)
		specs.append(spec)

	server.free()
	host.free()
	p2.free()
	for s: _WiredClient in specs:
		s.free()


# ---------------- (C) server 端 ReplayLog 決定性 ----------------

func _test_server_replay_determinism(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_battle(bus, 24242)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]
	var p2_holder := {"c": p2}
	var get_p2 := func() -> _WiredClient: return p2_holder["c"]

	_drive(sess, host, get_p2, MAX_TURNS)
	t.ok((sess.replay.actions as Array).size() > 0, "replay：server 錄到 action 流")

	# 用 server 端紀錄重播（P11-2 決定性）→ 最終狀態與權威核心逐位一致。
	var sim := ReplayLog.simulate(sess.replay, null)
	t.eq(sim.score, sess.core.score, "replay：重播分數＝權威核心")
	t.eq(sim.turn_number, sess.core.turn_number, "replay：重播回合＝權威核心")
	t.eq(JSON.stringify(sim.stats.export_for_charts()),
		JSON.stringify(sess.core.stats.export_for_charts()),
		"replay：重播統計 export 逐位一致")
	# 紀錄僅含 seed＋牌組＋action（不含快照/牌庫序）；seed 只在紀錄內、不外流快照。
	t.eq(sess.replay.seed, 24242, "replay：紀錄保存權威 seed（server-only）")

	server.free()
	host.free()
	p2.free()


# ---------------- 共用 ----------------

func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))
