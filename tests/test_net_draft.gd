# P12-8 驗收：連線選秀（BP，server 權威）。見 docs/rebuild/10_連線版本.md §6。
# 三層，各自忠實（沿用 P12-5/6「同程序匯流排」；@rpc-over-ENet 整合待運行樹 P12-7/11）：
#   (A) NetCodec.decode_draft_action：白名單／不可信輸入拒收；player 由呼叫端（server）指派。
#   (B) NetDraftSession：三階段推進／回合閘／完成／server 權威計時逾時 auto_fill_and_advance。
#   (C) NetGameServer 同程序 _Bus：兩 client 走完整 BP——雙方牌組兩端一致、完成後 server 建
#       GameCore 發首份快照；非編輯方與旁觀者的選秀行動被拒。
# 純 RefCounted／Node free 乾淨 → 維持零新洩漏。
extends RefCounted

# BP 測試用固定牌組（單位 ≤2、每階段達最低張數）。
const P1_FIRST6 := ["ADCW", "ADCW", "APW", "APW", "TANKW", "TANKW"]
const P1_LAST6 := ["HFW", "HFW", "LFW", "LFW", "ASSW", "ASSW"]
const P2_PICK12 := ["ADCW", "ADCW", "APW", "APW", "TANKW", "TANKW",
	"HFW", "HFW", "LFW", "LFW", "ASSW", "ASSW"]


func run(t: Object) -> void:
	_test_codec(t)
	_test_session(t)
	_test_session_timeout(t)
	_test_full_draft(t)
	_test_turn_reject(t)
	_test_spectator_reject(t)


# ---------------- (A) NetCodec 選秀行動 ----------------

func _test_codec(t: Object) -> void:
	var a := DraftAction.new("player1", "add_card", "ADCW")
	var wire: Variant = JSON.parse_string(JSON.stringify(NetCodec.encode_draft_action(a)))
	var back := NetCodec.decode_draft_action(wire, "player2")
	t.eq(back.action_type, "add_card", "codec：選秀 type 還原")
	t.eq(back.card_name, "ADCW", "codec：card_name 還原")
	t.eq(back.player, "player2", "codec：player 由呼叫端指派（非 client 值）")

	# 不可信輸入：非字典／未白名單型別 → null。
	t.ok(NetCodec.decode_draft_action("nope", "player1") == null, "codec：非字典拒收")
	t.ok(NetCodec.decode_draft_action({"type": "toggle_timer"}, "player1") == null,
		"codec：本機專用 toggle_timer 不可經網路")
	t.ok(NetCodec.decode_draft_action({"type": "quit"}, "player1") == null, "codec：未知型別拒收")
	t.ok(NetCodec.decode_draft_action({"type": "advance_phase"}, "player1") != null,
		"codec：advance_phase 合法")


# ---------------- (B) NetDraftSession：三階段推進＋回合閘＋完成 ----------------

func _test_session(t: Object) -> void:
	var s := NetDraftSession.new()
	s.start(123)
	t.eq(s.state.phase, "p1_first6", "session：開局階段 p1_first6")
	t.eq(s.state.current_editor(), "player1", "session：先手 P1 先選")

	# 回合閘：非編輯方（P2）此時 add 被拒。
	var r_wrong := s.apply("player2", DraftAction.new("", "add_card", "ADCW"))
	t.ok(not r_wrong["ok"] and r_wrong["message"] == "Not your turn", "session：非編輯方選牌被拒")

	# P1 選滿 6 → 可 advance。
	for c: String in P1_FIRST6:
		t.ok(s.apply("player1", DraftAction.new("", "add_card", c))["ok"], "session：P1 加牌 %s" % c)
	t.eq(s.state.player1_deck.size(), 6, "session：P1 選滿 6")
	var adv1 := s.apply("player1", DraftAction.new("", "advance_phase"))
	t.ok(adv1["ok"] and bool(adv1["phase_advanced"]), "session：階段 1→2 前進")
	t.eq(s.state.phase, "p2_pick12", "session：進入 p2_pick12")
	t.eq(s.state.current_editor(), "player2", "session：換 P2 選")

	# P2 選滿 12 → advance。
	for c: String in P2_PICK12:
		s.apply("player2", DraftAction.new("", "add_card", c))
	s.apply("player2", DraftAction.new("", "advance_phase"))
	t.eq(s.state.phase, "p1_last6", "session：進入 p1_last6")

	# 同名上限：P1 已有 2 張 ADCW，再加被拒（Over limit）。
	var over := s.apply("player1", DraftAction.new("", "add_card", "ADCW"))
	t.ok(not over["ok"] and over["message"] == "Over limit", "session：同名超上限被拒")

	# P1 補滿 12 → advance → done。
	for c: String in P1_LAST6:
		s.apply("player1", DraftAction.new("", "add_card", c))
	var fin := s.apply("player1", DraftAction.new("", "advance_phase"))
	t.ok(bool(fin["done"]), "session：完成（done）")
	t.ok(s.is_done(), "session：is_done()")
	t.eq(s.state.player1_deck.size(), 12, "session：P1 最終 12 張")
	t.eq(s.state.player2_deck.size(), 12, "session：P2 最終 12 張")

	# view 公開且不含 seed（D19）。
	t.ok(not JSON.stringify(s.view()).contains("seed"), "session：view 不含 seed（D19）")
	t.eq(s.decks()[0].size(), 12, "session：decks() 供建 GameCore（P1 12 張）")


# ---------------- (B2) server 權威選秀計時逾時 ----------------

func _test_session_timeout(t: Object) -> void:
	var s := NetDraftSession.new()
	s.start(99, true, 5.0)   # 開選秀計時，5 秒
	t.ok(not s.tick(2.0)["ok"], "timeout：未逾時 tick 不動作")
	var fired := s.tick(4.0)   # 累計 6 > 5 → 逾時
	t.ok(bool(fired["ok"]) and bool(fired["timed_out"]) and bool(fired["phase_advanced"]),
		"timeout：逾時自動補牌並前進")
	t.eq(s.state.phase, "p2_pick12", "timeout：階段由逾時推進（server 權威）")
	t.ok(s.state.player1_deck.size() >= 6, "timeout：P1 被自動補到可進階最低張數")

	# 連續逾時直到 done（純 server 端，不需 client 行動）。
	var guard := 0
	while not s.is_done() and guard < 10:
		guard += 1
		s.tick(6.0)
	t.ok(s.is_done(), "timeout：連續逾時可走完整 BP")
	t.eq(s.state.player1_deck.size(), 12, "timeout：P1 最終 12 張")
	t.eq(s.state.player2_deck.size(), 12, "timeout：P2 最終 12 張")


# ---------------- (C) 同程序匯流排：完整連線選秀 ----------------

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
	var last_draft: Dictionary = {}
	var last_snapshot: Dictionary = {}
	var last_reject: String = ""
	var last_error: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		lobby_error.connect(func(reason): last_error = reason)
		draft_updated.connect(func(d): last_draft = d)
		draft_rejected.connect(func(reason, _m): last_reject = reason)
		snapshot_received.connect(func(s): last_snapshot = s)


func _mk_client(bus: _Bus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


# 建 server＋兩玩家（＋可選旁觀者），跑到「房間 drafting、選秀開始」。回傳字典。
func _boot_draft(bus: _Bus, with_spectator: bool = false) -> Dictionary:
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
	host.create_room("選秀房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	if with_spectator:
		spec.join_room(rid, "", true)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_draft()
	return {"server": server, "host": host, "p2": p2, "spec": spec, "rid": rid}


func _add_cards(client: _WiredClient, cards: Array) -> void:
	for c: String in cards:
		client.send_draft_action("add_card", c)


func _test_full_draft(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_draft(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]

	# 開局：房間 drafting、兩 client 皆收到開局選秀狀態。
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_DRAFTING, "full：房間進入 drafting")
	t.ok(server._draft_sessions.has(rid), "full：server 建立權威選秀 session")
	t.eq(String(host.last_draft.get("phase", "")), "p1_first6", "full：開局階段 p1_first6")
	t.eq(String(host.last_draft.get("editor", "")), "player1", "full：先手 P1 先選")

	# 未就緒即 start_draft 應被拒的對照另測；此處走完整三階段。
	_add_cards(host, P1_FIRST6)
	host.send_draft_action("advance_phase")
	t.eq(String(host.last_draft.get("phase", "")), "p2_pick12", "full：階段 1→2（P2 選）")
	_add_cards(p2, P2_PICK12)
	p2.send_draft_action("advance_phase")
	t.eq(String(host.last_draft.get("phase", "")), "p1_last6", "full：階段 2→3（P1 補）")
	_add_cards(host, P1_LAST6)
	host.send_draft_action("advance_phase")   # → done → 建 GameCore 進對戰

	# 完成：兩端最終牌組一致（單一公開 view）＝預期。
	t.ok(bool(host.last_draft.get("done", false)), "full：host 收到完成狀態")
	t.eq(JSON.stringify(host.last_draft), JSON.stringify(p2.last_draft),
		"full：兩 client 選秀狀態彼此一致（單一公開 view）")
	t.eq(host.last_draft["player1_deck"], P1_FIRST6 + P1_LAST6, "full：P1 牌組＝預期")
	t.eq(host.last_draft["player2_deck"], P2_PICK12, "full：P2 牌組＝預期")

	# 完成後：選秀 session 清除、建立對戰 session、廣播開局快照給全房。
	t.ok(not server._draft_sessions.has(rid), "full：完成後移除選秀 session")
	t.ok(server._sessions.has(rid), "full：完成後 server 建立對戰 session")
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_BATTLING, "full：房間進入 battling")
	t.ok(not host.last_snapshot.is_empty() and not p2.last_snapshot.is_empty(),
		"full：完成後兩 client 皆收開局快照")

	# 對戰 core 的雙方牌組＝選秀結果（PlayerState.deck 為 setup 傳入的母牌組，順序保留；
	# draw_pile 才是洗牌後的工作副本）。→ 選秀決定的牌組正確帶入權威對戰核心。
	var sess: NetGameSession = server._sessions[rid]
	t.eq(sess.core.player1.deck, P1_FIRST6 + P1_LAST6, "full：對戰 P1 牌組＝選秀結果")
	t.eq(sess.core.player2.deck, P2_PICK12, "full：對戰 P2 牌組＝選秀結果")

	server.free()
	host.free(); p2.free()


# 非編輯方的選秀行動被 server 拒（not_your_turn）；權威狀態不受影響。
func _test_turn_reject(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_draft(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]

	# p1_first6：編輯方＝P1。P2 送 add_card → 被拒（回合閘）。
	p2.send_draft_action("add_card", "ADCW")
	t.eq(p2.last_reject, NetMessage.REASON_NOT_YOUR_TURN, "reject：非編輯方選牌被拒")
	var draft: NetDraftSession = server._draft_sessions[rid]
	t.eq(draft.state.player2_deck.size(), 0, "reject：權威狀態未受影響（P2 牌組仍空）")

	# 對照：編輯方（P1）同行動生效。
	host.send_draft_action("add_card", "ADCW")
	t.eq(draft.state.player1_deck.size(), 1, "reject：編輯方選牌生效")

	server.free()
	host.free(); p2.free()


# 旁觀者的選秀行動一律被 server 拒（唯讀由 server 保證）。
func _test_spectator_reject(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_draft(bus, true)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var spec: _WiredClient = b["spec"]
	var rid: String = b["rid"]

	spec.send_draft_action("add_card", "ADCW")
	t.eq(spec.last_reject, NetMessage.REASON_SPECTATOR_ACTION, "spec：旁觀者選秀被拒")
	var draft: NetDraftSession = server._draft_sessions[rid]
	t.eq(draft.state.player1_deck.size(), 0, "spec：權威狀態未受旁觀者影響")

	server.free()
	host.free(); p2.free(); spec.free()
