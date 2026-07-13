# P1-1 回合引擎：開局 / 回合開始 / 回合結束（結算計分）流程。
# 權威順序見 docs/rebuild/01 §3；翻譯自 core/player.py + core/battling_dispatcher.py end_turn。
# 純靜態函式，操作傳入的 GameCore（保持 core 無 Node 依賴）。
class_name TurnEngine
extends RefCounted


# 開局（見 01 §3【開局】）：
#   雙方 discard_pile = deck 複本 → 各抽 3 張 → player1 額外 +1 攻擊次數（先手補償）。
#   注意：第一回合「不執行」player1 的 turn_start，故 p1 首回合只有 3 張手牌、1 次攻擊。
static func initialize(core: GameCore) -> void:
	for owner in ["player1", "player2"]:
		var p: PlayerState = core.get_player(owner)
		p.discard_pile.assign(p.deck)
		for _i in GameConfig.STARTER_HAND:
			p.draw_card(core.rng)
	core.number_of_attacks["player1"] += GameConfig.P1_EXTRA_ATTACK


# 回合開始（見 01 §3【turn_start】）：
#   skip_turn_draw → 清旗標且不抽；否則抽 1 張。攻擊次數 +1。
#   我方每個場上棋子：ROUNDS_SURVIVED +1 → refresh()。
static func turn_start(core: GameCore, owner: String) -> void:
	if core.skip_turn_draw[owner]:
		core.skip_turn_draw[owner] = false
	else:
		core.get_player(owner).draw_card(core.rng)
	core.number_of_attacks[owner] += 1
	for piece: PieceState in core.get_player(owner).on_board:
		core.stats.increment(Statistics.StatType.ROUNDS_SURVIVED, piece.uid(), 1)
		core.refresh_piece(piece)


# 回合結束（見 01 §3【end_turn】 + battling_dispatcher end_turn）：
#   turn_number += 1 → 我方 turn_end（結算計分）→ 記 score_history →
#   若 |score| >= win_threshold 判定勝負並回傳（不換手）→ 否則對方 turn_start。
static func end_turn(core: GameCore, owner: String) -> ActionResult:
	core.turn_number += 1
	var opponent: String = core.opponent_name(owner)
	_turn_end(core, owner)
	core.stats.add_score_record(core.score)
	if abs(core.score) >= core.config.win_threshold:
		var winner: String = "player1" if core.score < 0 else "player2"
		core.mark_over(winner)
		return ActionResult.new(true, winner, true)
	turn_start(core, opponent)
	return ActionResult.new(true, "", false, true)


# 我方回合收尾（見 player.py turn_end）：
#   清 selected；手牌移除所有 MOVEO；cubes/movings/heals 歸零（未用完不保留）；
#   我方每個場上棋子 settle()。
static func _turn_end(core: GameCore, owner: String) -> void:
	var p: PlayerState = core.get_player(owner)
	p.hand.assign(p.hand.filter(func(c: String) -> bool: return c != "MOVEO"))
	core.number_of_cubes[owner] = 0
	core.number_of_movings[owner] = 0
	core.number_of_heals[owner] = 0
	for piece: PieceState in p.on_board:
		core.settle_piece(piece)
