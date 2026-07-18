# P12-3 傳輸工廠（見 docs/rebuild/10_連線版本.md §3 與 §9.5「Steam 之路」設計紀律）。
# 全案「唯一」知道底層用 ENetMultiplayerPeer 的地方——未來換 GodotSteam 的
# SteamMultiplayerPeer 只需改本檔（RPC/訊息/伺服器/房間層一律不碰具體 peer 型別）。
# 位址概念抽象為「端點」（ENet=IP:port、Steam=SteamID）；上層只傳端點字串。
# 純工廠（RefCounted、零遊戲邏輯）。
class_name NetTransport
extends RefCounted

# 預設埠（見 §9 部署：Ubuntu 常駐、避開 Steam 用戶端 27000–27100 區段）。
const DEFAULT_PORT := 24242
# 預設最大連線數（房間/觀戰上限在房間層另管，這裡只是 ENet 承載上限）。
const DEFAULT_MAX_CLIENTS := 32


# 建立伺服器 peer。回傳 {ok: bool, peer: MultiplayerPeer, error: String}。
static func create_server(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		return {"ok": false, "peer": null,
			"error": "create_server 失敗（埠 %d）：%s" % [port, error_string(err)]}
	return {"ok": true, "peer": peer, "error": ""}


# 建立用戶端 peer，連往端點。回傳 {ok: bool, peer: MultiplayerPeer, error: String}。
static func create_client(host: String, port: int = DEFAULT_PORT) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return {"ok": false, "peer": null,
			"error": "create_client 失敗（%s）：%s" % [endpoint(host, port), error_string(err)]}
	return {"ok": true, "peer": peer, "error": ""}


# 端點顯示字串（ENet=IP:port）。上層 UI/log 用；未來 Steam 版改回 SteamID 只動這裡。
static func endpoint(host: String, port: int) -> String:
	return "%s:%d" % [host, port]
