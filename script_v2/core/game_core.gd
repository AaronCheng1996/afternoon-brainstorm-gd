# P1-1 遊戲核心：狀態 + 回合引擎（行動分派在 P1-2、傷害管線在 P1-3 補上）。
# 純 GDScript（RefCounted，零 Node 依賴）——不得 extends Node / get_tree / load 場景（見 04 §1）。
# 對外介面：吃 GameAction（P1-2）、吐 GameEventV2 陣列（drain_events）+ 可查詢狀態。
class_name GameCore
extends RefCounted

var config: GameConfig
var board: BoardState
var balance: Object                # BalanceDB 實例（資料層，唯讀查詢）
var rng: RngService
var stats: Statistics

var player1: PlayerState
var player2: PlayerState
var neutral_pieces: Array = []     # Array[PieceState]：CUBE / LUCKYBLOCK 等
var event_sink: Array = []         # Array[GameEventV2]：本步驟產生的表現層事件

var score: int = 0
var turn_number: int = 0

# 每玩家計數（key: player1/player2）。
var number_of_attacks: Dictionary = {"player1": 0, "player2": 0}
var number_of_movings: Dictionary = {"player1": 0, "player2": 0}
var number_of_cubes: Dictionary = {"player1": 0, "player2": 0}
var number_of_heals: Dictionary = {"player1": 0, "player2": 0}
var card_to_draw: Dictionary = {"player1": 0, "player2": 0}
var skip_turn_draw: Dictionary = {"player1": false, "player2": false}

# 各色資源（luck/token/totem 含 neutral）。
var players_luck: Dictionary = {"player1": 50, "player2": 50, "neutral": 50}
var players_token: Dictionary = {"player1": 0, "player2": 0, "neutral": 0}
var players_totem: Dictionary = {"player1": 0, "player2": 0, "neutral": 0}
var players_coin: Dictionary = {"player1": 0, "player2": 0}

# 攻擊佇列（P1-3 傷害管線用，先宣告以固定欄位）。
var pending_attacks: Array = []
var _attack_draining: bool = false
var _attack_anim_cursor: float = 0.0

var _over: bool = false
var _winner: String = ""


# 開局（見 01 §3）。balance_db 可注入（headless 測試）；未提供則用 autoload Balance。
func setup(p1_deck: Array, p2_deck: Array, seed_value: int, balance_db: Object = null) -> void:
	balance = balance_db if balance_db != null else Balance
	config = GameConfig.new()
	board = BoardState.new()
	rng = RngService.new(seed_value)
	stats = Statistics.new()
	player1 = PlayerState.new("player1", p1_deck)
	player2 = PlayerState.new("player2", p2_deck)
	players_luck["player1"] = GameConfig.LUCK_INITIAL
	players_luck["player2"] = GameConfig.LUCK_INITIAL
	TurnEngine.initialize(self)


# --- 查詢輔助 ---

func get_player(owner: String) -> PlayerState:
	return player1 if owner == "player1" else player2


func opponent_name(owner: String) -> String:
	return "player2" if owner == "player1" else "player1"


# 當前回合玩家：turn_number 偶數 = player1，奇數 = player2（見 01 §3）。
func current_player() -> String:
	return "player1" if (turn_number % 2 == 0) else "player2"


func get_all_pieces() -> Array:
	var out: Array = []
	out.append_array(player1.on_board)
	out.append_array(player2.on_board)
	out.append_array(neutral_pieces)
	return out


# --- 回合流程（委派 TurnEngine）---

func end_turn(owner: String) -> ActionResult:
	return TurnEngine.end_turn(self, owner)


func mark_over(winner: String) -> void:
	_winner = winner
	_over = true


# 每邏輯步（見 01 §3 logic_update）：回收死亡棋子 + 消化 card_to_draw。
func logic_step() -> void:
	for owner in ["player1", "player2"]:
		_recycle_player(owner)
		if card_to_draw[owner] > 0:
			card_to_draw[owner] -= 1
			get_player(owner).draw_card(rng)
	_recycle_neutral()


# 棋子回合開始刷新（見 base.py refresh）：moving 清除 → on_refresh 能力鉤子（P1-3）。
func refresh_piece(piece: PieceState) -> void:
	piece.set_moving(false)
	# P1-3：ON_REFRESH trigger。


# 棋子結算計分（P1-1 基本版：非 numbness = 1 分；能力掛勾在 P1-3 以 ON_SETTLE 取代）。
# 見 base.py settle/on_settle：SCORED 先查詢不清狀態，計分時才清 numbness。
func settle_piece(piece: PieceState) -> void:
	piece.set_moving(false)
	var was_numb: bool = piece.is_numb()
	var pts: int = 0 if was_numb else 1
	stats.increment(Statistics.StatType.SCORED, piece.uid(), pts)
	# player1 得分 → score 減；player2 得分 → score 加（見 01 §1）。
	if piece.owner == "player1":
		score -= pts
	else:
		score += pts
	if was_numb:
		piece.set_numb(false)


# 回收：health<=0 且 can_be_killed → die 鉤子（P1-3）→ 進棄牌堆、釋放格子。
func _recycle_player(owner: String) -> void:
	var p: PlayerState = get_player(owner)
	var survivors: Array = []
	for piece: PieceState in p.on_board:
		if piece.health <= 0 and _can_be_killed(piece):
			p.discard_pile.append(piece.card_id)
			board.set_occupied(piece.pos(), false)
		else:
			survivors.append(piece)
	p.on_board = survivors


# neutral 棋子回收：直接消失（不進牌庫）。
func _recycle_neutral() -> void:
	var survivors: Array = []
	for piece: PieceState in neutral_pieces:
		if piece.health <= 0 and _can_be_killed(piece):
			board.set_occupied(piece.pos(), false)
		else:
			survivors.append(piece)
	neutral_pieces = survivors


# 死亡判定（P1-3：怒氣不死身覆寫 CAN_BE_KILLED）。
func _can_be_killed(_piece: PieceState) -> bool:
	return true


# --- 對外狀態 ---

func is_over() -> bool:
	return _over


# -1 = 未定 / 平；0 = player1；1 = player2。
func winner() -> int:
	if _winner == "player1":
		return 0
	if _winner == "player2":
		return 1
	return -1


func winner_name() -> String:
	return _winner


# 表現層每幀取走事件（取走後清空）。
func drain_events() -> Array:
	var out: Array = event_sink.duplicate()
	event_sink.clear()
	return out
