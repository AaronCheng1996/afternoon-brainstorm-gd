# P12-3 連線訊息封裝（見 docs/rebuild/10_連線版本.md §3）。
# 網路上一律傳「信封」JSON：{v: 協定版本, t: 型別, p: payload}。上層只認型別常數＋
# payload 字典，不碰傳輸細節。純資料（RefCounted、零 Node 依賴），server/client/測試共用。
# 伺服器端輸入全部當不可信（§9）：decode 對結構做最低限度驗證，不合一律 ok=false。
class_name NetMessage
extends RefCounted

# 遊戲版本（Godot 版自有；握手時必須完全一致，見 §3 版本閘）。改規則/資料相容性時更新。
const GAME_VERSION := "godot-0.1.0"
# 連線協定版本（信封格式；與 GAME_VERSION 獨立，改信封結構時 +1）。
const PROTOCOL_VERSION := 1

# --- 訊息型別常數 ---
const T_HELLO := "hello"       # client→server：握手（見 _payload 需求）
const T_WELCOME := "welcome"   # server→client：握手通過
const T_REJECTED := "rejected" # server→client：握手層被拒（帶 reason，隨後斷線）
const T_PING := "ping"         # 心跳：帶送出時間戳 {t}
const T_PONG := "pong"         # 心跳回覆：原樣回送 {t} 供對方算 RTT

# --- 大廳／房間訊息（P12-5，§5）---
# client→server
const T_CREATE_ROOM := "create_room"  # {name, locked, password, allow_spectators, spectator_limit}
const T_JOIN_ROOM := "join_room"      # {room_id, password, spectate}
const T_LEAVE_ROOM := "leave_room"    # {}
const T_SET_READY := "set_ready"      # {ready}
const T_LIST_ROOMS := "list_rooms"    # {}
# server→client
const T_ROOM_LIST := "room_list"      # {rooms:[public_room…]}（回應 list_rooms）
const T_ROOM_STATE := "room_state"    # {room: member_view}（廣播給房內成員）
const T_ROOM_CLOSED := "room_closed"  # {room_id, reason}（房解散：通知原成員）
const T_LOBBY_ERROR := "lobby_error"  # {reason}（大廳請求失敗，不斷線，有別於握手 T_REJECTED）

# --- 選秀 BP 訊息（P12-8，§6）---
# client→server
const T_START_DRAFT := "start_draft"    # {}（房內玩家、兩席就緒 → server 進 drafting、建 DraftState）
const T_DRAFT_ACTION := "draft_action"  # {action:{type,card}}（席位玩家的選秀行動；player 由 server 依席位指派）
# server→client（廣播全房，BP 全公開）
const T_DRAFT_STATE := "draft_state"    # {draft: view}（選秀狀態：階段/當前選手/雙方牌組，關鍵點/每次行動後廣播）
const T_DRAFT_REJECTED := "draft_rejected"  # {reason, message}（只回行動者：回合閘／上限…，不斷線）

# --- 對戰訊息（P12-6，§4/§6）---
# client→server
const T_START_BATTLE := "start_battle"  # {seed?}（開發旗標：跳過 BP、預設牌組先驗對戰鏈路，見 §6）
const T_GAME_ACTION := "game_action"    # {action:{type,x,y,i}}（席位玩家的行動；player 由 server 依席位指派）
# server→client（廣播全房，玩家＋旁觀者同一份，D19）
const T_GAME_EVENTS := "game_events"    # {events:[{k,d}…]}（GameEvent 流，客端照本機管線播動畫）
const T_SNAPSHOT := "snapshot"          # {snapshot: GameSnapshot}（開局／回合交接／校正）
const T_GAME_OVER := "game_over"        # {snapshot, winner, reason?}（終局＋完整統計；reason 可為對手掉線判勝）
const T_ACTION_REJECTED := "action_rejected"  # {reason, message}（只回行動者，不斷線）

# --- 斷線重連訊息（P12-10，§8）---
# server→client：入座／重連成功後私下下發席位 token（只給該玩家，供再次斷線重連）。
const T_SEAT_TOKEN := "seat_token"      # {token, room_id, seat}

# --- 握手意圖（見 §5.3 角色）---
const INTENT_PLAY := "play"
const INTENT_SPECTATE := "spectate"

# --- 拒絕原因常數（§3 版本閘 / §5.2 密碼 / §8 重連）---
const REASON_GAME_VERSION := "game_version_mismatch"
const REASON_DATA_VERSION := "data_version_mismatch"
const REASON_BAD_INTENT := "bad_intent"
const REASON_BAD_MESSAGE := "bad_message"

# --- 大廳／房間錯誤原因（P12-5，§5）---
const REASON_ALREADY_IN_ROOM := "already_in_room"
const REASON_TOO_MANY_ROOMS := "too_many_rooms"
const REASON_ROOM_NOT_FOUND := "room_not_found"
const REASON_BAD_PASSWORD := "bad_password"
const REASON_ROOM_FULL := "room_full"
const REASON_NO_SPECTATE := "spectate_disabled"
const REASON_NOT_IN_ROOM := "not_in_room"
const REASON_NOT_A_PLAYER := "not_a_player"
const REASON_BAD_STATE := "bad_state"

# --- 選秀錯誤原因（P12-8，§6）---
const REASON_NOT_DRAFTING := "not_drafting"           # 房間未在選秀中
const REASON_BAD_DRAFT_ACTION := "bad_draft_action"   # 選秀行動格式非法（codec 拒收）

# --- 對戰錯誤原因（P12-6，§6）---
const REASON_NOT_BATTLING := "not_battling"           # 房間未在對戰中
const REASON_NOT_YOUR_TURN := "not_your_turn"         # 非當前回合玩家
const REASON_SPECTATOR_ACTION := "spectator_cannot_act"  # 旁觀者不得行動（唯讀由 server 保證）
const REASON_BAD_ACTION := "bad_action"               # 行動格式非法（codec 拒收）
const REASON_NOT_READY := "not_ready"                 # 開戰前雙方尚未就緒

# --- 斷線重連原因（P12-10，§8）---
const REASON_BAD_TOKEN := "bad_token"                 # 重連 token 無效／過期（席位不存在）
const REASON_RECONNECT_TIMEOUT := "reconnect_timeout" # 玩家逾時未回→房解散（通知留下成員）
const REASON_OPPONENT_FORFEIT := "opponent_forfeit"   # 對手重連逾時→判勝（game_over reason）

# --- 信封鍵 ---
const K_PROTOCOL := "v"
const K_TYPE := "t"
const K_PAYLOAD := "p"


# 打包成傳輸字串（JSON）。payload 省略時為空字典。
static func encode(type: String, payload: Dictionary = {}) -> String:
	return JSON.stringify({K_PROTOCOL: PROTOCOL_VERSION, K_TYPE: type, K_PAYLOAD: payload})


# 解析並驗證傳入字串。回傳 {ok: bool, type: String, payload: Dictionary, error: String}。
# 不可信輸入：非字典／協定不符／型別非字串／payload 非字典 一律拒收。
static func decode(text: String) -> Dictionary:
	# 用 JSON 實例的 parse()（回錯誤碼、不往全域錯誤日誌噴）——不可信封包解析失敗屬常態，
	# 不該汙染 log（parse_string 會 push_error）。
	var json := JSON.new()
	if json.parse(text) != OK:
		return _bad("parse_failed")
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _bad("not_a_dictionary")
	var env: Dictionary = parsed
	if int(env.get(K_PROTOCOL, -1)) != PROTOCOL_VERSION:
		return _bad("protocol_mismatch")
	var type: Variant = env.get(K_TYPE, null)
	if typeof(type) != TYPE_STRING or String(type).is_empty():
		return _bad("bad_type")
	var payload: Variant = env.get(K_PAYLOAD, {})
	if typeof(payload) != TYPE_DICTIONARY:
		return _bad("bad_payload")
	return {"ok": true, "type": String(type), "payload": payload, "error": ""}


static func _bad(err: String) -> Dictionary:
	return {"ok": false, "type": "", "payload": {}, "error": err}
