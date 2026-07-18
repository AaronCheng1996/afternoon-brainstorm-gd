# P12-12 驗收：連線對戰畫面接線（battle net 模式骨幹）。見 docs/rebuild/10_連線版本.md §4/§6/§11。
# 沿用 P12-6「同程序匯流排」手法（@rpc-over-ENet 的跨機驗證屬【人工】，見 test_net_battle 檔頭）：
# 真的把兩個 battle.tscn 場景以 boot_net 接上兩個 NetClient，經 server 權威打一整局，斷言——
#   (A) 開局：兩場景由開局公開快照重建盤面（視圖數＝快照棋子數）。
#   (B) gating：非我回合的場景輸入（點盤面/點手牌）**零送信**（§11.2-5）。
#   (C) 被拒 action：server 拒收 → 場景狀態列顯示訊息（不斷線）。
#   (D) 整局：兩場景最終公開快照＝server、且彼此一致（D19 單一公開快照）；盤面由該快照重建。
# 瞬時模式（set_animation_enabled(false)）讓事件同步收斂（headless 無 _process）。
# 場景與 net 物件皆 .free() → 維持零新洩漏（39/78 基準）。
extends RefCounted

const BattleScene := preload("res://scenes/battle/battle.tscn")


func run(t: Object) -> void:
	_test_scene_battle(t)


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
	var opening_snapshot: Dictionary = {}
	var sent_actions: int = 0

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	# 送信計數（gating 驗收：非我回合輸入應零送信）。
	func send_action(action: GameAction) -> void:
		sent_actions += 1
		super(action)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		# 開局快照（第一份）供建立 battle 場景；此後校正快照由場景自身連結處理。
		snapshot_received.connect(func(s):
			if opening_snapshot.is_empty():
				opening_snapshot = s)


func _mk_client(bus: _Bus, id: int, nick: String) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


# 以 boot_net 建一個連線對戰場景（瞬時模式）。boot_net 已建顯示鏡像 core，再強制關動畫。
func _mk_battle(client: _WiredClient, seat: String, opening: Dictionary) -> Node:
	var b: Node = BattleScene.instantiate()
	b.boot_net(client, seat, opening)
	b.set_animation_enabled(false)   # 瞬時：事件同步收斂（headless 無 _process）
	return b


# 深拷貝快照並移除每棋子的 instance_id（行程內物件識別碼，跨獨立 core 不可比）。
func _strip_ids(snap: Dictionary) -> Dictionary:
	var s := snap.duplicate(true)
	for p in s.get("pieces", []):
		(p as Dictionary).erase("instance_id")
	return s


# 正規化（JSON 往返統一型別）＋去 instance_id → 可比字串。
# client 端快照本就 JSON 往返過；server 端為新鮮字典，這裡一併正規化才可逐字比對。
func _canon(snap: Dictionary) -> String:
	var norm: Variant = JSON.parse_string(JSON.stringify(snap))
	return JSON.stringify(_strip_ids(norm))


func _test_scene_battle(t: Object) -> void:
	var seed_value := 20260718
	var bus := _Bus.new()
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 24680)   # 決定性房碼
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host")
	var p2 := _mk_client(bus, 101, "p2")
	for c in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("場景房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_battle(seed_value)   # 開發旗標：跳過 BP、預設牌組

	t.ok(not host.opening_snapshot.is_empty() and not p2.opening_snapshot.is_empty(),
		"scene：兩 client 收到開局快照")

	# 建兩個連線對戰場景（各以自己收到的開局快照）。
	var host_b: Node = _mk_battle(host, "player1", host.opening_snapshot)
	var p2_b: Node = _mk_battle(p2, "player2", p2.opening_snapshot)

	# (A) 開局：兩場景由公開快照重建盤面（視圖數＝快照棋子數）。
	var opening_pieces: int = (host.opening_snapshot.get("pieces", []) as Array).size()
	t.eq(host_b._views.size(), opening_pieces, "scene：host 開局盤面視圖＝快照棋子數")
	t.eq(p2_b._views.size(), opening_pieces, "scene：p2 開局盤面視圖＝快照棋子數")
	t.eq(host_b._core.current_player(), "player1", "scene：開局先手 player1（鏡像）")

	# (B) gating：開局為 player1 回合 → p2 場景（非當前）任何輸入零送信。
	var p2_before: int = p2.sent_actions
	p2_b._board_click(Vector2i(0, 0))
	p2_b._on_hand_pressed(0)
	p2_b._do("end_turn", -1, -1)
	t.eq(p2.sent_actions, p2_before, "scene：非我回合輸入零送信（p2）")
	# 對照：host（當前）點手牌會進入放置狀態（其 _do 送信另於整局驗）。
	host_b._on_hand_pressed(0)
	t.eq(host_b._placing_index, 0, "scene：當前玩家點手牌進入放置狀態")
	host_b._placing_index = -1

	# (C) 被拒 action：把 server 端 player1 攻擊次數清 0，host 送 attack（通過客端 gating）→ server 拒。
	var sess: NetGameSession = server._sessions[rid]
	var saved_attacks: int = int(sess.core.number_of_attacks["player1"])
	sess.core.number_of_attacks["player1"] = 0
	host_b._net_message = ""
	host_b._do("attack", 0, 0)
	t.ok(not host_b._net_message.is_empty(), "scene：被拒 action 於 host 狀態列顯示訊息")
	sess.core.number_of_attacks["player1"] = saved_attacks   # 還原（不影響後續整局）

	# (D) 整局：參考 session（同 seed/牌組）＋White AI 逐步鎖定；每個行動經「當前玩家的場景」_do 送 server。
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
		var a: GameAction = acts[0]
		var bt: Node = host_b if cur == "player1" else p2_b
		bt._do(a.action_type, a.board_x, a.board_y, a.hand_index)   # 場景輸入 → 送 server（net 模式）
		ref.apply_action(cur, a)                                    # 參考逐步鎖定

	t.ok(guard < 12000, "scene：對局未卡死")

	# 若未自然終局，強制一次 end_turn 取得反映最終權威狀態的校正快照。
	if not ref.core.is_over():
		var cur2: String = ref.core.current_player()
		var bt2: Node = host_b if cur2 == "player1" else p2_b
		bt2._do("end_turn", -1, -1)
		ref.apply_action(cur2, GameAction.new("end_turn", cur2))

	# 兩場景最終公開快照＝server 權威、且彼此一致（D19 單一公開快照）。
	var server_canon := _canon(sess.snapshot())
	t.eq(_canon(host_b._last_net_snapshot), server_canon, "scene：host 端最終快照＝server（逐位，除 id）")
	t.eq(_canon(p2_b._last_net_snapshot), server_canon, "scene：p2 端最終快照＝server（逐位，除 id）")
	t.eq(JSON.stringify(host_b._last_net_snapshot), JSON.stringify(p2_b._last_net_snapshot),
		"scene：兩端快照彼此一致（單一公開快照）")

	# 盤面由最終快照重建：視圖數＝快照棋子數。
	t.eq(host_b._views.size(), (host_b._last_net_snapshot.get("pieces", []) as Array).size(),
		"scene：host 盤面視圖＝最終快照棋子數")
	t.eq(p2_b._views.size(), (p2_b._last_net_snapshot.get("pieces", []) as Array).size(),
		"scene：p2 盤面視圖＝最終快照棋子數")

	host_b.free()
	p2_b.free()
	server.free()
	host.free()
	p2.free()
