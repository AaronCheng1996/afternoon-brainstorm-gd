# P12-3 連線端點共同基底（見 docs/rebuild/10_連線版本.md §3）。
# 職責：以「單一 @rpc 通道」收送 NetMessage、轉發底層連線/斷線信號、量測 RTT 心跳。
# 不含遊戲邏輯、不含 UI；NetServer/NetClient 各自繼承並覆寫 _on_message。
#
# RPC 路徑一致性：High-Level Multiplayer 依「節點路徑＋方法名」跨端解析 RPC，故 server 與
# client 兩端此節點必須同名同相對路徑——一律以 PEER_NODE_NAME 命名（正式部署掛在 /root 下、
# headless 測試掛在各自的 SceneMultiplayer 根下，相對路徑皆為 NetPeer）。
class_name NetPeerBase
extends Node

# 兩端統一節點名（見上方 RPC 路徑一致性說明）。
const PEER_NODE_NAME := "NetPeer"
# High-Level Multiplayer 伺服器固定 peer id。
const SERVER_ID := 1

# 收到一則（非心跳）訊息：型別＋payload。
signal message_received(sender_id: int, type: String, payload: Dictionary)
# 底層傳輸層某 peer 連上（server：新客端；client：伺服器）。
signal transport_peer_connected(peer_id: int)
# 底層傳輸層某 peer 斷線。
signal transport_peer_disconnected(peer_id: int)
# 完成一次 RTT 量測（單位毫秒）。
signal rtt_measured(peer_id: int, rtt_ms: int)

# 目前使用中的 peer（由子類經 NetTransport 建立後設入）。
var _peer: MultiplayerPeer = null
var _started := false


# 綁定底層 MultiplayerAPI 的連線/斷線信號（子類設好 multiplayer_peer 後呼叫）。
func _bind_multiplayer_signals() -> void:
	var mp := multiplayer
	if not mp.peer_connected.is_connected(_on_transport_peer_connected):
		mp.peer_connected.connect(_on_transport_peer_connected)
	if not mp.peer_disconnected.is_connected(_on_transport_peer_disconnected):
		mp.peer_disconnected.connect(_on_transport_peer_disconnected)


func _on_transport_peer_connected(id: int) -> void:
	transport_peer_connected.emit(id)


func _on_transport_peer_disconnected(id: int) -> void:
	transport_peer_disconnected.emit(id)


# --- 收送（單一入口）---

# 送一則 NetMessage 給指定 peer（server→client 用其 peer id；client→server 用 SERVER_ID）。
func send_to(peer_id: int, type: String, payload: Dictionary = {}) -> void:
	_transmit(peer_id, NetMessage.encode(type, payload))


# 實際送出一段已編碼字串。正式＝@rpc over ENet；測試子類覆寫為同程序投遞。
# （集中於此便於未來換傳輸；與 NetTransport 工廠一同守住 Steam 之路，見 §9.5。）
func _transmit(peer_id: int, text: String) -> void:
	_rpc_recv.rpc_id(peer_id, text)


# 唯一 RPC 入口：取傳輸層 sender id → 交給 _ingest。any_peer（server 當不可信）、可靠有序。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_recv(text: String) -> void:
	_ingest(multiplayer.get_remote_sender_id(), text)


# 收進一段字串（解碼＋驗證＋分派）；sender_id 由傳輸層提供。純邏輯、可獨立測試。
func _ingest(sender_id: int, text: String) -> void:
	var msg := NetMessage.decode(text)
	if not msg["ok"]:
		_on_bad_message(sender_id, msg["error"])
		return
	_dispatch_message(sender_id, msg["type"], msg["payload"])


# 內部分派：先攔心跳（PING/PONG），其餘交給子類。
func _dispatch_message(sender_id: int, type: String, payload: Dictionary) -> void:
	match type:
		NetMessage.T_PING:
			send_to(sender_id, NetMessage.T_PONG, payload)   # 原樣回送時間戳
		NetMessage.T_PONG:
			_on_pong(sender_id, payload)
		_:
			message_received.emit(sender_id, type, payload)
			_on_message(sender_id, type, payload)


# --- RTT 心跳 ---

# 送一次 ping（預設對伺服器）；對方回 pong 後觸發 rtt_measured。
func ping(peer_id: int = SERVER_ID) -> void:
	send_to(peer_id, NetMessage.T_PING, {"t": Time.get_ticks_msec()})


func _on_pong(peer_id: int, payload: Dictionary) -> void:
	var sent := int(payload.get("t", 0))
	var rtt: int = Time.get_ticks_msec() - sent
	rtt_measured.emit(peer_id, rtt)


# --- 子類覆寫點 ---

func _on_message(_sender_id: int, _type: String, _payload: Dictionary) -> void:
	pass


func _on_bad_message(_sender_id: int, _error: String) -> void:
	pass


# --- 生命週期 ---

# 關閉連線並釋放 peer（子類 stop 前置）。
func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if is_inside_tree():
		multiplayer.multiplayer_peer = null
	_started = false
