# P12-18 驗收：伺服器回放檔下載（D19 2026-07-18 修訂：終局後 seed 公開）。見 10 §11.2-7／06 P12-18。
# 沿用同程序匯流排（@rpc-over-ENet 跨機屬【人工】）：一局 AI 對戰打到終局後，client 向 server
# 索取本局 ReplayLog（JSONL，含 seed），斷言——
#   (A) 終局後可下載：收到 JSONL＋含 seed＋牌組；`ReplayLog.from_jsonl→simulate` 重播的最終
#       分數/回合/統計 export 與 server 權威核心逐位一致（決定性、P11-2 格式）。
#   (B) 對局進行中拒收：房態 battling（seed 仍隱藏，防實時模擬未來）→ 回 no_replay、無回放送達。
# 純 RefCounted／全部 free → 維持零新洩漏。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")


func run(t: Object) -> void:
	_test_download_after_over(t)
	_test_refused_during_battle(t)


# ---------------- 同程序匯流排 ----------------


class _WiredServer extends NetGameServer:
	var bus: NetTestBus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var got_replay: String = ""
	var last_lobby_error: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		replay_received.connect(func(j): got_replay = j)
		lobby_error.connect(func(e): last_lobby_error = e)


func _mk_client(bus: NetTestBus, id: int, nick: String) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


func _boot(bus: NetTestBus, seed_value: int) -> Dictionary:
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 24680)
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host")
	var p2 := _mk_client(bus, 101, "p2")
	for c in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("回放房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_battle(seed_value)
	return {"server": server, "host": host, "p2": p2, "rid": rid}


# AI 驅動至終局或回合上限（行動經對應席位的 client 送 server）。
func _drive(sess: NetGameSession, host: _WiredClient, p2: _WiredClient, until_turn: int) -> void:
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
		(host if cur == "player1" else p2).send_action(acts[0])


# ---------------- (A) 終局後可下載並可決定性重播 ----------------

func _test_download_after_over(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot(bus, 24242)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]

	_drive(sess, host, p2, 200)
	t.ok(sess.core.is_over(), "replay-dl：對局打到終局")
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_ENDED, "replay-dl：房態＝ended")

	# 終局後請求回放 → 收到 JSONL（含 seed，D19 修訂）。
	host.request_replay()
	t.ok(not host.got_replay.is_empty(), "replay-dl：終局後收到回放 JSONL")
	t.ok(host.got_replay.contains("\"seed\""), "replay-dl：JSONL 含 seed（終局後公開）")

	# 重建 ReplayLog → simulate → 最終狀態與 server 權威核心逐位一致（決定性）。
	var log := ReplayLog.from_jsonl(host.got_replay)
	t.eq(log.seed, sess.replay.seed, "replay-dl：重建的 seed＝server 紀錄")
	var sim := ReplayLog.simulate(log, null)
	t.eq(sim.score, sess.core.score, "replay-dl：重播分數＝權威核心")
	t.eq(sim.turn_number, sess.core.turn_number, "replay-dl：重播回合＝權威核心")
	t.eq(JSON.stringify(sim.stats.export_for_charts()),
		JSON.stringify(sess.core.stats.export_for_charts()), "replay-dl：重播統計 export＝權威核心")
	t.eq(sim.winner_name(), sess.core.winner_name(), "replay-dl：重播勝方＝權威核心")

	# 旁觀者/雙方皆可下載：p2 亦能取得同一份。
	p2.request_replay()
	t.eq(p2.got_replay, host.got_replay, "replay-dl：雙方取得同一份回放")

	server.free()
	host.free()
	p2.free()


# ---------------- (B) 對局進行中拒收（seed 仍隱藏）----------------

func _test_refused_during_battle(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot(bus, 555)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]

	t.eq(server.rooms.state_of(rid), RoomManager.STATE_BATTLING, "replay-dl：對局進行中（battling）")
	t.ok(not sess.core.is_over(), "replay-dl：尚未終局")
	host.request_replay()
	t.ok(host.got_replay.is_empty(), "replay-dl：進行中不下發回放（seed 仍隱藏）")
	t.eq(host.last_lobby_error, NetMessage.REASON_NO_REPLAY, "replay-dl：進行中請求回 no_replay")

	server.free()
	host.free()
	p2.free()
