# P12-5 專用伺服器 headless 進入點（見 docs/rebuild/10_連線版本.md §5.1、§9）。
# 用法：godot --headless --path <專案> -s script/net/server_main.gd -- port=24242 max_rooms=16
# server 不載入任何場景/圖形；只用 script/core + script/net + Balance（autoload）。
# 常駐＝systemd（P12-11 附範本）；ENet 由 SceneTree 每幀自動 poll（multiplayer_peer 已設）。
extends SceneTree

# 設定檔（部署時可編輯，命令列參數可再覆蓋；路徑細節見 P12-11）。
const CONFIG_PATH := "user://server_config.json"

var _server: NetGameServer = null


func _initialize() -> void:
	var cfg := parse_config(OS.get_cmdline_user_args(), _read_text(CONFIG_PATH))
	_server = NetGameServer.new()
	_server.name = NetPeerBase.PEER_NODE_NAME   # 兩端同名，@rpc 路徑一致（見 NetPeerBase）
	_server.rooms.max_rooms = int(cfg["max_rooms"])
	root.add_child(_server)                       # 先入樹再開埠（multiplayer 需在樹上）
	var res := _server.start(int(cfg["port"]), int(cfg["max_clients"]))
	if not res["ok"]:
		push_error("[server] 開埠失敗：%s" % res["error"])
		quit(1)
		return
	print("[server] 午後激盪 專用伺服器啟動：埠 %d（UDP）／最大房間 %d／每房觀戰上限 %d"
		% [int(cfg["port"]), int(cfg["max_rooms"]), int(cfg["spectator_limit"])])
	print("[server] 遊戲版本 %s／資料版本 %s。Ctrl-C 或 SIGTERM 結束。"
		% [NetMessage.GAME_VERSION, Balance.data_version()])
	# 不 quit：SceneTree 主迴圈持續運行、每幀 poll ENet，直到收到終止訊號。


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
