# P12-15 驗收：終局與再戰流程閉環（連線終局統計＋再戰）。見 docs/rebuild/10_連線版本.md §11.2-7。
# 沿用同程序匯流排（@rpc-over-ENet 跨機屬【人工】，見 test_net_battle_scene 檔頭）。斷言——
#   (A) 終局：兩個 battle 場景經 server 打到終局 → 各 emit net_game_finished，勝方/統計 export＝
#       server 終局快照；以該資料 boot_net 建 end_game 子場景（net 版按鈕：再來一局／回房間）。
#   (B) 再戰：兩 client 送 rematch → server 房 ended→waiting＋雙方就緒 → 房主開新局（新 seed）→
#       兩端收新開局快照（≠上一局終局）、房間重回 battling、權威 session 為全新一顆。
#   (C) 判勝：battle 收到 game_over(reason=opponent_forfeit) → net_game_finished 帶 forfeit 原因；
#       end_game.boot_net(reason=forfeit) 標題加註「對手離線，判定勝出」。
# 場景與 net 物件皆 .free() → 維持零新洩漏。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")
const BattleScene := preload("res://scenes/battle/battle.tscn")
const EndGameScene := preload("res://scenes/end_game/end_game.tscn")


func run(t: Object) -> void:
	_test_endgame_and_rematch(t)
	_test_forfeit_reason(t)


# 雙重 JSON round-trip 正規化（統一 int/float 表示，供逐字比對）。
func _norm(v: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


# ---------------- 同程序匯流排（沿用 test_net_battle_scene）----------------


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
		# 每次「首份快照」都記為開局快照（測試於再戰前清空以捕捉第二局開局）。
		snapshot_received.connect(func(s):
			if opening_snapshot.is_empty():
				opening_snapshot = s)


func _mk_client(bus: NetTestBus, id: int, nick: String) -> _WiredClient:
	var c := _WiredClient.new()
	c.bus = bus
	c.my_id = id
	c._intent = NetMessage.INTENT_PLAY
	c._nickname = nick
	c._wire()
	return c


# 以 boot_net 建一個連線對戰場景（瞬時模式：事件同步收斂，headless 無 _process）。
func _mk_battle(client: _WiredClient, seat: String, opening: Dictionary) -> Node:
	var b: Node = BattleScene.instantiate()
	b.boot_net(client, seat, opening)
	b.set_animation_enabled(false)
	return b


# 連 battle 的 net_game_finished 到一個捕捉字典（測試斷言終局資料）。
func _capture_finish(b: Node) -> Dictionary:
	var cap := {"fired": false, "winner": -99, "stats": {}, "reason": "", "score_history": []}
	b.net_game_finished.connect(func(w: int, _sc: int, _wt: int, sh: Array, st: Dictionary, rs: String) -> void:
		cap["fired"] = true
		cap["winner"] = w
		cap["stats"] = st
		cap["reason"] = rs
		cap["score_history"] = sh)
	return cap


# ---------------- (A)(B) 終局統計 ＋ 再戰閉環 ----------------

func _test_endgame_and_rematch(t: Object) -> void:
	var seed1 := 20260718
	var bus := NetTestBus.new()
	var server := _WiredServer.new()
	server.bus = bus
	server.rooms = RoomManager.new(16, 24680)   # 決定性房碼
	bus.add(NetPeerBase.SERVER_ID, server)
	var host := _mk_client(bus, 100, "host")
	var p2 := _mk_client(bus, 101, "p2")
	for c in [host, p2]:
		bus.add(c.my_id, c)
		c._on_connected()
	host.create_room("終局房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_battle(seed1)   # 開發旗標：跳過 BP、預設牌組

	var host_b: Node = _mk_battle(host, "player1", host.opening_snapshot)
	var p2_b: Node = _mk_battle(p2, "player2", p2.opening_snapshot)
	var host_fin := _capture_finish(host_b)
	var p2_fin := _capture_finish(p2_b)

	# 以參考 session（同 seed/牌組）＋White AI 逐步驅動；每個行動經「當前玩家的場景」送 server。
	var ref := NetGameSession.new()
	ref.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, seed1, null)
	var ai1 := AIController.new("white", Balance, "player1")
	var ai2 := AIController.new("white", Balance, "player2")
	var now := 0
	var guard := 0
	var sess: NetGameSession = server._sessions[rid]
	while not sess.core.is_over() and sess.core.turn_number < 160 and guard < 16000:
		guard += 1
		now += 1000
		var cur: String = ref.core.current_player()
		var acts: Array = (ai1 if cur == "player1" else ai2).tick(ref.core, now, false)
		if acts.is_empty():
			continue
		var a: GameAction = acts[0]
		(host_b if cur == "player1" else p2_b)._do(a.action_type, a.board_x, a.board_y, a.hand_index)
		ref.apply_action(cur, a)

	# 若未自然終局，強制一次終局（設分數過門檻→當前玩家 end_turn，server 權威判定）。
	if not sess.core.is_over():
		sess.core.score = sess.core.config.win_threshold   # >0 → player2 勝
		var cur2: String = sess.core.current_player()
		(host_b if cur2 == "player1" else p2_b)._do("end_turn", -1, -1)

	# (A) 兩場景皆收到終局並 emit net_game_finished；勝方＝server；統計 export 兩端一致＝server。
	t.ok(sess.core.is_over(), "endgame：server 權威對局已終局")
	t.ok(host_fin["fired"] and p2_fin["fired"], "endgame：兩場景皆 emit net_game_finished")
	t.eq(int(host_fin["winner"]), sess.core.winner(), "endgame：host 端勝方＝server")
	t.eq(int(p2_fin["winner"]), sess.core.winner(), "endgame：p2 端勝方＝server")
	# 正規化（雙重 JSON round-trip 統一 int/float 表示）：client 端統計經 JSON 解為 float，
	# server 端為新鮮 int，逐字比對前先歸一（沿用 test_net_battle_scene._canon 手法）。
	var server_stats := _norm(sess.snapshot()["stats"])
	t.eq(_norm(host_fin["stats"]), server_stats, "endgame：host 端統計 export＝server")
	t.eq(_norm(p2_fin["stats"]), server_stats, "endgame：p2 端統計 export＝server")

	# 以終局資料 boot_net 建 end_game 子場景（net 版按鈕、旁觀者無再來一局）。
	var eg: Node = EndGameScene.instantiate()
	eg.boot_net(int(host_fin["winner"]), sess.core.score, sess.core.config.win_threshold,
		host_fin["score_history"], host_fin["stats"], false, String(host_fin["reason"]))
	t.ok(eg._is_net, "endgame：end_game 進入 net 模式")
	t.eq((eg.get_node("%AgainBtn") as Button).text, "再來一局", "endgame：AgainBtn＝再來一局")
	t.eq((eg.get_node("%MenuBtn") as Button).text, "回房間", "endgame：MenuBtn＝回房間")
	t.ok((eg.get_node("%AgainBtn") as Button).visible, "endgame：玩家可見再來一局")
	t.eq(eg._winner, sess.core.winner(), "endgame：end_game 勝方＝server")
	# 統計表格資料由終局統計 export 派生（單一資料源）。
	t.ok(eg.table_data() != null, "endgame：統計表格資料可派生")
	# 旁觀變體：無「再來一局」。
	var eg_spec: Node = EndGameScene.instantiate()
	eg_spec.boot_net(int(host_fin["winner"]), sess.core.score, sess.core.config.win_threshold,
		host_fin["score_history"], host_fin["stats"], true, "")
	t.ok(not (eg_spec.get_node("%AgainBtn") as Button).visible, "endgame：旁觀者無再來一局")

	# (B) 再戰：兩 client 送 rematch → 房 ended→waiting＋雙方就緒。
	var game1_final := JSON.stringify(sess.snapshot())
	host_b.free()
	p2_b.free()
	eg.free()
	eg_spec.free()
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_ENDED, "rematch：終局房態＝ended")
	host.rematch()
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_WAITING, "rematch：首位 rematch → 房重開 waiting")
	t.ok(not server.rooms.both_ready(rid), "rematch：僅一方就緒（尚缺對手）")
	p2.rematch()
	t.ok(server.rooms.both_ready(rid), "rematch：雙方 rematch → 兩席皆就緒")
	t.ok(not server._sessions.has(rid), "rematch：上一局權威 session 已丟棄")

	# 房主開新局（新 seed）→ 兩端收全新開局快照、房重回 battling。
	var seed2 := 20260719
	host.opening_snapshot = {}
	p2.opening_snapshot = {}
	host.start_battle(seed2)
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_BATTLING, "rematch：新局 → 房 battling")
	t.ok(not host.opening_snapshot.is_empty() and not p2.opening_snapshot.is_empty(),
		"rematch：兩端收到第二局開局快照")
	t.ok(server._sessions.has(rid) and not (server._sessions[rid] as NetGameSession).is_over(),
		"rematch：新一顆權威 session 進行中")
	t.ok(JSON.stringify(host.opening_snapshot) != game1_final,
		"rematch：第二局開局快照≠第一局終局（＝真正的新局）")

	server.free()
	host.free()
	p2.free()


# ---------------- (C) 判勝（forfeit）原因顯示 ----------------

func _test_forfeit_reason(t: Object) -> void:
	# 以一顆真 session 取得合法開局快照，建一個 net battle 場景（player1 視角）。
	var sess := NetGameSession.new()
	sess.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, 424242, null)
	var bus := NetTestBus.new()
	var client := _mk_client(bus, 200, "solo")
	bus.add(client.my_id, client)
	client._on_connected()
	var b: Node = _mk_battle(client, "player1", sess.snapshot())
	var cap := _capture_finish(b)

	# 模擬 server 廣播「對手判勝」終局（reason=opponent_forfeit，winner=player1）。
	b._on_net_game_over({"snapshot": sess.snapshot(), "winner": "player1",
		"reason": NetMessage.REASON_OPPONENT_FORFEIT})
	t.ok(cap["fired"], "forfeit：收到 game_over → emit net_game_finished")
	t.eq(String(cap["reason"]), NetMessage.REASON_OPPONENT_FORFEIT, "forfeit：原因＝opponent_forfeit")
	t.eq(int(cap["winner"]), 0, "forfeit：勝方＝player1（本方）")
	t.ok(not String(b._net_message).is_empty(), "forfeit：狀態列顯示判勝訊息")

	# end_game.boot_net 帶 forfeit 原因 → 標題加註。
	var eg: Node = EndGameScene.instantiate()
	eg.boot_net(0, 10, 10, [], {}, false, NetMessage.REASON_OPPONENT_FORFEIT)
	t.ok((eg.get_node("%TitleLabel") as Label).text.contains("對手離線"),
		"forfeit：end_game 標題加註對手離線判勝")

	eg.free()
	b.free()
	client.free()
