# P11-2 對戰紀錄（RefCounted，零 Node 依賴）。錄一局所需的最小重現資料：
#   seed ＋ 雙方牌組 ＋ GameAction 流（type/player/x/y/hand_index）。
# 決定性由 RngService(seed) 保證：把同一 action 流餵進新 GameCore（simulate）→ 完全相同結果。
# 序列化為 JSONL：第 1 行 meta，之後每行一個 action（人可讀、可 append 串流）。
# 檔案 I/O（FileAccess/DirAccess）非 Node 依賴，符合 core 零 Node 規則（見 D1）。
class_name ReplayLog
extends RefCounted

const VERSION := 1
const DIR := "user://replays/"

var seed: int = 0
var p1_deck: Array = []
var p2_deck: Array = []
var actions: Array = []   # 每筆＝{"t":type, "p":player, "x":board_x, "y":board_y, "i":hand_index}


func _init(seed_value: int = 0, deck1: Array = [], deck2: Array = []) -> void:
	seed = seed_value
	p1_deck = deck1.duplicate()
	p2_deck = deck2.duplicate()
	actions = []


func record(action: GameAction) -> void:
	actions.append({
		"t": action.action_type,
		"p": action.player,
		"x": action.board_x,
		"y": action.board_y,
		"i": action.hand_index,
	})


# --- 序列化 ---

func to_jsonl() -> String:
	var lines: Array = []
	lines.append(JSON.stringify({
		"v": VERSION, "seed": seed, "p1": p1_deck, "p2": p2_deck,
	}))
	for a: Dictionary in actions:
		lines.append(JSON.stringify(a))
	return "\n".join(lines)


static func from_jsonl(text: String) -> ReplayLog:
	var log := ReplayLog.new()
	var lines: PackedStringArray = text.split("\n", false)
	if lines.is_empty():
		return log
	var meta: Variant = JSON.parse_string(lines[0])
	if meta is Dictionary:
		log.seed = int(meta.get("seed", 0))
		log.p1_deck = _to_str_array(meta.get("p1", []))
		log.p2_deck = _to_str_array(meta.get("p2", []))
	for i in range(1, lines.size()):
		var a: Variant = JSON.parse_string(lines[i])
		if a is Dictionary:
			log.actions.append({
				"t": String(a.get("t", "")),
				"p": String(a.get("p", "")),
				"x": int(a.get("x", -1)),
				"y": int(a.get("y", -1)),
				"i": int(a.get("i", -1)),
			})
	return log


static func _to_str_array(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for e: Variant in v:
			out.append(String(e))
	return out


# 把第 idx 筆 action 還原為 GameAction。
func action_at(idx: int) -> GameAction:
	var a: Dictionary = actions[idx]
	var ga := GameAction.new(String(a["t"]), String(a["p"]))
	ga.board_x = int(a["x"])
	ga.board_y = int(a["y"])
	ga.hand_index = int(a["i"])
	return ga


# --- 決定性重播（headless 驗收用）：新開 GameCore，依序分派全部 action，
#     每筆後照 battle 的瞬時同步（drain_events + logic_step 抽牌迴圈）推進 → 回傳最終 core。---
static func simulate(log: ReplayLog, db: Object = null) -> GameCore:
	var core := GameCore.new()
	core.setup(log.p1_deck.duplicate(), log.p2_deck.duplicate(), log.seed, db)
	for i in log.actions.size():
		core.dispatch(log.action_at(i))
		core.drain_events()
		_drain_logic(core)
	return core


static func _drain_logic(core: GameCore) -> void:
	core.logic_step()
	var guard: int = 0
	while (int(core.card_to_draw["player1"]) > 0 or int(core.card_to_draw["player2"]) > 0) and guard < 256:
		guard += 1
		core.logic_step()


# --- 檔案 I/O ---

static func save_to_file(log: ReplayLog, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ReplayLog：無法寫入 " + path)
		return false
	f.store_string(log.to_jsonl())
	f.close()
	return true


static func load_from_file(path: String) -> ReplayLog:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return from_jsonl(text)


# 列出 replays 目錄下的 .jsonl（新到舊），回傳完整路徑陣列。
static func list_replays() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for name: String in d.get_files():
		if name.ends_with(".jsonl"):
			out.append(DIR + name)
	out.sort()
	out.reverse()
	return out


# 產生一個以時間戳為名的存檔路徑（DIR + <時間>.jsonl）。
static func new_path() -> String:
	return DIR + "replay_" + str(Time.get_unix_time_from_system()) + ".jsonl"
