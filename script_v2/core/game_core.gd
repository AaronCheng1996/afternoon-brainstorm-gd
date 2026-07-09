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


# --- 行動分派（P1-2，見 01 §4 + battling_dispatcher._execute）---
# 表現層/AI 的唯一輸入口。回合限定行動只有當前回合玩家可執行。
func dispatch(action: GameAction) -> ActionResult:
	const OWNED := ["attack", "play_card", "move_to", "heal", "spawn_cube", "toggle_upgrade", "end_turn"]
	if OWNED.has(action.action_type) and action.player != current_player():
		return ActionResult.new(false, "Not your turn")

	match action.action_type:
		"attack":
			if number_of_attacks[action.player] <= 0:
				return ActionResult.new(false, "攻擊次數不足")
			_attack(action.player, action.board_x, action.board_y)
			return ActionResult.new(true)
		"play_card":
			_play_card(action.player, action.board_x, action.board_y, action.hand_index)
			return ActionResult.new(true)
		"move_to":
			_move_card(action.player, action.board_x, action.board_y)
			return ActionResult.new(true)
		"heal":
			_heal_card(action.player, action.board_x, action.board_y)
			return ActionResult.new(true)
		"spawn_cube":
			_spawn_cube(action.player, action.board_x, action.board_y)
			return ActionResult.new(true)
		"toggle_upgrade":
			_toggle_upgrade(action.player, action.hand_index)
			return ActionResult.new(true)
		"end_turn":
			return end_turn(action.player)
		"quit":
			return ActionResult.new(true, "", true)
	return ActionResult.new(false, "unknown action: " + action.action_type)


# 攻擊執行（前置守衛在 dispatch）。實際傷害管線與扣攻擊次數留待 P1-3。
# P1-3：找 (x,y) 我方棋子 → combat → 成功才扣 attack_uses、記 HIT。
func _attack(_owner: String, _x: int, _y: int) -> void:
	pass


# 出牌（見 player.py play_card）：魔法計數 or 生成棋子。
func _play_card(owner: String, x: int, y: int, index: int) -> void:
	var p: PlayerState = get_player(owner)
	if index < -p.hand.size() or index >= p.hand.size():
		return
	var card_name: String = p.hand[index]
	stats.increment(Statistics.StatType.CARD_USE, owner, 1)
	match card_name:
		"HEAL":
			number_of_heals[owner] += 1
			p.discard_pile.append(p.hand.pop_at(index))
		"MOVE":
			number_of_movings[owner] += 1
			p.discard_pile.append(p.hand.pop_at(index))
		"MOVEO":
			# MOVEO 為臨時卡：出牌即消失（不進棄牌堆）；未出的在回合結束被清（見 turn_engine._turn_end）。
			number_of_movings[owner] += 1
			p.hand.pop_at(index)
		"CUBES":
			number_of_cubes[owner] += GameConfig.CUBES_PER_CARD
			p.discard_pile.append(p.hand.pop_at(index))
		_:
			var real_name: String = card_name
			var upgrade: bool = false
			if card_name.ends_with(" (+)"):
				real_name = card_name.substr(0, card_name.length() - 4)
				upgrade = true
			if _spawn_card(x, y, real_name, owner, p.on_board, upgrade):
				p.hand.pop_at(index)


# 生成棋子（見 factory.spawn_card）：格子有效且空 → 生成 → deploy 鉤子 → 佔格。
# 回傳是否生成成功（生成失敗牌留手上）。Cyan 價格檢查（price_check）留待 P1-10。
func _spawn_card(x: int, y: int, card_name: String, owner: String, target_board: Array, upgrade: bool = false) -> bool:
	var target_pos: Vector2i = Vector2i(x, y)
	if not board.is_free(target_pos):
		return false
	var piece: PieceState = PieceState.make(card_name, owner, x, y, balance)
	piece.upgrade = upgrade
	# P1-3：ON_DEPLOY trigger（card.deploy）在此發動；P1-10：Cyan price_check 攔截。
	board.set_occupied(target_pos, true)
	target_board.append(piece)
	event_sink.append(GameEventV2.spawn(target_pos, piece.card_id, owner))
	return true


# 治療（見 player.py heal_card + base.heal）：回 6 HP、溢出 //2 轉盾。
func _heal_card(owner: String, x: int, y: int) -> void:
	if number_of_heals[owner] <= 0:
		return
	stats.increment(Statistics.StatType.HEAL_USE, owner, 1)
	for piece: PieceState in get_player(owner).on_board:
		if piece.board_x == x and piece.board_y == y:
			_heal_piece(piece, GameConfig.HEAL_AMOUNT)
			number_of_heals[owner] -= 1
			break


# 對單一棋子治療（見 base.heal）：不超過 max 直接加；超過則補滿、溢出 //2 轉 armor。
# Shadow 不可治療的覆寫留待 P1-11。
func _heal_piece(piece: PieceState, value: int) -> bool:
	if piece.health + value <= piece.max_health:
		piece.health += value
	else:
		piece.health += value
		piece.armor += (piece.health - piece.max_health) / 2
		piece.health = piece.max_health
	return true


# 移動（兩段式，見 player.py move_card + 01 §4）。
func _move_card(owner: String, x: int, y: int) -> void:
	var p: PlayerState = get_player(owner)
	var moving_cards: Array = p.on_board.filter(func(c: PieceState) -> bool: return c.is_moving())
	if moving_cards.is_empty():
		# 階段 1：無移動中棋子 → 點我方非暈眩棋子且有移動點 → 啟用移動（此時就扣點）。
		for piece: PieceState in p.on_board:
			if piece.board_x == x and piece.board_y == y and not piece.is_numb():
				if number_of_movings[owner] > 0:
					piece.set_moving(true)
					number_of_movings[owner] -= 1
				break
	else:
		# 階段 2：有移動中棋子。先選取（selected），再點目的地執行 move。
		var selected: Array = p.on_board.filter(func(c: PieceState) -> bool: return c.has_status("selected"))
		if selected.size() == 1:
			var sc: PieceState = selected[0]
			sc.set_status("selected", false)
			sc.set_moving(true)
			_move_piece(sc, x, y)
		elif selected.size() == 0:
			for piece: PieceState in p.on_board:
				if piece.board_x == x and piece.board_y == y:
					piece.set_status("selected", true)
					break


# 執行單子移動（見 base.move）：目的地須空且為 8 鄰（切比雪夫距離 1）；失敗不退點（B5）。
func _move_piece(piece: PieceState, x: int, y: int) -> bool:
	# P1-3：custom_move 攔截鉤子（目前無卡使用）。
	if not piece.movable:
		return false
	var target_pos: Vector2i = Vector2i(x, y)
	if board.is_free(target_pos):
		var dx: int = abs(piece.board_x - x)
		var dy: int = abs(piece.board_y - y)
		var adjacent: bool = maxi(dx, dy) == 1   # 切比雪夫 1，自動排除原格 (0,0)
		if not (adjacent and piece.is_moving()):
			piece.set_moving(false)
			return false
		var from_pos: Vector2i = piece.pos()
		stats.increment(Statistics.StatType.MOVE, piece.uid(), 1)
		board.set_occupied(from_pos, false)
		piece.board_x = x
		piece.board_y = y
		board.set_occupied(target_pos, true)
		piece.set_moving(false)
		event_sink.append(GameEventV2.move(target_pos, from_pos))
		# P1-3：after_movement（自己）與 move_broadcast（全場）鉤子。
		return true
	piece.set_moving(false)
	return false


# 放方塊（見 player.py spawn_cube）：格子空 → 生成 neutral CUBE(4HP/0atk)。
func _spawn_cube(owner: String, x: int, y: int) -> void:
	if number_of_cubes[owner] <= 0:
		return
	if _spawn_card(x, y, "CUBE", "neutral", neutral_pieces):
		number_of_cubes[owner] -= 1
		stats.increment(Statistics.StatType.CUBE_USE, owner, 1)


# 切換 Cyan 升級（見 dispatcher toggle_upgrade）：只改手牌名字（加/去 " (+)" 後綴）。
func _toggle_upgrade(owner: String, index: int) -> void:
	var p: PlayerState = get_player(owner)
	if index >= 0 and index < p.hand.size():
		var card_name: String = p.hand[index]
		if card_name.ends_with(" (+)"):
			p.hand[index] = card_name.substr(0, card_name.length() - 4)
		elif card_name.ends_with("C"):
			p.hand[index] = card_name + " (+)"


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
