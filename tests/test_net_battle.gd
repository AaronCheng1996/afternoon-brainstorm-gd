# P12-6 驗收：連線對戰核心（server 權威）。見 docs/rebuild/10_連線版本.md §4/§6。
# 三層，各自忠實（沿用 P12-5「同程序匯流排」手法，@rpc-over-ENet 整合待運行樹 P12-7/11）：
#   (A) NetCodec：GameAction 白名單／不可信輸入拒收；GameEvent 經 JSON 往返（Vector2i↔[x,y]）還原。
#   (B) NetGameSession：開局／apply_action 換手／server 權威回合計時逾時 end_turn。
#   (C) NetGameServer 同程序 _Bus：兩 client 走完整局（AI 驅動、參考 session 逐步鎖定）——
#       server 權威核心／兩 client 快照與參考「逐位一致」；非當前玩家與旁觀者行動被拒；
#       server tick 逾時廣播換手。
# 純 RefCounted／Node free 乾淨 → 維持零新洩漏。
extends RefCounted


func run(t: Object) -> void:
	_test_codec(t)
	_test_session(t)
	_test_full_game(t)
	_test_turn_reject(t)
	_test_spectator_reject(t)
	_test_server_timeout(t)


# ---------------- (A) NetCodec ----------------

func _test_codec(t: Object) -> void:
	# action 編碼往返（經 JSON，模擬傳輸）。
	var a := GameAction.new("play_card", "player1")
	a.board_x = 2; a.board_y = 3; a.hand_index = 4
	var wire: Variant = JSON.parse_string(JSON.stringify(NetCodec.encode_action(a)))
	var back := NetCodec.decode_action(wire, "player2")
	t.eq(back.action_type, "play_card", "codec：action type 還原")
	t.eq(back.player, "player2", "codec：player 由呼叫端指派（非 client 值）")
	t.eq(back.board_x, 2, "codec：board_x 還原（int）")
	t.eq(back.hand_index, 4, "codec：hand_index 還原")

	# 不可信輸入：非字典／未白名單型別 → null。
	t.ok(NetCodec.decode_action("nope", "player1") == null, "codec：非字典拒收")
	t.ok(NetCodec.decode_action({"type": "quit"}, "player1") == null, "codec：quit 不可經網路")
	t.ok(NetCodec.decode_action({"type": "hack"}, "player1") == null, "codec：未知型別拒收")

	# event 編碼往返（Vector2i 鍵 from/to/at）。
	var e := GameEvent.attack(Vector2i(1, 2), Vector2i(3, 0), 0.32)
	var ew: Variant = JSON.parse_string(JSON.stringify(NetCodec.encode_event(e)))
	var ed := NetCodec.decode_event(ew)
	t.eq(ed.kind, GameEvent.Kind.ATTACK, "codec：event kind 還原")
	t.eq(ed.data["from"], Vector2i(1, 2), "codec：from 還原為 Vector2i")
	t.eq(ed.data["to"], Vector2i(3, 0), "codec：to 還原為 Vector2i")
	t.ok(absf(float(ed.data["delay"]) - 0.32) < 0.0001, "codec：delay（float）還原")

	# 批次往返＋壞資料略過。
	var batch := NetCodec.encode_events([GameEvent.move(Vector2i(0, 0), Vector2i(1, 1)),
		GameEvent.death(Vector2i(2, 2), 0.1)])
	var decoded := NetCodec.decode_events(JSON.parse_string(JSON.stringify(batch)))
	t.eq(decoded.size(), 2, "codec：批次往返數量一致")
	t.eq(decoded[0].data["from"], Vector2i(0, 0), "codec：批次[0] from 還原")
	t.eq(decoded[1].kind, GameEvent.Kind.DEATH, "codec：批次[1] kind 還原")
	t.eq(NetCodec.decode_events("not array").size(), 0, "codec：非陣列回空")


# ---------------- (B) NetGameSession ----------------

func _test_session(t: Object) -> void:
	var s := NetGameSession.new()
	var opening := s.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, 99, null)
	t.ok(s.core != null and not s.core.is_over(), "session：core 就緒、未結束")
	t.eq(s.core.current_player(), "player1", "session：先手 player1")
	t.ok(opening is Array, "session：start 回傳開局事件陣列")

	# 出一張單位牌（合法）→ apply_action ok、手牌減少。
	var act := _legal_action(s.core)
	var before := s.core.player1.hand.size()
	var r := s.apply_action("player1", act)
	t.ok(r["ok"], "session：合法行動 apply 成功")
	if act.action_type == "play_card":
		t.eq(s.core.player1.hand.size(), before - 1, "session：出牌後手牌 -1")

	# end_turn 換手（turn_changed）。
	var r2 := s.apply_action("player1", GameAction.new("end_turn", "player1"))
	t.ok(r2["ok"] and bool(r2["turn_changed"]), "session：end_turn 換手")
	t.eq(s.core.current_player(), "player2", "session：換手到 player2")

	# 快照不含 seed／牌庫序（D19 鐵則，再保險一次）。
	var snap_json := JSON.stringify(s.snapshot())
	t.ok(not snap_json.contains("seed") and not snap_json.contains("draw_pile"),
		"session：快照不含 seed／draw_pile（D19）")

	# server 權威回合計時：逾時自動 end_turn。
	var s2 := NetGameSession.new()
	s2.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, 99, null, true, 5.0)
	var turn0: int = s2.core.turn_number
	t.ok(not s2.tick(2.0)["ok"], "session：未逾時 tick 不動作")
	var fired := s2.tick(4.0)
	t.ok(bool(fired["ok"]) and bool(fired["turn_changed"]), "session：逾時觸發 end_turn")
	t.eq(s2.core.turn_number, turn0 + 1, "session：逾時換手（server 權威）")


# ---------------- (C) 同程序匯流排：完整連線對戰 ----------------

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
	var last_error: String = ""
	var last_snapshot: Dictionary = {}
	var event_count: int = 0
	var got_over: bool = false
	var last_reject: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		lobby_error.connect(func(reason): last_error = reason)
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


# 建 server＋兩玩家（＋可選旁觀者），跑到「房間 battling、session 建立」。回傳字典。
func _boot_battle(bus: _Bus, seed_value: int, with_spectator: bool = false) -> Dictionary:
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 12321)   # 決定性房碼
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	var clients := [host, p2]
	var spec: _WiredClient = null
	if with_spectator:
		spec = _mk_client(bus, 102, "看客", true)
		clients.append(spec)
	for c in clients:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("戰鬥房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	if with_spectator:
		spec.join_room(rid, "", true)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_battle(seed_value)   # 開發旗標：跳過 BP、預設牌組
	return {"server": server, "host": host, "p2": p2, "spec": spec, "rid": rid}


func _test_full_game(t: Object) -> void:
	var seed_value := 4242
	var bus := _Bus.new()
	var b := _boot_battle(bus, seed_value)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]

	# 開局：兩 client 皆收到開局快照。
	t.ok(not host.last_snapshot.is_empty() and not p2.last_snapshot.is_empty(),
		"full：開局兩 client 皆收快照")
	t.ok(server._sessions.has(rid), "full：server 建立權威 session")

	# 參考 session（同 seed／同預設牌組）逐步鎖定；AI 驅動雙方產生行動流。
	var ref := NetGameSession.new()
	ref.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, seed_value, null)
	var ai1 := AIController.new("white", Balance, "player1")
	var ai2 := AIController.new("white", Balance, "player2")
	var now := 0
	var guard := 0
	while not ref.core.is_over() and ref.core.turn_number < 120 and guard < 12000:
		guard += 1
		now += 1000
		var cur: String = ref.core.current_player()
		var acts: Array = (ai1 if cur == "player1" else ai2).tick(ref.core, now, false)
		if acts.is_empty():
			continue
		var action: GameAction = acts[0]
		(host if cur == "player1" else p2).send_action(action)   # 經網路送 server
		ref.apply_action(cur, action)                            # 參考逐步鎖定

	t.ok(guard < 12000, "full：對局未卡死")
	t.ok(host.event_count > 0 and p2.event_count > 0, "full：兩 client 皆收到事件流")

	# 若尚未終局，強制一次 end_turn 以取得反映最終權威狀態的廣播快照。
	if not ref.core.is_over():
		var cur2: String = ref.core.current_player()
		var et := GameAction.new("end_turn", cur2)
		(host if cur2 == "player1" else p2).send_action(et)
		ref.apply_action(cur2, et)

	var sess: NetGameSession = server._sessions[rid]

	# 逐位一致（server 權威核心 vs 參考）：分數／回合／統計 export／完整公開快照。
	t.eq(sess.core.score, ref.core.score, "full：server 分數＝參考")
	t.eq(sess.core.turn_number, ref.core.turn_number, "full：server 回合＝參考")
	t.eq(JSON.stringify(sess.core.stats.export_for_charts()),
		JSON.stringify(ref.core.stats.export_for_charts()), "full：統計 export 逐位一致")
	# 公開快照逐位一致（排除 instance_id——它是行程內物件識別碼，兩顆獨立 core 本就不同，非對局狀態）。
	t.eq(JSON.stringify(_strip_ids(sess.snapshot())), JSON.stringify(_strip_ids(GameSnapshot.encode(ref.core))),
		"full：server 公開快照＝參考（逐位，除 instance_id）")

	# 兩 client 收到的最終快照＝server（且彼此一致，D19 單一公開快照）。
	t.eq(int(host.last_snapshot.get("score", 999)), sess.core.score, "full：host 快照分數＝server")
	t.eq(int(p2.last_snapshot.get("score", 999)), sess.core.score, "full：p2 快照分數＝server")
	t.eq(int(host.last_snapshot.get("turn_number", -1)), sess.core.turn_number,
		"full：host 快照回合＝server")
	t.eq(JSON.stringify(host.last_snapshot), JSON.stringify(p2.last_snapshot),
		"full：兩 client 快照彼此一致（單一公開快照）")

	server.free()
	host.free(); p2.free()


# 非當前玩家的行動被 server 拒（not_your_turn）；權威核心不受影響。
func _test_turn_reject(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_battle(bus, 555)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]
	t.eq(sess.core.current_player(), "player1", "reject：開局先手 player1")
	var turn_before := sess.core.turn_number

	# player2（非當前）送行動 → 被拒。
	var illegal := GameAction.new("end_turn", "player2")
	p2.send_action(illegal)
	t.eq(p2.last_reject, NetMessage.REASON_NOT_YOUR_TURN, "reject：非當前玩家行動被拒")
	t.eq(sess.core.turn_number, turn_before, "reject：權威核心回合未變")

	# 對照：當前玩家（player1）同型別行動可行。
	host.send_action(GameAction.new("end_turn", "player1"))
	t.eq(sess.core.turn_number, turn_before + 1, "reject：當前玩家行動生效換手")

	server.free()
	host.free(); p2.free()


# 旁觀者的行動一律被 server 拒（唯讀由 server 保證，不只 UI）。
func _test_spectator_reject(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_battle(bus, 777, true)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var spec: _WiredClient = b["spec"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]
	var turn_before := sess.core.turn_number

	spec.send_action(GameAction.new("end_turn", "player1"))
	t.eq(spec.last_reject, NetMessage.REASON_SPECTATOR_ACTION, "spec：旁觀者行動被拒")
	t.eq(sess.core.turn_number, turn_before, "spec：權威核心未受旁觀者影響")

	server.free()
	host.free(); p2.free(); spec.free()


# server tick 逾時：權威 end_turn 並廣播事件＋校正快照給全房。
func _test_server_timeout(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_battle(bus, 888)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]
	# 開發旗標開戰預設關計時；此處手動啟用以驗 server 主迴圈的逾時廣播。
	sess.turn_timer.configure(true, 3.0)
	sess.turn_timer.start()
	var turn_before := sess.core.turn_number

	server.tick_sessions(1.0)
	t.eq(sess.core.turn_number, turn_before, "timeout：未逾時不換手")
	server.tick_sessions(3.0)   # 累計 4.0 > 3.0 → 逾時
	t.eq(sess.core.turn_number, turn_before + 1, "timeout：server 權威逾時 end_turn 換手")
	# end_turn 本身可能不產生 GameEvent（僅結算＋換手）；換手校正快照廣播全房＝逾時廣播的實據。
	t.eq(int(host.last_snapshot.get("turn_number", -1)), sess.core.turn_number,
		"timeout：換手校正快照廣播（host）")
	t.eq(int(p2.last_snapshot.get("turn_number", -1)), sess.core.turn_number,
		"timeout：換手校正快照廣播（p2）")

	server.free()
	host.free(); p2.free()


# ---------------- 共用：產生一個合法行動（出第一張單位牌到第一個空格，否則 end_turn）----------------

# 深拷貝快照並移除每棋子的 instance_id（行程內物件識別碼，跨獨立 core 不可比，非對局狀態）。
func _strip_ids(snap: Dictionary) -> Dictionary:
	var s := snap.duplicate(true)
	for p in s.get("pieces", []):
		(p as Dictionary).erase("instance_id")
	return s


func _legal_action(core: GameCore) -> GameAction:
	var p: PlayerState = core.get_player(core.current_player())
	var empties: Array = AIQuery.empty_positions(core)
	if not empties.is_empty():
		for i in p.hand.size():
			if AIQuery.is_playable_unit_card(p.hand[i]):
				var a := GameAction.new("play_card", core.current_player())
				a.hand_index = i
				a.board_x = empties[0].x
				a.board_y = empties[0].y
				return a
	return GameAction.new("end_turn", core.current_player())
