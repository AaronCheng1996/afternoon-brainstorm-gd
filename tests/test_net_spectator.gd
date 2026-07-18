# P12-9 驗收：旁觀系統（中途加入補送＋唯讀保證）。見 docs/rebuild/10_連線版本.md §7。
# 沿用 P12-5/6/8「同程序匯流排」手法（@rpc-over-ENet 整合待運行樹）：
#   (A) 中途加入 battling 房：旁觀者除房態外補送當前公開快照＝server，且＝雙方玩家；D19 手牌
#       公開、不含 seed／牌庫序；此後事件流續播（玩家行動 → 旁觀者收事件＋校正快照同步）。
#   (B) 中途加入 drafting 房：補送當前公開選秀 view＝server；此後選秀行動 → 旁觀者狀態同步。
#   (C) 中途加入 ended 房：補送終局快照＋勝方（可看統計）。
#   (D) 唯讀由 server 保證：旁觀者送 action／draft_action 一律被拒（不只 UI）；上鎖房旁觀驗密碼、
#       關觀戰的房拒旁觀。
# 純 RefCounted／Node free 乾淨 → 維持零新洩漏。
extends RefCounted

# BP 測試用固定牌組（沿用 test_net_draft）。
const P1_FIRST6 := ["ADCW", "ADCW", "APW", "APW", "TANKW", "TANKW"]
const P2_PICK12 := ["ADCW", "ADCW", "APW", "APW", "TANKW", "TANKW",
	"HFW", "HFW", "LFW", "LFW", "ASSW", "ASSW"]


func run(t: Object) -> void:
	_test_spectate_midbattle(t)
	_test_spectate_middraft(t)
	_test_spectate_ended(t)
	_test_spectate_password_and_toggle(t)


# ---------------- 同程序匯流排（沿用 test_net_battle/draft）----------------

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
	var last_draft: Dictionary = {}
	var last_snapshot: Dictionary = {}
	var last_over: Dictionary = {}
	var got_over: bool = false
	var event_count: int = 0
	var last_reject: String = ""

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		lobby_error.connect(func(reason): last_error = reason)
		draft_updated.connect(func(d): last_draft = d)
		snapshot_received.connect(func(s): last_snapshot = s)
		battle_events.connect(func(e): event_count += (e as Array).size())
		game_over.connect(func(i): got_over = true; last_over = i; last_snapshot = i.get("snapshot", last_snapshot))
		action_rejected.connect(func(reason, _m): last_reject = reason)
		draft_rejected.connect(func(reason, _m): last_reject = reason)


func _mk_client(bus: _Bus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


# 建 server＋兩玩家並開一間房（尚未開始 BP／對戰）。回傳字典。
func _boot_room(bus: _Bus, allow_spectators: bool = true, locked: bool = false,
		password: String = "") -> Dictionary:
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 12321)   # 決定性房碼
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	for c: _WiredClient in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("旁觀房", locked, password, allow_spectators, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, password, false)
	host.set_ready(true)
	p2.set_ready(true)
	return {"server": server, "host": host, "p2": p2, "rid": rid}


# 讓一個新旁觀者連上並加入既有房（模擬對局中途加入）。
func _join_spectator(bus: _Bus, id: int, rid: String, password: String = "") -> _WiredClient:
	var spec := _mk_client(bus, id, "看客", true)
	bus.add(id, spec)
	spec._on_connected()
	spec.join_room(rid, password, true)
	return spec


# ---------------- (A) 中途加入對戰中的房 ----------------

func _test_spectate_midbattle(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var rid: String = b["rid"]
	host.start_battle(4242)   # 開發旗標：跳過 BP、預設牌組開戰
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_BATTLING, "midbattle：房間進入 battling")
	var sess: NetGameSession = server._sessions[rid]

	# 對戰進行到一半（先手 player1 出一張合法牌，讓盤面非開局原狀）。
	host.send_action(_legal_action(sess.core))

	# 旁觀者於對戰中途加入 → 立即補送當前公開快照。
	var spec := _join_spectator(bus, 102, rid)
	t.ok(not spec.last_snapshot.is_empty(), "midbattle：中途加入者收到補送快照")
	# 重建狀態與 server 一致（同一顆 core，instance_id 亦相同 → 可直接逐位比對）。
	t.eq(JSON.stringify(spec.last_snapshot), _norm(sess.snapshot()),
		"midbattle：旁觀者快照與 server 逐位一致")
	# D19：看得到雙方手牌，看不到 seed／牌庫序。
	var hands: Dictionary = spec.last_snapshot.get("hands", {})
	t.ok(hands.has("player1") and hands.has("player2"), "midbattle：快照含雙方手牌（D19）")
	var snap_json := JSON.stringify(spec.last_snapshot)
	t.ok(not snap_json.contains("seed") and not snap_json.contains("draw_pile"),
		"midbattle：快照不含 seed／draw_pile（D19）")

	# 此後廣播續播：現任玩家換手 → 校正快照廣播全房（含旁觀者，_broadcast_to_room 依成員清單）。
	host.send_action(GameAction.new("end_turn", "player1"))
	t.eq(int(spec.last_snapshot.get("turn_number", -1)), sess.core.turn_number,
		"midbattle：後續換手校正快照同步（旁觀者＝server）")

	# (D) 唯讀：旁觀者送 action 一律被 server 拒（現任玩家為 player2，特意用非其席位也不放行）。
	var turn_before := sess.core.turn_number
	spec.send_action(GameAction.new("end_turn", "player2"))
	t.eq(spec.last_reject, NetMessage.REASON_SPECTATOR_ACTION, "midbattle：旁觀者行動被拒")
	t.eq(sess.core.turn_number, turn_before, "midbattle：權威核心未受旁觀者影響")

	server.free()
	host.free(); b["p2"].free(); spec.free()


# ---------------- (B) 中途加入選秀中的房 ----------------

func _test_spectate_middraft(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var rid: String = b["rid"]
	host.start_draft()
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_DRAFTING, "middraft：房間進入 drafting")
	# P1 先選幾張，讓選秀狀態離開開局原狀。
	host.send_draft_action("add_card", "ADCW")
	host.send_draft_action("add_card", "APW")
	var draft: NetDraftSession = server._draft_sessions[rid]

	# 旁觀者中途加入 → 補送當前公開選秀 view。
	var spec := _join_spectator(bus, 102, rid)
	t.ok(not spec.last_draft.is_empty(), "middraft：中途加入者收到補送選秀狀態")
	t.eq(JSON.stringify(spec.last_draft), _norm(draft.view()),
		"middraft：旁觀者選秀 view 與 server 一致")
	t.eq(int(spec.last_draft.get("player1_count", -1)), 2, "middraft：補送 view 反映已選 2 張")
	t.ok(not JSON.stringify(spec.last_draft).contains("seed"), "middraft：選秀 view 不含 seed（D19）")

	# 此後選秀續播：P1 再選 → 旁觀者狀態同步。
	host.send_draft_action("add_card", "TANKW")
	t.eq(int(spec.last_draft.get("player1_count", -1)), 3, "middraft：後續選秀行動同步至旁觀者")

	# (D) 唯讀：旁觀者送選秀行動被拒。
	spec.send_draft_action("add_card", "ADCW")
	t.eq(spec.last_reject, NetMessage.REASON_SPECTATOR_ACTION, "middraft：旁觀者選秀被拒")
	t.eq(draft.state.player1_deck.size(), 3, "middraft：權威選秀狀態未受旁觀者影響")

	server.free()
	host.free(); b["p2"].free(); spec.free()


# ---------------- (C) 中途加入終局的房 ----------------

func _test_spectate_ended(t: Object) -> void:
	var bus := _Bus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var rid: String = b["rid"]
	host.start_battle(4242)
	var sess: NetGameSession = server._sessions[rid]
	# 終局轉換（＝_finish_battle 的房態轉換；session 保留供統計檢視，§6）。
	server.rooms.end_battle(rid)
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_ENDED, "ended：房間進入 ended")

	# 旁觀者於終局後加入 → 補送終局快照＋勝方（可看統計）。
	var spec := _join_spectator(bus, 102, rid)
	t.ok(spec.got_over, "ended：中途加入者收到終局訊息")
	t.ok(not spec.last_over.get("snapshot", {}).is_empty(), "ended：終局訊息含快照（可看統計）")
	t.ok(spec.last_over.has("winner"), "ended：終局訊息含勝方")
	t.eq(JSON.stringify(spec.last_over.get("snapshot", {})), _norm(sess.snapshot()),
		"ended：終局快照與 server 一致")

	server.free()
	host.free(); b["p2"].free(); spec.free()


# ---------------- (D) 上鎖房旁觀驗密碼／關觀戰拒旁觀 ----------------

func _test_spectate_password_and_toggle(t: Object) -> void:
	# 上鎖房：旁觀者同樣需正確密碼（§7）。
	var bus := _Bus.new()
	var b := _boot_room(bus, true, true, "s3cret")
	var server: _WiredServer = b["server"]
	var rid: String = b["rid"]

	var bad := _join_spectator(bus, 103, rid, "wrong")
	t.eq(bad.last_error, NetMessage.REASON_BAD_PASSWORD, "pw：上鎖房旁觀密碼錯被拒")
	t.eq(server.rooms.room_of(103), "", "pw：密碼錯的旁觀者未入房")
	var good := _join_spectator(bus, 104, rid, "s3cret")
	t.eq(good.last_error, "", "pw：正確密碼旁觀加入成功")
	t.eq(server.rooms.player_seat(104), "", "pw：加入者為旁觀者（無席位）")

	server.free()
	b["host"].free(); b["p2"].free(); bad.free(); good.free()

	# 關閉觀戰的房：旁觀請求被拒（受觀戰開關控制，§7）。
	var bus2 := _Bus.new()
	var b2 := _boot_room(bus2, false)   # allow_spectators = false
	var server2: _WiredServer = b2["server"]
	var rid2: String = b2["rid"]
	var no_spec := _join_spectator(bus2, 105, rid2)
	t.eq(no_spec.last_error, NetMessage.REASON_NO_SPECTATE, "toggle：關觀戰的房拒旁觀")

	server2.free()
	b2["host"].free(); b2["p2"].free(); no_spec.free()


# server 端物件經 JSON 往返正規化（int→float 等），與「已過網路」的 client 值同一表示再比對
# （client 收到的皆為 JSON 解析結果；直接比原生 int 會因型別表示差異誤判）。
func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


# ---------------- 共用：產生一個合法行動（出第一張單位牌到第一個空格，否則 end_turn）----------------

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
