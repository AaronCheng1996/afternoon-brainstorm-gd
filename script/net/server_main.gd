# P12-5 專用伺服器 headless 進入點（見 docs/rebuild/10_連線版本.md §5.1、§9）。
# 用法：godot --headless --path <專案> -s script/net/server_main.gd -- port=24242 max_rooms=16
# server 不載入任何場景/圖形；只用 script/core + script/net + Balance（autoload）。
# 常駐＝systemd（P12-11 附範本）；ENet 由 SceneTree 每幀自動 poll（multiplayer_peer 已設）。
extends SceneTree

# 設定檔（部署時可編輯，命令列參數可再覆蓋；路徑細節見 P12-11）。
const CONFIG_PATH := "user://server_config.json"

# 型別以 Node（非 NetGameServer）宣告：以 `-s` 進入點執行時，若在編譯期具名 NetGameServer，
# 會連鎖編譯 net_server.gd（引用 autoload Balance）——而 autoload 尚未註冊 → 編譯失敗。
# 改於 _initialize（autoload 已就緒）用 load().new() 動態載入，讓依賴鏈於執行期才編譯。
var _server: Node = null
var _cfg: Dictionary = {}


func _initialize() -> void:
	_cfg = parse_config(OS.get_cmdline_user_args(), _read_text(CONFIG_PATH))
	# 動態載入（見上方型別註解）：此時 SceneTree 已註冊 autoload，net_server 的 Balance 可解析。
	_server = load("res://script/net/net_game_server.gd").new()
	_server.name = NetPeerBase.PEER_NODE_NAME   # 兩端同名，@rpc 路徑一致（見 NetPeerBase）
	_server.rooms.max_rooms = int(_cfg["max_rooms"])
	_server.seat_hold_seconds = float(_cfg["seat_hold_seconds"])   # P12-10 席位保留秒數
	_server.save_replays = bool(_cfg["save_replays"])              # P12-11 對局結束存紀錄
	root.add_child(_server)
	# _initialize 期間新加入的節點尚未完整入樹（is_inside_tree 為 false，get_path/multiplayer 未就緒）
	# ——延到入樹後（下一 idle）再掛 MultiplayerAPI 與開埠。
	_boot.call_deferred()


# 節點入樹後開伺服器：`-s` SceneTree 主迴圈不會自動為節點建立 MultiplayerAPI（正式 boot 才有）
# ——手動掛一個。**根＝真正的 "/root"（不是 _server.get_path()）**：RPC 定址是「節點路徑相對於
# 該 MultiplayerAPI 的根」；用戶端走一般 boot 的預設 API（根＝其 SceneTree 的 /root），其 NetPeer
# 必須是 /root 的直接子節點才會算出相對路徑 "NetPeer"（見 net_peer_base.gd 開頭的路徑一致性說明）。
# 若這裡改綁 _server.get_path()（＝/root/NetPeer 自己），_server 相對自己的路徑會變成空字串，
# 與用戶端的 "NetPeer" 對不上，RPC 會回報 "Node not found"（P12-11 實機部署發現的 bug）。
func _boot() -> void:
	set_multiplayer(SceneMultiplayer.new(), ^"/root")
	var res: Dictionary = _server.start(int(_cfg["port"]), int(_cfg["max_clients"]))
	if not res["ok"]:
		push_error("[server] 開埠失敗：%s" % res["error"])
		quit(1)
		return
	print("[server] 午後激盪 專用伺服器啟動：埠 %d（UDP）／最大房間 %d／每房觀戰上限 %d"
		% [int(_cfg["port"]), int(_cfg["max_rooms"]), int(_cfg["spectator_limit"])])
	print("[server] 遊戲版本 %s／資料版本 %s。Ctrl-C 或 SIGTERM 結束。"
		% [NetMessage.GAME_VERSION, _data_version()])
	# 不 quit：SceneTree 主迴圈持續運行、每幀 poll ENet，直到收到終止訊號。


# 取資料版本。以 `-s` 進入點執行時，autoload 全域識別字（Balance）不進本主腳本的編譯期
# 符號表——改以執行期查 /root/Balance（SceneTree 已把 autoload 掛上 root）。net_server 等
# 依賴類仍於執行期用 Balance 全域（握手時，autoload 已就緒）。
func _data_version() -> String:
	var bal := root.get_node_or_null(^"Balance")
	return String(bal.data_version()) if bal != null else "unavailable"


func _finalize() -> void:
	if _server != null:
		_server.stop()


# ---------------- 設定解析（純函式，可測）----------------

# 預設 → server_config.json 覆蓋 → 命令列 key=value 覆蓋。回傳型別穩定（int/bool）的設定字典。
static func parse_config(args: PackedStringArray, file_text: String) -> Dictionary:
	var cfg := {
		"port": NetTransport.DEFAULT_PORT,
		"max_rooms": 16,
		"max_clients": NetTransport.DEFAULT_MAX_CLIENTS,
		"spectator_limit": RoomManager.DEFAULT_SPECTATOR_LIMIT,
		"seat_hold_seconds": 60,     # P12-10 重連用（本任務先納入設定）
		"save_replays": true,        # P12-11 server 端存 ReplayLog
	}
	_apply_file(cfg, file_text)
	_apply_args(cfg, args)
	return cfg


static func _apply_file(cfg: Dictionary, file_text: String) -> void:
	if file_text.strip_edges().is_empty():
		return
	var json := JSON.new()
	if json.parse(file_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data
	for k: String in cfg.keys():
		if data.has(k):
			cfg[k] = _coerce(cfg[k], data[k])


static func _apply_args(cfg: Dictionary, args: PackedStringArray) -> void:
	for a in args:
		var kv := String(a).split("=", false, 1)
		if kv.size() == 2 and cfg.has(kv[0]):
			cfg[kv[0]] = _coerce(cfg[kv[0]], kv[1])


# 依預設值型別強制轉換傳入值（bool/int/其他原樣）。
static func _coerce(default_val: Variant, incoming: Variant) -> Variant:
	match typeof(default_val):
		TYPE_BOOL:
			if typeof(incoming) == TYPE_STRING:
				var s := String(incoming).strip_edges().to_lower()
				return s == "1" or s == "true" or s == "yes" or s == "on"
			return bool(incoming)
		TYPE_INT:
			return int(incoming)
		_:
			return incoming


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""
