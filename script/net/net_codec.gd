# P12-6 連線資料編解碼（見 docs/rebuild/10_連線版本.md §4/§6）。
# GameAction（client→server 輸入）與 GameEvent（server→client 輸出）的 JSON 化與還原。
# core 不動：GameAction/GameEvent 定義仍留在 script/core，本模組只做「純資料 ↔ JSON 安全字典」。
#
# **不可信輸入（§9）**：decode_action 白名單 action_type、座標/索引一律 int 化，非法回 null；
# player 由伺服器依席位指派，**不採用 client 宣稱值**（見 net_game_server._do_game_action）。
# 純資料（RefCounted、零 Node），server/client/測試共用。
class_name NetCodec
extends RefCounted

# dispatch 可執行的行動白名單（"quit" 不可經網路觸發；player 由 server 指派）。
const ALLOWED_ACTIONS := ["attack", "play_card", "move_to", "heal", "spawn_cube", "toggle_upgrade", "end_turn"]
# GameEvent.data 中屬 Vector2i 的鍵（JSON 無此型別 → 序列化為 [x, y]，還原時依鍵重建）。
const V2_KEYS := ["from", "to", "at"]


# --- GameAction ---

static func encode_action(a: GameAction) -> Dictionary:
	return {"type": a.action_type, "x": a.board_x, "y": a.board_y, "i": a.hand_index}


# 還原一則行動；player 由呼叫端（server）依席位指派。非字典／未知型別／缺鍵 → null。
static func decode_action(d: Variant, player: String) -> GameAction:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = d
	var type := String(dict.get("type", ""))
	if not ALLOWED_ACTIONS.has(type):
		return null
	var a := GameAction.new(type, player)
	a.board_x = int(dict.get("x", -1))
	a.board_y = int(dict.get("y", -1))
	a.hand_index = int(dict.get("i", -1))
	return a


# --- GameEvent ---

static func encode_event(e: GameEvent) -> Dictionary:
	return {"k": e.kind, "d": _encode_data(e.data)}


static func decode_event(d: Variant) -> GameEvent:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = d
	if not dict.has("k"):
		return null
	return GameEvent.new(int(dict["k"]), _decode_data(dict.get("d", {})))


static func encode_events(events: Array) -> Array:
	var out: Array = []
	for e: GameEvent in events:
		out.append(encode_event(e))
	return out


static func decode_events(arr: Variant) -> Array:
	var out: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return out
	for item in arr:
		var e := decode_event(item)
		if e != null:
			out.append(e)
	return out


# --- 內部：data 字典的 Vector2i ↔ [x,y] 轉換 ---

static func _encode_data(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in data:
		var v: Variant = data[key]
		if typeof(v) == TYPE_VECTOR2I:
			out[key] = [v.x, v.y]
		else:
			out[key] = v
	return out


static func _decode_data(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for key in d:
		var v: Variant = d[key]
		if V2_KEYS.has(key) and typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
			out[key] = Vector2i(int(v[0]), int(v[1]))
		else:
			out[key] = v
	return out
