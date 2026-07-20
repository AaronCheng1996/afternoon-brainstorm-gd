# P12-10 驗收：斷線重連（席位 token）。見 docs/rebuild/10_連線版本.md §8。
# 沿用 P12-5/6/8/9「同程序匯流排」手法（@rpc-over-ENet 整合待運行樹，實機跨機屬【人工】）：
#   (A) 入座即發席位 token（建房 P1、加入 P2 各私下收到，不進廣播房態）。
#   (B) 對戰中玩家斷線 → 席位保留（held、不放給新人、不解散）、對手看到 held、計時暫停；
#       帶對的 token 重連 → 收復席位、補送快照＝server、對手看到 held 清除、計時恢復、可續玩。
#   (C) 錯 token 重連 → lobby_error(bad_token)，held 席位不受影響。
#   (D) 逾時未回 → 判定：對戰中對手判勝（game_over winner=對手、reason=forfeit、房 ended）。
#   (E) 旁觀者斷線 → 直接移除（無重連機制，§7）。
# 純 RefCounted／Node free 乾淨 → 維持零新洩漏。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")


func run(t: Object) -> void:
	_test_token_issuance(t)
	_test_reconnect_roundtrip(t)
	_test_bad_token(t)
	_test_timeout_forfeit(t)
	_test_spectator_no_hold(t)


# ---------------- 同程序匯流排（沿用 test_net_spectator）----------------


class _WiredServer extends NetGameServer:
	var bus: NetTestBus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var last_error: String = ""
	var last_token: String = ""
	var last_snapshot: Dictionary = {}
	var last_over: Dictionary = {}
	var got_over: bool = false
	var closed_reason: String = ""
	var event_count: int = 0
	var last_reject: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		lobby_error.connect(func(reason): last_error = reason)
		seat_token_received.connect(func(tok, _rid, _seat): last_token = tok)
		snapshot_received.connect(func(s): last_snapshot = s)
		battle_events.connect(func(e): event_count += (e as Array).size())
		game_over.connect(func(i): got_over = true; last_over = i; last_snapshot = i.get("snapshot", last_snapshot))
		room_closed.connect(func(_rid, reason): closed_reason = reason)
		action_rejected.connect(func(reason, _m): last_reject = reason)


func _mk_client(bus: NetTestBus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


# 建 server＋兩玩家並開一間房（尚未開始 BP／對戰）。
func _boot_room(bus: NetTestBus) -> Dictionary:
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 24680)   # 決定性房碼／token
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	for c: _WiredClient in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("重連房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	return {"server": server, "host": host, "p2": p2, "rid": rid}


# ---------------- (A) 入座即發席位 token ----------------

func _test_token_issuance(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	t.ok(host.last_token.length() == 16, "token：房主入座收到 16 碼席位 token")
	t.ok(p2.last_token.length() == 16, "token：P2 入座收到席位 token")
	t.ok(host.last_token != p2.last_token, "token：兩席 token 不同")
	# token 為 server-only：不進廣播房態（member_view 無 token/password）。
	t.ok(not host.last_room.has("tokens") and not host.last_room.has("password"),
		"token：廣播房態不外送 token／密碼")
	t.eq(host.seat_token(), host.last_token, "token：client 存下 token 供重連")

	b["server"].free()
	host.free(); p2.free()


# ---------------- (B) 斷線→held→重連收復席位（含計時暫停/恢復）----------------

func _test_reconnect_roundtrip(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	host.start_battle(4242)   # 開發旗標：跳過 BP、預設牌組開戰
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_BATTLING, "rc：進入 battling")
	var sess: NetGameSession = server._sessions[rid]
	# 開回合計時（server 權威），驗證暫停/恢復。先手為 player1（host）。
	sess.turn_timer.configure(true, 5.0)
	sess.turn_timer.start()
	var turn_before: int = sess.core.turn_number
	var p2_token: String = p2.seat_token()

	# P2 斷線 → 席位保留（held）、不解散、對手看到 held。
	server._on_peer_left(p2.my_id)
	t.ok(server.rooms.has_held_seat(rid), "rc：P2 斷線→席位 held")
	t.eq(server.rooms.seat_peer(rid, RoomManager.SEAT_P2), 0, "rc：held 席位無 live peer")
	t.ok(server.rooms.has_room(rid), "rc：對局中掉線不解散")
	t.ok(bool(host.last_room.get("held", {}).get("player2", false)), "rc：對手看到 P2 等待重連")

	# 計時暫停：held 期間 tick 不推進回合（hold 60s 未逾時）。
	server.tick_sessions(10.0)
	t.eq(sess.core.turn_number, turn_before, "rc：等待重連期間回合計時暫停")

	# 帶 token 重連（新連線 id=102）。
	var p2b := _mk_client(bus, 102, "p2-回", false)
	p2b._token = p2_token
	bus.add(p2b.my_id, p2b)
	p2b._on_connected()   # 送 hello{token} → server 認證→重連
	t.eq(server.rooms.seat_peer(rid, RoomManager.SEAT_P2), 102, "rc：重連收復席位（新 peer id）")
	t.ok(not server.rooms.has_held_seat(rid), "rc：重連後 held 清除")
	t.ok(not bool(host.last_room.get("held", {}).get("player2", false)), "rc：對手看到 held 清除")
	# 補送快照＝server 逐位一致（同一顆 core）。
	t.ok(not p2b.last_snapshot.is_empty(), "rc：重連者收到補送快照")
	t.eq(JSON.stringify(p2b.last_snapshot), _norm(sess.snapshot()), "rc：補送快照與 server 一致")
	# D19：含雙方手牌、不含 seed／牌庫序。
	var snap_json := JSON.stringify(p2b.last_snapshot)
	t.ok((p2b.last_snapshot.get("hands", {}) as Dictionary).has("player2")
		and not snap_json.contains("seed") and not snap_json.contains("draw_pile"),
		"rc：補送快照公開手牌、不含 seed（D19）")

	# 計時恢復：重連後 tick 推進→逾時 end_turn（回合前進），證明恢復。
	server.tick_sessions(10.0)
	t.ok(sess.core.turn_number > turn_before, "rc：重連後回合計時恢復（逾時 end_turn）")

	# 重連者可續玩：送合法行動不被拒（此時輪到 player2）。
	if sess.core.current_player() == RoomManager.SEAT_P2:
		var ev_before := p2b.event_count
		p2b.send_action(_legal_action(sess.core))
		t.eq(p2b.last_reject, "", "rc：重連者行動不被拒（席位已收復）")
		t.ok(p2b.event_count > ev_before, "rc：重連者行動被權威核心接受並廣播")

	server.free()
	host.free(); p2.free(); p2b.free()


# ---------------- (C) 錯 token 重連被拒、held 不受影響 ----------------

func _test_bad_token(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	b["host"].start_battle(4242)
	server._on_peer_left(p2.my_id)   # P2 掉線→held
	t.ok(server.rooms.has_held_seat(rid), "bad：P2 held")

	# 亂填 token 的新連線 → lobby_error(bad_token)，席位仍 held、未被收復。
	var intruder := _mk_client(bus, 103, "亂入", false)
	intruder._token = "NOTAVALIDTOKEN00"
	bus.add(intruder.my_id, intruder)
	intruder._on_connected()
	t.eq(intruder.last_error, NetMessage.REASON_BAD_TOKEN, "bad：錯 token 重連回 bad_token")
	t.eq(server.rooms.room_of(103), "", "bad：錯 token 者未入房")
	t.ok(server.rooms.has_held_seat(rid), "bad：held 席位不受錯 token 影響")
	t.eq(server.rooms.seat_peer(rid, RoomManager.SEAT_P2), 0, "bad：席位未被錯 token 收復")

	server.free()
	b["host"].free(); p2.free(); intruder.free()


# ---------------- (D) 逾時未回 → 對手判勝 ----------------

func _test_timeout_forfeit(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	server.seat_hold_seconds = 0.5   # 短保留秒數（測試決定性）
	host.start_battle(4242)
	server._on_peer_left(p2.my_id)   # P2 掉線→held（0.5s）
	t.ok(server.rooms.has_held_seat(rid), "ff：P2 held（0.5s）")

	# 推進超過保留秒數 → 逾時判定：對手（player1）判勝。
	server.tick_sessions(1.0)
	t.ok(host.got_over, "ff：逾時→對手收到終局")
	t.eq(String(host.last_over.get("winner", "")), RoomManager.SEAT_P1, "ff：對手（player1）判勝")
	t.eq(String(host.last_over.get("reason", "")), NetMessage.REASON_OPPONENT_FORFEIT,
		"ff：終局原因＝對手掉線判勝")
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_ENDED, "ff：房間進入 ended")
	t.ok(not server.rooms.has_held_seat(rid), "ff：逾時後 held 席位已放棄")

	server.free()
	host.free(); p2.free()


# ---------------- (E) 旁觀者斷線直接移除（無重連）----------------

func _test_spectator_no_hold(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var rid: String = b["rid"]
	b["host"].start_battle(4242)
	var spec := _mk_client(bus, 104, "看客", true)
	bus.add(spec.my_id, spec)
	spec._on_connected()
	spec.join_room(rid, "", true)
	t.eq(server.rooms.room_of(104), rid, "sp：旁觀者已入房")

	server._on_peer_left(spec.my_id)   # 旁觀者斷線 → 直接移除、無 held
	t.eq(server.rooms.room_of(104), "", "sp：旁觀者斷線後直接移除")
	t.ok(not server.rooms.has_held_seat(rid), "sp：旁觀者斷線不產生 held")
	t.ok(server.rooms.has_room(rid), "sp：房間存續（玩家仍在）")

	server.free()
	b["host"].free(); b["p2"].free(); spec.free()


# ---------------- 共用 ----------------

func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


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
