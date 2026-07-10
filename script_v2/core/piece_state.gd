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
var movable: bool = true         # 是否可被移動（base.py movable，SHADOW 等覆寫）
var shadow_attack_types: String = ""   # Fuchsia：鏡像用攻擊模式（空＝沿用 attack_types；LFF="nearest"，P1-11）

# 狀態字典：id -> {value:bool, duration:int}（duration=-1 表示無期限）。
var statuses: Dictionary = {}

var instance_id: String = ""
var hit_cards: Array = []       # 本次攻擊已命中的棋子（管線用，P1-3）
var pending_death: bool = false
var shadows: Array = []         # Fuchsia 鏡像（P1-11）：本體強參考持有其 shadow（SHADOW 棋子）
var upgrade: bool = false       # Cyan 升級旗標（P1-10）

# Fuchsia SHADOW 對本體（linker）的反向參考。用 WeakRef 打斷
# linker.shadows（強）→ shadow → linker 的循環，避免 RefCounted 洩漏（P1-11）。
var _linker_ref: WeakRef = null
var counters: Dictionary = {}   # 卡牌專用暫存計數（如 HFC 的 count；對齊 Python 各卡自有欄位）

# 能力元件（P1-3，見 04 §5.2）：native 由 registry 依 card_id 組裝；granted=附魔；silence=沉默。
# 由 make() 建立；直接 new() 的裸棋子需自行呼叫 ensure_abilities()。
var abilities: AbilityComponentV2 = null


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


# --- Fuchsia 鏡像關聯（P1-11）---

# 鏡像用攻擊模式：未設定則沿用本體 attack_types（對齊 Python FuchsiaCard.shadow_attack_types 預設）。
func get_shadow_attack_types() -> String:
	return shadow_attack_types if shadow_attack_types != "" else attack_types

# 設定 SHADOW 的本體反向參考（WeakRef）。
func set_linker(l: PieceState) -> void:
	_linker_ref = weakref(l) if l != null else null

# 取本體（可能已被回收 → null）。
func get_linker() -> PieceState:
	return _linker_ref.get_ref() if _linker_ref != null else null


# --- 工廠 ---

# 依 card_id 從 BalanceDB 組出一個棋子。
# balance：BalanceDB 實例（stats/attack_types/job_of）。
# 入場暈眩預設 True，ASS（刺客先攻）例外（見 01 §3）。特殊卡（CUBE/SHADOW…）
# 的 numbness 由呼叫端另行處理（P1-2/P1-4）。
static func make(card_id: String, owner: String, x: int, y: int, balance: Object, upgrade: bool = false) -> PieceState:
	var p := PieceState.new()
	p.instance_id = str(PieceState._next_instance)
	PieceState._next_instance += 1
	p.card_id = card_id
	p.owner = owner
	p.board_x = x
	p.board_y = y
	p.upgrade = upgrade

	var s: Dictionary = balance.stats(card_id)
	# Cyan 升級版改用 upgrade_health/upgrade_damage（見 02 §Cyan、card_setting）。
	if upgrade and s.has("upgrade_health"):
		p.health = int(s.get("upgrade_health", 0))
		p.damage = int(s.get("upgrade_damage", 0))
	else:
		p.health = int(s.get("health", 0))
		p.damage = int(s.get("damage", 0))
	p.max_health = p.health
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

	# 掛上能力元件（native 依 card_id）。
	p.abilities = AbilityRegistryV2.build(p.card_id, p)
	return p


# Fuchsia 鏡像工廠（P1-11，見 cards/card_fuchsia.py Shadow）：
# HP1/ATK0、不暈眩、攻擊模式沿用 linker 的 shadow_attack_types；linker 為 WeakRef 反向參考。
# 掛 SHADOW 能力（BLOCK_DAMAGE：linker=APTF 時 linker 獲 value//2 護盾）。
# 呼叫端（fuchsia.gd）負責 append 到 linker.shadows。
static func make_shadow(linker: PieceState, owner: String, x: int, y: int, movable_flag: bool) -> PieceState:
	var s := PieceState.new()
	s.instance_id = str(PieceState._next_instance)
	PieceState._next_instance += 1
	s.card_id = "SHADOW"
	s.job = "SHADOW"
	s.color_code = "F"
	s.owner = owner
	s.board_x = x
	s.board_y = y
	s.health = 1
	s.max_health = 1
	s.damage = 0
	s.original_damage = 0
	s.attack_types = linker.get_shadow_attack_types()
	s.movable = movable_flag
	s.set_numb(false)
	s.set_linker(linker)
	s.abilities = AbilityRegistryV2.build("SHADOW", s)
	return s


# 為裸棋子（PieceState.new()）補上空能力元件，避免鉤子分派時 null。
func ensure_abilities() -> void:
	if abilities == null:
		abilities = AbilityComponentV2.new(self)
