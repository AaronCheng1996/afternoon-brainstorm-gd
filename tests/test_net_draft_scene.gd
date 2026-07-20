# P12-13 驗收：連線選秀畫面接線（draft net 模式）＋正式流程 BP→對戰轉場。
# 見 docs/rebuild/10_連線版本.md §6/§11。沿用 P12-8/12「同程序匯流排」手法
# （@rpc-over-ENet 的跨機驗證屬【人工】，見 test_net_draft 檔頭）：真的把兩個 draft.tscn 場景以
# boot_net 接上兩個 NetClient，經 server 權威走完整 BP，斷言——
#   (A) 開局：兩場景由開局公開 view 重建顯示鏡像（phase/editor/雙方牌組）。
#   (B) gating：非編輯方場景輸入（點展示卡/進階/移除）**零送信**（§11.2-5）。
#   (C) 被拒 draft action：同名超上限 → 場景訊息列顯示（不斷線）。
#   (D) 完整三階段：經場景輸入走完 BP → server 雙方牌組＝預期、兩端 view 一致；完成後 server 建
#       對戰 session、房間 battling、兩 client 收開局快照（＝battle 轉場的協定信號）。
# 純 RefCounted／Node free 乾淨 → 維持零新洩漏。
extends RefCounted

const NetTestBus := preload("res://tests/net_test_bus.gd")
const DraftScene := preload("res://scenes/draft/draft.tscn")

# BP 測試用固定牌組（沿用 test_net_draft；單位 ≤2、每階段達最低張數）。
const P1_FIRST6 := ["ADCW", "ADCW", "APW", "APW", "TANKW", "TANKW"]
const P1_LAST6 := ["HFW", "HFW", "LFW", "LFW", "ASSW", "ASSW"]
const P2_PICK12 := ["ADCW", "ADCW", "APW", "APW", "TANKW", "TANKW",
	"HFW", "HFW", "LFW", "LFW", "ASSW", "ASSW"]


func run(t: Object) -> void:
	_test_scene_draft(t)


# ---------------- 同程序匯流排（沿用 test_net_draft/battle_scene）----------------


class _WiredServer extends NetGameServer:
	var bus: NetTestBus
	func _transmit(peer_id: int, text: String) -> void:
		bus.route(SERVER_ID, peer_id, text)


class _WiredClient extends NetClient:
	var bus: NetTestBus
	var my_id: int = 0
	var last_room: Dictionary = {}
	var last_draft: Dictionary = {}
	var opening_snapshot: Dictionary = {}
	var sent_drafts: int = 0

	func _transmit(peer_id: int, text: String) -> void:
		bus.route(my_id, peer_id, text)

	# 送信計數（gating 驗收：非我回合輸入應零送信）。
	func send_draft_action(type: String, card: String = "") -> void:
		sent_drafts += 1
		super(type, card)

	func _wire() -> void:
		room_updated.connect(func(r): last_room = r)
		draft_updated.connect(func(d): last_draft = d)
		# 開局對戰快照（第一份）＝BP→對戰轉場的協定信號。
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


# 以 boot_net 建一個連線選秀場景（以自己收到的開局 view）。
func _mk_draft(client: _WiredClient, seat: String, opening: Dictionary) -> Node:
	var d: Node = DraftScene.instantiate()
	d.boot_net(client, seat, opening)
	return d


# 讓「當前編輯方的場景」逐張加牌（每張經場景 _on_exhibit_pressed → 送 server → 同步鏡像）。
func _scene_add(scene: Node, cards: Array) -> void:
	for c: String in cards:
		scene._on_exhibit_pressed(c)


func _test_scene_draft(t: Object) -> void:
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
	host.create_room("選秀場景房", false, "", true, 8)
	var rid: String = String(host.last_room.get("room_id", ""))
	p2.join_room(rid, "", false)
	host.set_ready(true)
	p2.set_ready(true)
	host.start_draft()   # 正式流程：進 drafting、發首份選秀 view

	t.ok(not host.last_draft.is_empty() and not p2.last_draft.is_empty(),
		"scene：兩 client 收到開局選秀狀態")

	# 建兩個連線選秀場景（各以自己收到的開局 view）。
	var host_d: Node = _mk_draft(host, "player1", host.last_draft)
	var p2_d: Node = _mk_draft(p2, "player2", p2.last_draft)

	# (A) 開局：兩場景由公開 view 重建顯示鏡像。
	t.eq(host_d._state.phase, "p1_first6", "scene：host 開局階段 p1_first6（鏡像）")
	t.eq(host_d._state.current_editor(), "player1", "scene：開局編輯方 player1")
	t.eq(p2_d._state.phase, "p1_first6", "scene：p2 開局階段一致")

	# (B) gating：開局為 P1 回合 → p2 場景（非編輯方）任何輸入零送信。
	var p2_before: int = p2.sent_drafts
	p2_d._on_exhibit_pressed("ADCW")
	p2_d._on_advance()
	p2_d._on_remove_last()
	p2_d._on_deck_card_pressed("player1", "ADCW")   # 連對手牌組也不可動
	t.eq(p2.sent_drafts, p2_before, "scene：非編輯方輸入零送信（p2）")

	# (D) 階段 1：host（編輯方）經場景加滿 6 → 進階。
	_scene_add(host_d, P1_FIRST6)
	t.eq(host.last_draft.get("player1_count", 0), 6, "scene：P1 經場景選滿 6")
	host_d._on_advance()   # p1_first6 → p2_pick12
	t.eq(String(host.last_draft.get("phase", "")), "p2_pick12", "scene：階段 1→2")
	t.eq(String(host.last_draft.get("editor", "")), "player2", "scene：換 P2 選")

	# 階段 2：p2 加滿 12 → 進階。
	_scene_add(p2_d, P2_PICK12)
	p2_d._on_advance()     # p2_pick12 → p1_last6
	t.eq(String(host.last_draft.get("phase", "")), "p1_last6", "scene：階段 2→3")

	# (C) 被拒：p1_last6 時 host 已含 2 張 ADCW（來自 P1_FIRST6），再加 → 同名上限被拒 → 訊息列顯示。
	host_d._net_message = ""
	host_d._on_exhibit_pressed("ADCW")
	t.ok(not host_d._net_message.is_empty(), "scene：被拒選秀於 host 訊息列顯示")

	# 階段 3：host 補滿 12 → 進階 → done → 建 GameCore 進對戰。
	_scene_add(host_d, P1_LAST6)
	host_d._on_advance()

	# (D) 完成：兩端最終 view 一致、server 牌組＝預期、建對戰 session、兩 client 收開局快照。
	t.ok(bool(host.last_draft.get("done", false)), "scene：host 收到完成狀態")
	t.eq(JSON.stringify(host.last_draft), JSON.stringify(p2.last_draft),
		"scene：兩端選秀 view 一致（單一公開 view）")
	t.eq(host.last_draft["player1_deck"], P1_FIRST6 + P1_LAST6, "scene：P1 牌組＝預期")
	t.eq(host.last_draft["player2_deck"], P2_PICK12, "scene：P2 牌組＝預期")
	t.ok(not server._draft_sessions.has(rid), "scene：完成後移除選秀 session")
	t.ok(server._sessions.has(rid), "scene：完成後 server 建立對戰 session")
	t.eq(server.rooms.state_of(rid), RoomManager.STATE_BATTLING, "scene：房間進入 battling（轉場）")
	t.ok(not host.opening_snapshot.is_empty() and not p2.opening_snapshot.is_empty(),
		"scene：完成後兩 client 收開局快照（battle 轉場信號）")

	# 對戰 core 的雙方牌組＝選秀結果（母牌組順序保留）。
	var sess: NetGameSession = server._sessions[rid]
	t.eq(sess.core.player1.deck, P1_FIRST6 + P1_LAST6, "scene：對戰 P1 牌組＝選秀結果")
	t.eq(sess.core.player2.deck, P2_PICK12, "scene：對戰 P2 牌組＝選秀結果")

	# 完成後場景鏡像為 done：任一場景輸入不再送信（選秀已結束）。
	var host_before: int = host.sent_drafts
	host_d._on_exhibit_pressed("APW")
	host_d._on_advance()
	t.eq(host.sent_drafts, host_before, "scene：done 後場景輸入零送信")

	host_d.free()
	p2_d.free()
	server.free()
	host.free()
	p2.free()
