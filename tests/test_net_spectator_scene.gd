# P12-14 驗收：旁觀者唯讀畫面（battle/draft net 模式的 spectator 變體）。見 10 §7/§11。
# 沿用同程序匯流排（@rpc-over-ENet 跨機屬【人工】）：第三 client 以旁觀身分中途加入，依 server
# catchup（快照/選秀 view）建旁觀場景，斷言——
#   (A) 對戰旁觀：場景重建＝server 快照；行動控制（模式/升級/結束回合）隱藏、雙方手牌唯讀；
#       任何點擊（盤面/手牌/結束回合）**零送信**；後續玩家行動→旁觀場景同步；觀戰人數顯示。
#   (B) 選秀旁觀：場景重建＝server view；進階/移除鈕隱藏、展示卡不可點；點擊零送信；後續同步。
# 場景與 net 物件皆 .free() → 維持零新洩漏。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")
const BattleScene := preload("res://scenes/battle/battle.tscn")
const DraftScene := preload("res://scenes/draft/draft.tscn")


func run(t: Object) -> void:
	_test_battle_spectator_scene(t)
	_test_draft_spectator_scene(t)


# ---------------- 同程序匯流排 ----------------


class _WiredServer extends NetGameServer:
	var bus: NetTestBus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var last_draft: Dictionary = {}
	var last_snapshot: Dictionary = {}
	var sent_actions: int = 0
	var sent_drafts: int = 0

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func send_action(action: GameAction) -> void:
		sent_actions += 1
		super(action)

	func send_draft_action(type: String, card: String = "") -> void:
		sent_drafts += 1
		super(type, card)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		draft_updated.connect(func(d): last_draft = d)
		snapshot_received.connect(func(s): last_snapshot = s)


func _mk_client(bus: NetTestBus, id: int, nick: String, spectate: bool) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_SPECTATE if spectate else NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


# 建 server＋兩玩家並開一間房（尚未開始）。
func _boot_room(bus: NetTestBus) -> Dictionary:
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 24680)
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host", false)
	var p2 := _mk_client(bus, 101, "p2", false)
	for c in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("旁觀場景房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	return {"server": server, "host": host, "p2": p2, "rid": rid}


func _join_spectator(bus: NetTestBus, id: int, rid: String) -> _WiredClient:
	var spec := _mk_client(bus, id, "看客", true)
	bus.add(id, spec)
	spec._on_connected()
	spec.join_room(rid, "", true)
	return spec


func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


# 產生一個合法行動（出第一張單位牌到第一個空格，否則 end_turn）。
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


# ---------------- (A) 對戰旁觀畫面 ----------------

func _test_battle_spectator_scene(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var rid: String = b["rid"]
	host.start_battle(4242)   # 開發旗標：跳過 BP、預設牌組開戰
	var sess: NetGameSession = server._sessions[rid]

	# 對戰進行到一半（先手 player1 出一張合法牌）。
	host.send_action(_legal_action(sess.core))

	# 旁觀者中途加入 → 收 catchup 快照。
	var spec := _join_spectator(bus, 102, rid)
	t.ok(not spec.last_snapshot.is_empty(), "battle：旁觀者收到 catchup 快照")

	# 建旁觀對戰場景（seat="" → boot_net 判定為 spectator）。
	var spec_b: Node = BattleScene.instantiate()
	spec_b.boot_net(spec, "", spec.last_snapshot, true)
	spec_b.set_animation_enabled(false)   # 瞬時：後續事件同步收斂

	t.ok(spec_b._net_spectator, "battle：場景為旁觀模式")
	t.eq(spec_b._views.size(), (spec.last_snapshot.get("pieces", []) as Array).size(),
		"battle：旁觀盤面視圖＝快照棋子數")

	# 行動控制隱藏（模式工具列/升級/結束回合）。
	t.ok(not (spec_b._mode_buttons["attack"] as Button).visible, "battle：旁觀隱藏攻擊模式鈕")
	t.ok(not spec_b._upgrade_btn.visible, "battle：旁觀隱藏升級鈕")
	t.ok(spec_b._end_turn_btn != null and not spec_b._end_turn_btn.visible,
		"battle：旁觀隱藏結束回合鈕")

	# 雙方手牌唯讀（旁觀＝左右兩欄皆 disabled）。P12-20（D21）：旁觀無主視角→左 P1／右 P2。
	t.eq(spec_b._left_seat(), "player1", "battle：旁觀（無主視角）左欄＝P1")
	t.eq(spec_b._right_seat(), "player2", "battle：旁觀右欄＝P2")
	var hand_children: Array = spec_b._left_hand_box.get_children() \
		+ spec_b._right_hand_box.get_children()
	t.ok(hand_children.size() > 0, "battle：兩欄手牌非空（快照含公開手牌）")
	var all_disabled := true
	for c in hand_children:
		if not (c as Button).disabled:
			all_disabled = false
	t.ok(all_disabled, "battle：旁觀雙方手牌欄全唯讀（disabled）")

	# 任何點擊零送信。
	var before := spec.sent_actions
	spec_b._board_click(Vector2i(0, 0))
	spec_b._on_hand_pressed(0)
	spec_b._do("end_turn", -1, -1)
	t.eq(spec.sent_actions, before, "battle：旁觀任何點擊零送信")

	# 觀戰人數顯示（狀態列）。
	spec_b.set_spectator_count(1)
	t.ok(spec_b._net_status_text().contains("觀戰"), "battle：狀態列顯示觀戰人數")
	t.ok(spec_b._net_status_text().contains("旁觀中"), "battle：狀態列顯示旁觀徽章")

	# 後續玩家行動 → 旁觀場景同步（換手校正快照）。
	host.send_action(GameAction.new("end_turn", "player1"))
	t.eq(int(spec_b._last_net_snapshot.get("turn_number", -1)), sess.core.turn_number,
		"battle：後續換手→旁觀場景與 server 同步")

	spec_b.free()
	server.free()
	host.free(); b["p2"].free(); spec.free()


# ---------------- (B) 選秀旁觀畫面 ----------------

func _test_draft_spectator_scene(t: Object) -> void:
	var bus := NetTestBus.new()
	var b := _boot_room(bus)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var rid: String = b["rid"]
	host.start_draft()
	# P1 先選幾張（離開開局原狀）。
	host.send_draft_action("add_card", "ADCW")
	host.send_draft_action("add_card", "APW")
	var draft: NetDraftSession = server._draft_sessions[rid]

	# 旁觀者中途加入 → 收 catchup 選秀 view。
	var spec := _join_spectator(bus, 102, rid)
	t.ok(not spec.last_draft.is_empty(), "draft：旁觀者收到 catchup 選秀狀態")

	# 建旁觀選秀場景。
	var spec_d: Node = DraftScene.instantiate()
	spec_d.boot_net(spec, "", spec.last_draft, true)

	t.ok(spec_d._net_spectator, "draft：場景為旁觀模式")
	t.eq(spec_d._state.player1_deck.size(), 2, "draft：旁觀鏡像反映已選 2 張")

	# 進階/移除鈕隱藏。
	t.ok(not spec_d._advance_btn.visible, "draft：旁觀隱藏進階鈕")
	t.ok(not spec_d._remove_last_btn.visible, "draft：旁觀隱藏移除鈕")

	# 展示卡不可點（disabled）。
	var ex_children: Array = spec_d._exhibit_box.get_children()
	t.ok(ex_children.size() > 0, "draft：展示格非空")
	var ex_all_disabled := true
	for c in ex_children:
		if not (c as Button).disabled:
			ex_all_disabled = false
	t.ok(ex_all_disabled, "draft：旁觀展示卡全不可點（disabled）")

	# 任何點擊零送信。
	var before := spec.sent_drafts
	spec_d._on_exhibit_pressed("TANKW")
	spec_d._on_advance()
	spec_d._on_remove_last()
	spec_d._on_deck_card_pressed("player1", "ADCW")
	t.eq(spec.sent_drafts, before, "draft：旁觀任何點擊零送信")

	# 觀戰人數顯示（階段列）。
	spec_d.set_spectator_count(1)
	t.ok(spec_d._net_phase_text().contains("觀戰"), "draft：階段列顯示觀戰人數")
	t.ok(spec_d._net_phase_text().contains("旁觀中"), "draft：階段列顯示旁觀徽章")

	# 後續選秀行動 → 旁觀場景同步。
	host.send_draft_action("add_card", "TANKW")
	t.eq(spec_d._state.player1_deck.size(), 3, "draft：後續選秀→旁觀場景同步")

	spec_d.free()
	server.free()
	host.free(); b["p2"].free(); spec.free()
