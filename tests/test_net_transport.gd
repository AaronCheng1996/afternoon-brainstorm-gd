# P12-3 連線轉接層骨架測試（見 docs/rebuild/10_連線版本.md §3）。
#
# harness 限制：run_tests.gd 於 SceneTree `_initialize` 內同步跑到底即 quit，幀迴圈從未啟動，
# 故 root 尚未 in-tree，High-Level Multiplayer 的 @rpc 節點分派無法在此驗（需要運行中的樹）。
# 因此本測試把驗收拆兩層，各自忠實：
#   (B) 真 ENet loopback（同程序 server＋client peer，經 NetTransport 工廠、手動 poll 泵送）：
#       證明「連上／底層 RTT 可讀／斷線信號」——真實網路層。
#   (C) 協定邏輯以「同程序訊息匯流排」串接真正的 NetServer/NetClient（覆寫 _transmit）：
#       證明「握手成功／版本不符被拒＋原因／app 層 ping-pong RTT」——真實協定邏輯，零網路。
# 兩層合起來涵蓋 P12-3 全部驗收點；@rpc-over-ENet 的整合會在場景於運行樹中跑時（P12-6+）驗。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")
const HOST := "127.0.0.1"


# --- 同程序訊息匯流排：把 _transmit 導向對端 _ingest（取代 @rpc）---


class _WiredServer extends NetServer:
	var bus: NetTestBus

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 100

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)


# 純接收端（旁觀/擷取用）：收到的訊息記進 got。
class _Capture extends NetPeerBase:
	var bus: NetTestBus
	var my_id: int = 0
	var got: Array = []

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	func _on_message(_sender_id: int, type: String, payload: Dictionary) -> void:
		got.append({"type": type, "payload": payload})


func run(t: Object) -> void:
	_test_message_codec(t)
	_test_transport_endpoint(t)
	_test_real_enet_loopback(t)
	_test_handshake_and_rtt(t)
	_test_version_and_data_gate(t)


# --- (A) NetMessage 純編解碼 ---

func _test_message_codec(t: Object) -> void:
	var text := NetMessage.encode(NetMessage.T_HELLO, {"nickname": "阿明", "n": 3})
	var got := NetMessage.decode(text)
	t.ok(got["ok"], "codec：合法訊息解碼成功")
	t.eq(got["type"], NetMessage.T_HELLO, "codec：型別還原")
	t.eq(got["payload"].get("nickname", ""), "阿明", "codec：payload 字串還原")
	t.eq(int(got["payload"].get("n", 0)), 3, "codec：payload 數值還原")
	t.eq(NetMessage.decode(NetMessage.encode(NetMessage.T_PING))["payload"].size(), 0,
		"codec：省略 payload＝空字典")
	# 不可信輸入。
	t.ok(not NetMessage.decode("not json")["ok"], "codec：非 JSON 拒收")
	t.ok(not NetMessage.decode("[1,2,3]")["ok"], "codec：非字典拒收")
	t.ok(not NetMessage.decode(JSON.stringify({"v": 1, "t": ""}))["ok"], "codec：空型別拒收")
	t.ok(not NetMessage.decode(JSON.stringify({"v": 999, "t": "x", "p": {}}))["ok"],
		"codec：協定版本不符拒收")
	t.ok(not NetMessage.decode(JSON.stringify({"v": 1, "t": "x", "p": 5}))["ok"],
		"codec：payload 非字典拒收")


func _test_transport_endpoint(t: Object) -> void:
	t.eq(NetTransport.endpoint("1.2.3.4", 24242), "1.2.3.4:24242", "transport：端點字串格式")
	t.eq(NetTransport.DEFAULT_PORT, 24242, "transport：預設埠 24242（§9）")


# --- (B) 真 ENet loopback（連上／底層 RTT／斷線）---

func _test_real_enet_loopback(t: Object) -> void:
	var srv := NetTransport.create_server(24779, 8)
	t.ok(srv["ok"], "enet：server 開埠成功（%s）" % srv.get("error", ""))
	var cli := NetTransport.create_client(HOST, 24779)
	t.ok(cli["ok"], "enet：client 建立成功（%s）" % cli.get("error", ""))
	if not (srv["ok"] and cli["ok"]):
		return
	var sp: ENetMultiplayerPeer = srv["peer"]
	var cp: ENetMultiplayerPeer = cli["peer"]
	var rec := {"conn": false, "cid": 0, "disc": false}
	sp.peer_connected.connect(func(id): rec["conn"] = true; rec["cid"] = id)
	sp.peer_disconnected.connect(func(_id): rec["disc"] = true)

	for i in range(200):
		sp.poll()
		cp.poll()
		if rec["conn"]:
			break
		OS.delay_msec(3)
	t.ok(rec["conn"], "enet：client 連上 server（peer_connected 觸發）")
	t.eq(cp.get_connection_status(), MultiplayerPeer.CONNECTION_CONNECTED,
		"enet：client 連線狀態＝CONNECTED")
	# 底層 RTT 統計可讀（心跳的網路面佐證；app 層 RTT 在 C 測）。
	if rec["cid"] != 0:
		var pp := sp.get_peer(int(rec["cid"]))
		t.ok(pp != null and pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) >= 0.0,
			"enet：底層 RTT 統計可讀")

	cp.close()
	for i in range(200):
		sp.poll()
		if rec["disc"]:
			break
		OS.delay_msec(3)
	t.ok(rec["disc"], "enet：client 斷線觸發 server 端 peer_disconnected")
	sp.close()


# --- (C) 協定邏輯：握手成功＋app 層 RTT ---

func _test_handshake_and_rtt(t: Object) -> void:
	var bus := NetTestBus.new()
	var server := _WiredServer.new()
	server.bus = bus
	var client := _WiredClient.new()
	client.bus = bus
	client.my_id = 100
	bus.add(NetPeerBase.SERVER_ID, server)
	bus.add(100, client)

	var rec := {"welcomed": false, "welcome": {}, "rtt_got": false, "rtt_ms": -1}
	client.welcomed.connect(func(info): rec["welcomed"] = true; rec["welcome"] = info)
	client.rtt_measured.connect(func(_pid, ms): rec["rtt_got"] = true; rec["rtt_ms"] = ms)

	# 設握手欄位並觸發（正式由 connected_to_server 信號叫 _on_connected）。
	client._intent = NetMessage.INTENT_PLAY
	client._nickname = "阿明"
	client._on_connected()

	t.ok(client.is_welcomed(), "握手：client 收到 welcome")
	t.ok(rec["welcomed"], "握手：welcomed 信號觸發")
	t.eq(String(rec["welcome"].get("data_version", "")), Balance.data_version(),
		"握手：welcome 帶正確資料版本")
	t.eq(server.authenticated_peers().size(), 1, "握手：server 記錄 1 個已認證客端")
	t.eq(server.authenticated_peers()[0], 100, "握手：認證的是該客端 id")

	# app 層 ping→pong→RTT。
	client.ping()
	t.ok(rec["rtt_got"], "心跳：ping→pong 觸發 rtt_measured")
	t.ok(int(rec["rtt_ms"]) >= 0, "心跳：RTT 有值（>=0）")

	server.free()
	client.free()


# --- (C) 協定邏輯：版本閘（遊戲版本＋資料版本）＋非法意圖 ---

func _test_version_and_data_gate(t: Object) -> void:
	# 遊戲版本不符（走真正的 client._on_connected，宣告錯版本）。
	var bus := NetTestBus.new()
	var server := _WiredServer.new()
	server.bus = bus
	var client := _WiredClient.new()
	client.bus = bus
	client.my_id = 100
	bus.add(NetPeerBase.SERVER_ID, server)
	bus.add(100, client)

	var rec := {"rejected": false, "reason": ""}
	client.rejected.connect(func(r): rec["rejected"] = true; rec["reason"] = r)
	client.advertised_game_version = "WRONG-9.9.9"
	client._intent = NetMessage.INTENT_PLAY
	client._on_connected()

	t.ok(rec["rejected"], "版本閘：遊戲版本不符被拒（收到 rejected）")
	t.eq(String(rec["reason"]), NetMessage.REASON_GAME_VERSION, "版本閘：原因＝遊戲版本不符")
	t.ok(not client.is_welcomed(), "版本閘：被拒者未取得 welcome")
	t.eq(server.authenticated_peers().size(), 0, "版本閘：server 未認證任何客端")

	# 資料版本不符 & 非法意圖：以擷取端直接餵伺服器 crafted hello。
	var cap := _Capture.new()
	cap.bus = bus
	cap.my_id = 300
	bus.add(300, cap)

	server._ingest(300, NetMessage.encode(NetMessage.T_HELLO, {
		"game_version": NetMessage.GAME_VERSION,
		"data_version": "bal 0.0.0 @deadbeef",
		"intent": NetMessage.INTENT_PLAY,
	}))
	t.eq(cap.got.size(), 1, "版本閘：資料版本不符收到一則回覆")
	t.eq(cap.got[0]["type"], NetMessage.T_REJECTED, "版本閘：回覆為 rejected")
	t.eq(String(cap.got[0]["payload"].get("reason", "")), NetMessage.REASON_DATA_VERSION,
		"版本閘：原因＝資料版本不符")

	cap.got.clear()
	server._ingest(300, NetMessage.encode(NetMessage.T_HELLO, {
		"game_version": NetMessage.GAME_VERSION,
		"data_version": Balance.data_version(),
		"intent": "god_mode",
	}))
	t.eq(cap.got[0]["type"], NetMessage.T_REJECTED, "意圖閘：非法意圖被拒")
	t.eq(String(cap.got[0]["payload"].get("reason", "")), NetMessage.REASON_BAD_INTENT,
		"意圖閘：原因＝非法意圖")
	t.eq(server.authenticated_peers().size(), 0, "意圖閘：仍無認證客端")

	server.free()
	client.free()
	cap.free()
