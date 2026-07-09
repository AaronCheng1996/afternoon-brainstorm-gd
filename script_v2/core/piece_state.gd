# P1-1 棋子純資料（見 docs/rebuild/04 §3、01 §2）。
# Python 中散落的布林（numbness/moving/anger/mouse_selected/been_targeted）
# 在 v2 統一收進 statuses 字典（見 04 §6）。能力/引擎在 P1-3 起透過 API 加減。
class_name PieceState
extends RefCounted

static var _next_instance: int = 0

var card_id: String        # 職業碼+色碼（job_and_color），如 "ADCW"、"TANKBR"
var job: String            # 職業碼，如 "ADC"（特殊卡為 card_id 本身）
var color_code: String     # 色碼，如 "W"
var owner: String          # player1 / player2 / neutral
var board_x: int = 0
var board_y: int = 0

var health: int = 0
var max_health: int = 0
var damage: int = 0
var original_damage: int = 0
var armor: int = 0
var extra_damage: int = 0
var attack_uses: int = 1
var attack_types: String = ""

# 狀態字典：id -> {value:bool, duration:int}（duration=-1 表示無期限）。
var statuses: Dictionary = {}

var instance_id: String = ""
var hit_cards: Array = []       # 本次攻擊已命中的棋子（管線用，P1-3）
var pending_death: bool = false
var shadows: Array = []         # Fuchsia 鏡像（P1-11）
var upgrade: bool = false       # Cyan 升級旗標（P1-10）


func pos() -> Vector2i:
	return Vector2i(board_x, board_y)


# 統計/日誌用唯一鍵：owner_JOBANDCOLOR。
func uid() -> String:
	return owner + "_" + card_id


# --- 狀態 API（見 04 §6）---

func has_status(id: String) -> bool:
	return statuses.has(id) and bool(statuses[id].get("value", false))


func set_status(id: String, on: bool, duration: int = -1) -> void:
	if on:
		statuses[id] = {"value": true, "duration": duration}
	else:
		statuses.erase(id)


func is_numb() -> bool:
	return has_status("numbness")

func set_numb(on: bool) -> void:
	set_status("numbness", on)

func is_moving() -> bool:
	return has_status("moving")

func set_moving(on: bool) -> void:
	set_status("moving", on)

func is_angry() -> bool:
	return has_status("anger")

func set_anger(on: bool) -> void:
	set_status("anger", on)


# --- 工廠 ---

# 依 card_id 從 BalanceDB 組出一個棋子。
# balance：BalanceDB 實例（stats/attack_types/job_of）。
# 入場暈眩預設 True，ASS（刺客先攻）例外（見 01 §3）。特殊卡（CUBE/SHADOW…）
# 的 numbness 由呼叫端另行處理（P1-2/P1-4）。
static func make(card_id: String, owner: String, x: int, y: int, balance: Object) -> PieceState:
	var p := PieceState.new()
	p.instance_id = str(PieceState._next_instance)
	PieceState._next_instance += 1
	p.card_id = card_id
	p.owner = owner
	p.board_x = x
	p.board_y = y

	var s: Dictionary = balance.stats(card_id)
	p.health = int(s.get("health", 0))
	p.max_health = p.health
	p.damage = int(s.get("damage", 0))
	p.original_damage = p.damage
	p.armor = int(s.get("armor", 0))
	p.extra_damage = int(s.get("extra_damage", 0))

	p.job = balance.job_of(card_id)
	if p.job == "":
		p.job = card_id   # 特殊卡（無色碼）
	p.color_code = balance.color_code_of(card_id)
	p.attack_types = balance.attack_types(p.job)

	p.set_numb(true)
	if p.job == "ASS":
		p.set_numb(false)
	return p
