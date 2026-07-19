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
	_test_immediate_sync(t)       # P12-19/D20：每次成功行動後即時同步（不待回合交接）
	_test_busy_window(t)          # P12-19：動畫忙碌窗——手動驅動 busy/finished，暫存快照不遺失
	_test_scheduler_early_finish(t)  # P12-19：純資料批（無排程動畫）於非瞬時也立即結束


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

	# P12-20（D21）：連線＝**主視角（我的席位）恆左欄**，對手右欄；兩端各自視角固定、不互換。
	t.eq(host_b._left_seat(), "player1", "scene：host（席位 player1）左欄＝自己")
	t.eq(host_b._right_seat(), "player2", "scene：host 右欄＝對手 player2")
	t.eq(p2_b._left_seat(), "player2", "scene：p2（席位 player2）左欄＝自己（主視角恆左）")
	t.eq(p2_b._right_seat(), "player1", "scene：p2 右欄＝對手 player1")
	# 非我回合時我方欄唯讀（可點性隨當前玩家，欄位不動）。
	t.ok(host_b._hand_interactive("player1"), "scene：player1 回合→host 左欄可點")
	t.ok(not p2_b._hand_interactive("player2"), "scene：player1 回合→p2 左欄（自己）唯讀")

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


# ---------------- P12-19：連線對戰行動即時同步（D20）----------------

# 共用啟動：server＋兩玩家＋房間 battling（開發旗標跳過 BP），回傳 {bus,server,host,p2,rid}。
func _boot_battle_scenes(seed_value: int, room_code_seed: int, base_id: int) -> Dictionary:
	var bus := _Bus.new()
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, room_code_seed)
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, base_id, "host")
	var p2 := _mk_client(bus, base_id + 1, "p2")
	for c in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("即時房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_battle(seed_value)
	return {"bus": bus, "server": server, "host": host, "p2": p2, "rid": rid}


# (E) D20 核心：每次「未換手」的成功行動後，兩場景手牌/資源/盤面即時＝server（不待回合交接）。
# 舊行為（校正快照只在 turn_changed 下發）在此會失敗；修正後（server 每動作附快照）通過。
func _test_immediate_sync(t: Object) -> void:
	var seed_value := 20260719
	var b := _boot_battle_scenes(seed_value, 24681, 200)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var host_b: Node = _mk_battle(host, "player1", host.opening_snapshot)
	var p2_b: Node = _mk_battle(p2, "player2", p2.opening_snapshot)
	var sess: NetGameSession = server._sessions[rid]

	# 參考 session（同 seed/牌組）逐步鎖定；White AI 驅動雙方行動流。
	var ref := NetGameSession.new()
	ref.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, seed_value, null)
	var ai1 := AIController.new("white", Balance, "player1")
	var ai2 := AIController.new("white", Balance, "player2")
	var now := 0
	var guard := 0
	var midturn_checks := 0
	while midturn_checks < 4 and not ref.core.is_over() and guard < 4000:
		guard += 1
		now += 1000
		var cur: String = ref.core.current_player()
		var acts: Array = (ai1 if cur == "player1" else ai2).tick(ref.core, now, false)
		if acts.is_empty():
			continue
		var a: GameAction = acts[0]
		var turn_before: int = ref.core.turn_number
		var bt: Node = host_b if cur == "player1" else p2_b
		bt._do(a.action_type, a.board_x, a.board_y, a.hand_index)   # 場景→server（瞬時同步套用）
		ref.apply_action(cur, a)
		if ref.core.turn_number != turn_before:
			continue   # 換手行動另有回合交接快照；本項專驗「未換手也即時」
		midturn_checks += 1
		var server_canon := _canon(sess.snapshot())
		t.eq(_canon(host_b._last_net_snapshot), server_canon,
			"E：未換手行動後 host 場景即時＝server（不待回合交接）")
		t.eq(_canon(p2_b._last_net_snapshot), server_canon,
			"E：未換手行動後 p2 場景即時＝server")
		# 手牌逐一（D20「手牌不消失」的直接反例）：兩場景鏡像手牌＝server 權威手牌。
		t.eq(host_b._core.get_player(cur).hand, sess.core.get_player(cur).hand,
			"E：行動方手牌 host 鏡像＝server（即時）")
		t.eq(p2_b._core.get_player(cur).hand, sess.core.get_player(cur).hand,
			"E：行動方手牌 p2 鏡像亦即時（D19 公開）")

	t.ok(midturn_checks >= 1, "E：至少驗證一次未換手行動的即時同步")

	host_b.free()
	p2_b.free()
	server.free()
	host.free()
	p2.free()


# (F) 動畫忙碌窗（P12-19「busy 旗標未解除」假說）：非瞬時場景手動驅動排程器/旗標
# （headless 無 _process）。忙碌期間到達的校正快照須暫存不即套、輸入被 gating；播畢即套用
# （行動結果不無聲遺失）。另驗防呆：_busy 與排程器實況不一致（stale）時新快照即恢復。
func _test_busy_window(t: Object) -> void:
	var seed_value := 20260720
	var b := _boot_battle_scenes(seed_value, 24682, 300)
	var server: _WiredServer = b["server"]
	var host: _WiredClient = b["host"]
	var p2: _WiredClient = b["p2"]
	var rid: String = b["rid"]
	var sess: NetGameSession = server._sessions[rid]
	# 直接 boot_net（不經 _mk_battle 的瞬時覆寫）→ 預設動畫開＝非瞬時，才有真正的忙碌窗。
	var scene: Node = BattleScene.instantiate()
	scene.boot_net(host, "player1", host.opening_snapshot)

	t.ok(scene._net_input_allowed(), "F：開局我方回合非忙碌→輸入允許")

	# 注入一筆「有排程動畫」的事件批（攻擊者在盤外＝無視圖→回呼安全返回、不建 tween）→ 進入忙碌。
	scene._on_net_events([GameEvent.attack(Vector2i(9, 9), Vector2i(9, 9), 0.05)])
	t.ok(scene._busy, "F：事件動畫批進行中→忙碌")
	t.ok(scene._scheduler.is_busy(), "F：排程器實際忙碌（佇列有排程項）")
	t.ok(not scene._net_input_allowed(), "F：忙碌時輸入被 gating（零送信）")

	# 忙碌期間校正快照到達 → 暫存、不即套用。
	var before := JSON.stringify(scene._last_net_snapshot)
	sess.apply_action("player1", GameAction.new("end_turn", "player1"))   # 產生反映變化的權威快照
	var mid_snap := sess.snapshot()
	scene._on_net_snapshot(mid_snap)
	t.ok(scene._net_has_pending_snapshot, "F：忙碌時校正快照暫存（不即套用）")
	t.eq(JSON.stringify(scene._last_net_snapshot), before, "F：暫存期間場景快照未變")

	# 手動推進排程器越過 delay → finished → 套用暫存快照。
	scene._scheduler._advance(0.2)
	t.ok(not scene._busy, "F：排程器播畢→解除忙碌")
	t.eq(_canon(scene._last_net_snapshot), _canon(mid_snap),
		"F：忙碌窗結束後套用暫存快照（行動結果不無聲遺失，D20）")
	# mid_snap 為 end_turn 後（player2 回合）→ 我方（player1）輸入應被 gating。
	t.ok(not scene._net_input_allowed(), "F：套用換手快照後→非我回合，輸入 gating")

	# 防呆：_busy 為真但排程器未在播（stale）→ 新快照到達應解旗標並即套用（不再無限暫存）。
	scene._busy = true
	scene._net_has_pending_snapshot = false
	sess.apply_action("player2", GameAction.new("end_turn", "player2"))
	var recover_snap := sess.snapshot()
	scene._on_net_snapshot(recover_snap)
	t.ok(not scene._busy, "F：stale busy 遇新快照→解除忙碌（防呆）")
	t.ok(not scene._net_has_pending_snapshot, "F：stale busy→即套用而非暫存")
	t.eq(_canon(scene._last_net_snapshot), _canon(recover_snap), "F：stale busy 恢復後快照已套用")

	scene.free()
	server.free()
	host.free()
	p2.free()


# 排程器早結束（Change 1）：純資料批（SPAWN/RESOURCE 於排程器不進佇列）於非瞬時模式也立即
# finished，不為了一個無動畫批空等一個 _process 幀（消除「出牌後 busy 卡一幀」）。
func _test_scheduler_early_finish(t: Object) -> void:
	var sc := CombatScheduler.new()
	sc.instant = false
	sc.setup(func(_p): return null, null)
	var fired := [false]
	sc.finished.connect(func() -> void: fired[0] = true)
	sc.play_events([GameEvent.spawn(Vector2i(0, 0), "TANKW", "player1")])   # 出牌批＝無排程動畫
	t.ok(fired[0], "早結束：非瞬時純 SPAWN 批 play_events 後即 finished")
	t.ok(not sc.is_busy(), "早結束：純資料批後不忙碌")
	# 對照：有排程動畫（攻擊）者不誤判早結束——維持忙碌直到 _advance 播完。
	fired[0] = false
	sc.play_events([GameEvent.attack(Vector2i(9, 9), Vector2i(9, 9), 0.1)])
	t.ok(sc.is_busy(), "早結束：有排程動畫者仍忙碌（不誤早結束）")
	t.ok(not fired[0], "早結束：動畫批未立即 finished")
	sc._advance(0.2)
	t.ok(fired[0], "早結束：_advance 播完後 finished")
	sc.free()
