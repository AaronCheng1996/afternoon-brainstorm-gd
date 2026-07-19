# P12-16 驗收：斷線重連 UX（客端）。見 docs/rebuild/10_連線版本.md §8/§11.2-8。
# @rpc-over-ENet 的真實拔線重連屬【人工】（見 test_net_reconnect 檔頭）；本檔以純表現層方法驗——
#   (A) 對手 held（斷線等待重連）於 battle/draft net 場景顯示等待提示（含剩餘秒）。
#   (B) lobby 重連狀態機（純方法）：`_begin_reconnect` 進遮罩、`_on_room_updated` 恢復清旗標、
#       `_fail_reconnect`/放棄回連線設定；`_forward_opponent_held` 依房態轉入子場景；held 席位文字。
#   (C) server member_view 廣播 `hold_remaining`（供客端顯示性倒數，§11.2-6）。
# 純 Node/場景 .free() → 維持零新洩漏（不建立實際連線，故不涉 @rpc 節點）。
extends RefCounted

const BattleScene := preload("res://scenes/battle/battle.tscn")
const DraftScene := preload("res://scenes/draft/draft.tscn")
const LobbyScene := preload("res://scenes/online/online_lobby.tscn")


func run(t: Object) -> void:
	_test_opponent_held_display(t)
	_test_lobby_reconnect_state(t)
	_test_member_view_hold_remaining(t)


# ---------------- (A) 對手 held 顯示（battle / draft）----------------

func _test_opponent_held_display(t: Object) -> void:
	# battle：以一顆 session 的開局快照建 net 場景（player1 視角）。
	var sess := NetGameSession.new()
	sess.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, 20260718, null)
	var client := NetClient.new()   # 不啟動；boot_net 只連信號
	var b: Node = BattleScene.instantiate()
	b.boot_net(client, "player1", sess.snapshot())
	b.set_animation_enabled(false)
	b.set_opponent_held(true, 42)
	var st: String = b._net_status_text()
	t.ok(st.contains("對方斷線") and st.contains("42"), "held：battle 狀態列顯示對方斷線＋剩餘秒")
	b.set_opponent_held(false, 0)
	t.ok(not b._net_status_text().contains("對方斷線"), "held：battle 恢復後清除等待提示")
	b.free()
	client.free()

	# draft：以一份公開選秀 view 建 net 場景（player1 視角）。
	var draft := NetDraftSession.new()
	draft.start(20260719, false, 45.0)
	var client2 := NetClient.new()
	var d: Node = DraftScene.instantiate()
	d.boot_net(client2, "player1", draft.view())
	d.set_opponent_held(true, 30)
	t.ok(d._net_phase_text().contains("對方斷線"), "held：draft 階段列顯示對方斷線")
	d.set_opponent_held(false, 0)
	t.ok(not d._net_phase_text().contains("對方斷線"), "held：draft 恢復後清除等待提示")
	d.free()
	client2.free()


# ---------------- (B) lobby 重連狀態機（純方法，不建實際連線）----------------

func _test_lobby_reconnect_state(t: Object) -> void:
	var m: Node = LobbyScene.instantiate()
	m._bind_nodes()
	m._conn_host = "1.2.3.4"
	m._conn_port = 24242
	m._conn_nick = "me"
	m._my_id = 100
	m._current_room = {"room_id": "AB23", "state": RoomManager.STATE_BATTLING,
		"seats": {"player1": 100, "player2": 101}}

	# _begin_reconnect：進重連遮罩、存 token、狀態文字。
	m._begin_reconnect("seat-tok")
	t.ok(m._reconnecting, "rc：進入重連狀態")
	t.eq(m._ui_state, m.UI_RECONNECT, "rc：顯示重連遮罩面板")
	t.ok(m._reconnect_panel.visible, "rc：重連面板可見")
	t.eq(m._reconnect_token, "seat-tok", "rc：存下席位 token 供重連")
	t.ok(m._reconnect_status.text.contains("重新連線"), "rc：遮罩顯示重連中文案")

	# _on_room_updated（模擬重連成功的房態）→ 清重連旗標、回房內面板。
	m._on_room_updated({"room_id": "AB23", "state": RoomManager.STATE_WAITING,
		"seats": {"player1": 100, "player2": 101}, "ready": {"player1": false, "player2": false},
		"host_id": 100, "spectators": [], "held": {"player1": false, "player2": false},
		"hold_remaining": {"player1": 0.0, "player2": 0.0}})
	t.ok(not m._reconnecting, "rc：收到房態＝恢復成功，清重連旗標")
	t.eq(m._ui_state, m.UI_ROOM, "rc：恢復後回房內面板")

	# _fail_reconnect（逾次/席位逾時）→ 回連線設定並顯示原因。
	m._reconnecting = true
	m._fail_reconnect("席位逾時")
	t.ok(not m._reconnecting, "rc：放棄重連清旗標")
	t.eq(m._ui_state, m.UI_CONNECT, "rc：放棄重連回連線設定")
	t.eq((m.get_node("%ConnectStatus") as Label).text, "席位逾時", "rc：顯示放棄原因")

	# held 席位文字：apply_room_state 對 held 席位顯示「等待重連」。
	m.apply_room_state({"room_id": "AB23", "state": RoomManager.STATE_BATTLING,
		"seats": {"player1": 100, "player2": 0}, "ready": {"player1": true, "player2": false},
		"host_id": 100, "spectators": [], "held": {"player1": false, "player2": true},
		"hold_remaining": {"player1": 0.0, "player2": 30.0}})
	t.ok((m.get_node("%Seat2Label") as Label).text.contains("等待重連"), "rc：held 席位顯示等待重連")

	# _forward_opponent_held：把對手 held 轉入活躍子場景（以真 battle net 場景驗）。
	var sess := NetGameSession.new()
	sess.start(NetGameSession.DEV_P1_DECK, NetGameSession.DEV_P2_DECK, 111, null)
	var client := NetClient.new()
	var b: Node = BattleScene.instantiate()
	b.boot_net(client, "player1", sess.snapshot())
	b.set_animation_enabled(false)
	m._current_room = {"seats": {"player1": 100, "player2": 101},
		"held": {"player1": false, "player2": true}, "hold_remaining": {"player1": 0.0, "player2": 25.0},
		"names": {"101": "小美"}}
	m._forward_opponent_held(b)
	t.ok(b._net_opp_held and b._net_opp_hold_remaining == 25, "rc：對手 held 轉入對戰子場景")

	# P12-17：對手暱稱與 RTT 轉入子場景（以 _battle_scene 掛上驗轉發路徑）。
	m._my_id = 100   # 前面 _fail_reconnect→_teardown_client 已把 _my_id 清 0，這裡復原為 P1 席位
	t.eq(m._peer_display_name(101), "小美", "p17：房態 names→對手暱稱")
	# P12-21：無暱稱不再退回裸 peer id（實機「對手 #948868441」），改短碼「玩家NNNN」。
	t.eq(m._peer_display_name(999), "玩家0999", "p21：無暱稱→短碼保底（不顯示裸 peer id）")
	t.eq(m._opponent_display_name(), "小美", "p17：對手席位暱稱")
	m._battle_scene = b
	m._on_rtt_measured(1, 55)
	t.ok(b._net_rtt == 55 and b._net_quality == "良好", "p17：RTT/品質轉入對戰子場景")
	m._on_room_updated({"room_id": "AB23", "state": RoomManager.STATE_BATTLING,
		"seats": {"player1": 100, "player2": 101}, "ready": {"player1": true, "player2": true},
		"host_id": 100, "spectators": [], "held": {"player1": false, "player2": false},
		"hold_remaining": {"player1": 0.0, "player2": 0.0}, "names": {"101": "小美"}})
	t.eq(b._net_opp_name, "小美", "p17：對手暱稱轉入對戰子場景")
	m._battle_scene = null   # 避免 m.free 誤動 b（b 由本測試自行 free）
	b.free()
	client.free()

	m.free()


# ---------------- (C) member_view 廣播 hold_remaining ----------------

func _test_member_view_hold_remaining(t: Object) -> void:
	var rm := RoomManager.new(16, 24680)
	var res := rm.create_room(100, {"name": "房"})
	var rid: String = res["room_id"]
	rm.join(101, rid, "", false)
	# P2 對局中斷線 → held＋倒數（handle_disconnect 於 battling/drafting 才保留席位）。
	rm._rooms[rid]["state"] = RoomManager.STATE_BATTLING
	rm.handle_disconnect(101, 60.0)
	var view := rm.member_view(rid)
	t.ok(view.has("hold_remaining"), "mv：member_view 含 hold_remaining")
	t.eq(int(view["hold_remaining"]["player2"]), 60, "mv：held 席位剩餘秒＝保留秒數")
	t.ok(bool(view["held"]["player2"]), "mv：held 標記為真")
