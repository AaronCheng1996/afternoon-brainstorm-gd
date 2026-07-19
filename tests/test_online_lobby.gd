# P12-7 大廳與房間 UI headless 驗收（見 docs/rebuild/10_連線版本.md §5，06 P12-7）。
# 守（皆為不需連線的純表現層方法）：節點樹存在、面板狀態切換、房列表填充、房態套用
# （席位/就緒/房碼/開始鈕可用性/旁觀唯讀）、房碼與建房欄位驗證、拒絕原因文字對映。
# 實際連線流程（NetClient 開 ENet 連上 server）屬【人工】跨機測——@rpc-over-ENet 需運行樹，
# 且遠端伺服器不在此 harness（見 P12-3/P12-6 同註）。純 Node free 乾淨 → 維持零新洩漏。
extends RefCounted

const LobbyScene := preload("res://scenes/online/online_lobby.tscn")


func run(t: Object) -> void:
	_test_node_tree(t)
	_test_panel_states(t)
	_test_room_list(t)
	_test_room_state_player(t)
	_test_room_state_spectator(t)
	_test_validation(t)
	_test_reason_text(t)
	_test_settings_roundtrip(t)
	_test_display_name(t)   # P12-21 暱稱顯示


# ---------------- 0. 節點樹存在（instantiate 後 `%` 名稱解析）----------------
func _test_node_tree(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	for name in ["Background", "HUD", "MsgLabel",
			"ConnectPanel", "NicknameEdit", "HostEdit", "PortEdit", "ConnectBtn",
			"ConnectStatus", "ConnectBackBtn",
			"LobbyPanel", "LobbyServerLabel", "RoomList", "RefreshBtn", "CreateRoomBtn",
			"DisconnectBtn", "JoinCodeEdit", "JoinPasswordEdit", "JoinSpectateCheck", "JoinBtn",
			"CreatePanel", "CreateNameEdit", "CreateLockedCheck", "CreatePasswordEdit",
			"CreateSpectateCheck", "CreateConfirmBtn", "CreateCancelBtn", "CreateStatus",
			"RoomPanel", "RoomTitle", "RoomCodeLabel", "Seat1Label", "Seat2Label",
			"SpectatorLabel", "LatencyLabel", "RoomStatus", "ReadyBtn", "StartBtn", "LeaveBtn"]:
		t.ok(m.get_node_or_null("%" + name) != null, "lobby tree：%s 節點存在" % name)
	m.free()


# ---------------- 1. 面板狀態切換 ----------------
func _test_panel_states(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	m._bind_nodes()
	# 預設＝連線設定面板可見、其餘隱藏。
	t.ok(m._connect_panel.visible, "state：預設顯示連線面板")
	t.ok(not m._lobby_panel.visible, "state：預設隱藏大廳面板")
	t.ok(not m._create_panel.visible and not m._room_panel.visible, "state：預設隱藏建房/房內")
	# 欄位帶入預設埠。
	t.eq((m.get_node("%PortEdit") as LineEdit).text, str(NetTransport.DEFAULT_PORT), "state：埠欄位帶入預設")
	# 切到大廳。
	m._show_state(m.UI_LOBBY)
	t.ok(m._lobby_panel.visible and not m._connect_panel.visible, "state：切換到大廳面板")
	# 開建房面板（重設欄位）。
	m._on_open_create()
	t.ok(m._create_panel.visible, "state：開啟建房面板")
	t.ok((m.get_node("%CreateSpectateCheck") as CheckBox).button_pressed, "state：建房預設允許旁觀")
	# 取消 → 回大廳。
	m._on_create_cancel()
	t.ok(m._lobby_panel.visible and not m._create_panel.visible, "state：取消建房回大廳")
	m.free()


# ---------------- 2. 房列表填充 ----------------
func _test_room_list(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	m._bind_nodes()
	# 空列表 → 一個提示 Label。
	m.populate_room_list([])
	t.eq(m._room_list.get_child_count(), 1, "list：空列表顯示單一提示")
	t.ok(m._room_list.get_child(0) is Label, "list：提示為 Label")
	# 有房 → 每房一個 Button，文字含房碼；上鎖房帶鎖標記。
	var rooms := [
		{"room_id": "AB23", "name": "公開房", "locked": false, "state": "waiting",
			"player_count": 1.0, "spectator_count": 0.0, "spectator_limit": 8.0, "allow_spectators": true},
		{"room_id": "CD45", "name": "上鎖房", "locked": true, "state": "battling",
			"player_count": 2.0, "spectator_count": 3.0, "spectator_limit": 8.0, "allow_spectators": true},
	]
	m.populate_room_list(rooms)
	t.eq(m._room_list.get_child_count(), 2, "list：兩房兩列")
	var row0 := m._room_list.get_child(0) as Button
	var row1 := m._room_list.get_child(1) as Button
	t.ok(row0 != null and row0.text.contains("AB23"), "list：列含房碼")
	t.ok(row0.text.contains("玩家 1/2"), "list：列顯示玩家數")
	t.ok(row1.text.contains("🔒"), "list：上鎖房帶鎖標記")
	t.ok(row1.text.contains("觀 3/8"), "list：列顯示觀戰數")
	m.free()


# ---------------- 3. 房態套用（玩家＝房主視角）----------------
func _test_room_state_player(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	m._bind_nodes()
	m._my_id = 100   # 模擬 welcome 指派的 peer id
	# 等待中、我是 P1＝房主、對手未入座 → 開始鈕不可用、就緒鈕「準備就緒」。
	# （id 用 float 模擬 JSON 往返後的型別；apply 內以 int() 轉換）
	m.apply_room_state({
		"room_id": "AB23", "name": "測試房", "host_id": 100.0, "state": "waiting",
		"seats": {"player1": 100.0, "player2": 0.0},
		"ready": {"player1": false, "player2": false},
		"spectators": [], "allow_spectators": true, "spectator_limit": 8,
	})
	t.ok((m.get_node("%RoomCodeLabel") as Label).text.contains("AB23"), "room：房碼顯示於邀請列")
	t.ok((m.get_node("%Seat1Label") as Label).text.contains("你"), "room：P1 席位標為『你』")
	t.ok((m.get_node("%Seat2Label") as Label).text.contains("空位"), "room：P2 空位")
	t.ok((m.get_node("%ReadyBtn") as Button).visible, "room：玩家可見就緒鈕")
	t.eq((m.get_node("%ReadyBtn") as Button).text, "準備就緒", "room：未就緒時鈕為『準備就緒』")
	t.ok((m.get_node("%StartBtn") as Button).visible, "room：房主可見開始鈕")
	t.ok((m.get_node("%StartBtn") as Button).disabled, "room：未雙方就緒時開始鈕禁用")

	# 對手入座、雙方就緒 → 開始鈕啟用、就緒鈕切「取消就緒」、對手席位標『對手』。
	m.apply_room_state({
		"room_id": "AB23", "name": "測試房", "host_id": 100.0, "state": "waiting",
		"seats": {"player1": 100.0, "player2": 101.0},
		"ready": {"player1": true, "player2": true},
		"spectators": [], "allow_spectators": true, "spectator_limit": 8,
	})
	t.ok(not (m.get_node("%StartBtn") as Button).disabled, "room：雙方就緒後房主可開始")
	t.eq((m.get_node("%ReadyBtn") as Button).text, "取消就緒", "room：已就緒時鈕為『取消就緒』")
	# P12-21：他人席位顯示暱稱；房態未附 `names` 時以短碼保底，不再出現裸 peer id。
	var seat2: String = (m.get_node("%Seat2Label") as Label).text
	t.ok(not seat2.begins_with("你"), "room：P2 席位為他人（非『你』）")
	t.ok(seat2.contains("玩家0101"), "room：P2 席位以短碼顯示（無 names 時保底）")
	t.ok(not seat2.contains("#"), "room：席位不出現裸 peer id")
	t.ok((m.get_node("%RoomStatus") as Label).text.contains("可開始"), "room：狀態提示雙方就緒可開始")
	m.free()


# ---------------- 4. 房態套用（旁觀者＝唯讀）----------------
func _test_room_state_spectator(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	m._bind_nodes()
	m._my_id = 200   # 不在席位、非房主
	m.apply_room_state({
		"room_id": "CD45", "name": "觀戰房", "host_id": 100.0, "state": "battling",
		"seats": {"player1": 100.0, "player2": 101.0},
		"ready": {"player1": true, "player2": true},
		"spectators": [200.0], "allow_spectators": true, "spectator_limit": 8,
	})
	t.ok(not (m.get_node("%ReadyBtn") as Button).visible, "spec：旁觀者無就緒鈕")
	t.ok(not (m.get_node("%StartBtn") as Button).visible, "spec：旁觀者無開始鈕")
	t.ok((m.get_node("%SpectatorLabel") as Label).text.contains("1 人"), "spec：旁觀人數顯示")
	t.ok((m.get_node("%RoomStatus") as Label).text.contains("旁觀"), "spec：狀態標示旁觀中")
	t.eq(m._my_seat(), "", "spec：旁觀者無席位")
	m.free()


# ---------------- 5. 欄位驗證（房碼／建房，純靜態方法）----------------
func _test_validation(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	# 房碼：空／長度／無效字元／合法（含轉大寫）。
	t.ok(not m.validate_join_code("").is_empty(), "valid：空房碼被拒")
	t.ok(not m.validate_join_code("AB2").is_empty(), "valid：長度不足被拒")
	t.ok(not m.validate_join_code("AB2O").is_empty(), "valid：含排除字元 O 被拒")
	t.eq(m.validate_join_code("ab23"), "", "valid：小寫合法房碼（轉大寫）通過")
	t.eq(m.normalize_room_code("  ab23 "), "AB23", "valid：房碼正規化去空白＋大寫")
	# 建房：上鎖必須有密碼。
	t.ok(not m.create_error(true, "").is_empty(), "valid：上鎖無密碼被拒")
	t.ok(not m.create_error(true, "   ").is_empty(), "valid：上鎖密碼全空白被拒")
	t.eq(m.create_error(true, "pw"), "", "valid：上鎖有密碼通過")
	t.eq(m.create_error(false, ""), "", "valid：公開房免密碼通過")
	m.free()


# ---------------- 6. 拒絕原因 → 明確訊息 ----------------
func _test_reason_text(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	# 版本閘（§3）：給明確、可辨識的訊息。
	t.ok(m.reason_text(NetMessage.REASON_GAME_VERSION).contains("版本"), "reason：遊戲版本不符提及版本")
	t.ok(m.reason_text(NetMessage.REASON_DATA_VERSION).contains("版本"), "reason：資料版本不符提及版本")
	t.ok(m.reason_text(NetMessage.REASON_BAD_PASSWORD).contains("密碼"), "reason：密碼錯誤提及密碼")
	t.ok(m.reason_text(NetMessage.REASON_ROOM_FULL).contains("滿"), "reason：房間已滿")
	t.ok(m.reason_text(NetMessage.REASON_NO_SPECTATE).contains("旁觀"), "reason：未開放旁觀")
	# 未知原因不崩潰、回顯原字串。
	t.ok(m.reason_text("weird_thing").contains("weird_thing"), "reason：未知原因回顯原字串")
	m.free()


# ---------------- 8. P12-21 暱稱顯示（實機「對手 #948868441」修正）----------------
# 有暱稱用暱稱；空暱稱或舊 server 未送 `names` 時以短碼保底，**任何情況不出現裸 peer id**。
func _test_display_name(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()

	t.eq(m.display_name_for("阿倫", 948868441), "阿倫", "name：有暱稱直接用暱稱")
	t.eq(m.display_name_for("  阿倫  ", 1), "阿倫", "name：暱稱去除前後空白")
	var fb: String = m.display_name_for("", 948868441)
	t.ok(not fb.contains("948868441"), "name：空暱稱**不顯示裸 peer id**")
	t.eq(fb, "玩家8441", "name：空暱稱以短碼（末四位）保底")

	# 預設暱稱：確保永不為空 → server 端 names 不會是空字串。
	t.ok(not m.default_nickname().strip_edges().is_empty(), "name：預設暱稱非空")
	t.ok(m.default_nickname().begins_with("玩家"), "name：預設暱稱為「玩家NNNN」")

	# 房態 names 對映（辨因 (c) 防迴歸）：server 以 str(int(peer_id)) 為鍵、客端以 str(pid) 查，
	# 經 JSON 後 peer id 為浮點也必須先 int() 正規化才對得上。
	m._current_room = {"names": {"100": "阿倫", "101": ""}}
	t.eq(m._peer_display_name(100), "阿倫", "name：依房態 names 顯示暱稱")
	t.eq(m._peer_display_name(101), "玩家0101", "name：names 內空暱稱→短碼保底")
	t.eq(m._peer_display_name(999), "玩家0999", "name：names 缺鍵（舊版 server）→短碼保底")
	m.free()


# ---------------- 7. 連線設定持久化（記住上次）----------------
func _test_settings_roundtrip(t: Object) -> void:
	var existed: bool = FileAccess.file_exists(SettingsStore.PATH)
	var orig: Dictionary = SettingsStore.load_settings()

	# 預設含連線鍵。
	t.eq(orig["net_port"], NetTransport.DEFAULT_PORT, "settings：net_port 預設＝24242")

	var m: Node = LobbyScene.instantiate()
	m._persist_net_settings("阿倫", "192.168.1.50", 25000)
	var r: Dictionary = SettingsStore.load_settings()
	t.eq(r["net_nickname"], "阿倫", "settings：暱稱存讀一致")
	t.eq(r["net_host"], "192.168.1.50", "settings：位址存讀一致")
	t.eq(r["net_port"], 25000, "settings：埠存讀一致")
	# 保留其他設定（不被連線設定寫入重置）。
	t.eq(r["hints_on"], orig["hints_on"], "settings：其他設定不被連線寫入影響")
	m.free()

	# 還原（不留測試痕跡）。
	if existed:
		SettingsStore.save_settings(orig)
	else:
		var d := DirAccess.open("user://")
		if d != null:
			d.remove("settings.json")
