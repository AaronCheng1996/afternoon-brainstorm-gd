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
const T_REJECTED := "rejected" # server→client：握手/請求被拒（帶 reason）
const T_PING := "ping"         # 心跳：帶送出時間戳 {t}
const T_PONG := "pong"         # 心跳回覆：原樣回送 {t} 供對方算 RTT

# --- 握手意圖（見 §5.3 角色）---
const INTENT_PLAY := "play"
const INTENT_SPECTATE := "spectate"

# --- 拒絕原因常數（§3 版本閘 / §5.2 密碼 / §8 重連）---
const REASON_GAME_VERSION := "game_version_mismatch"
const REASON_DATA_VERSION := "data_version_mismatch"
const REASON_BAD_INTENT := "bad_intent"
const REASON_BAD_MESSAGE := "bad_message"

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
