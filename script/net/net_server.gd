# P12-3 伺服器端點（見 docs/rebuild/10_連線版本.md §3～§5）。
# 職責（本任務範圍＝骨架）：開埠、握手版本閘（遊戲版本＋Balance.data_version()）、
# 追蹤已認證客端、回應心跳。房間/座位/對戰（P12-5+）之後在 _on_message 擴充。
# 伺服器端輸入全部當不可信：未握手前的非 HELLO 訊息一律忽略。
class_name NetServer
extends NetPeerBase

# 客端完成握手。info = {intent, nickname, authed}。
signal client_authenticated(peer_id: int, info: Dictionary)
# 客端被拒（版本不符/意圖非法…）。
signal client_rejected(peer_id: int, reason: String)

# peer_id -> {intent: String, nickname: String, authed: bool}
var _clients: Dictionary = {}


# 開伺服器。回傳 {ok: bool, error: String}。
func start(port: int = NetTransport.DEFAULT_PORT,
		max_clients: int = NetTransport.DEFAULT_MAX_CLIENTS) -> Dictionary:
	var made := NetTransport.create_server(port, max_clients)
	if not made["ok"]:
		return {"ok": false, "error": made["error"]}
	_peer = made["peer"]
	multiplayer.multiplayer_peer = _peer
	_bind_multiplayer_signals()
	if not transport_peer_disconnected.is_connected(_on_client_gone):
		transport_peer_disconnected.connect(_on_client_gone)
	_started = true
	return {"ok": true, "error": ""}


func _on_client_gone(id: int) -> void:
	_clients.erase(id)


# 已認證客端清單（peer id）。
func authenticated_peers() -> Array:
	var out: Array = []
	for id in _clients.keys():
		if _clients[id].get("authed", false):
			out.append(id)
	return out


func is_authenticated(peer_id: int) -> bool:
	return _clients.has(peer_id) and _clients[peer_id].get("authed", false)


func _on_message(sender_id: int, type: String, payload: Dictionary) -> void:
	if type == NetMessage.T_HELLO:
		_handle_hello(sender_id, payload)
		return
	if not is_authenticated(sender_id):
		return   # 未握手前忽略（不可信）
	# 房間/對戰訊息在 P12-5+ 於此擴充。


# 握手：版本閘（遊戲版本＋資料版本，見 §3）→ 意圖檢查 → welcome/rejected。
func _handle_hello(sender_id: int, payload: Dictionary) -> void:
	var gv := String(payload.get("game_version", ""))
	if gv != NetMessage.GAME_VERSION:
		_reject(sender_id, NetMessage.REASON_GAME_VERSION)
		return
	var dv := String(payload.get("data_version", ""))
	if dv != Balance.data_version():
		_reject(sender_id, NetMessage.REASON_DATA_VERSION)
		return
	var intent := String(payload.get("intent", NetMessage.INTENT_PLAY))
	if intent != NetMessage.INTENT_PLAY and intent != NetMessage.INTENT_SPECTATE:
		_reject(sender_id, NetMessage.REASON_BAD_INTENT)
		return
	_clients[sender_id] = {
		"intent": intent,
		"nickname": String(payload.get("nickname", "")),
		"authed": true,
	}
	send_to(sender_id, NetMessage.T_WELCOME, {
		"peer_id": sender_id,
		"game_version": NetMessage.GAME_VERSION,
		"data_version": Balance.data_version(),
	})
	client_authenticated.emit(sender_id, _clients[sender_id])


func _reject(sender_id: int, reason: String) -> void:
	send_to(sender_id, NetMessage.T_REJECTED, {"reason": reason})
	client_rejected.emit(sender_id, reason)
	# 優雅斷線：disconnect_peer 預設會 flush 已排入的可靠封包（reject 先送達再斷）。
	if _peer is ENetMultiplayerPeer:
		(_peer as ENetMultiplayerPeer).disconnect_peer(sender_id)


func stop() -> void:
	_clients.clear()
	super()
