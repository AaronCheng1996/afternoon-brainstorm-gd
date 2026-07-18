# P11-2 驗收：對戰紀錄與回放（script/core/replay_log.gd）。
# 核心保證：錄一局的 action 流 → ReplayLog.simulate 重播 → 最終分數/回合/統計完全一致
# （決定性由 RngService(seed) 保證）。另驗 JSONL 序列化 round-trip 與空/檔案 I/O。
extends RefCounted

const P1_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]
const P2_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]

var _db: Object = null


func run(t: Object) -> void:
	_db = load("res://script/data/balance_db.gd").new()
	_test_record_then_replay_matches(t)
	_test_jsonl_roundtrip(t)
	_test_from_jsonl_empty(t)
	_db.free()
	_db = null


func _settle(core: GameCore) -> void:
	core.drain_events()
	core.logic_step()
	var g: int = 0
	while (int(core.card_to_draw["player1"]) > 0 or int(core.card_to_draw["player2"]) > 0) and g < 256:
		g += 1
		core.logic_step()


# 統一分派點：dispatch → 記錄 → 同步（對應 battle 的瞬時 _resync）。
func _apply(core: GameCore, log: ReplayLog, a: GameAction) -> void:
	core.dispatch(a)
	log.record(a)
	_settle(core)


# 固定腳本玩家 player1：打第一張可打單位卡（未真的打出＝break→end_turn），保證回合前進。
# 每個實際 dispatch 都經 _apply 記入 log（含未生效的 play_card，以維持與重播完全一致）。
func _drive_player1(core: GameCore, log: ReplayLog) -> void:
	var p1: PlayerState = core.player1
	var empties: Array = AIQuery.empty_positions(core)
	if not empties.is_empty():
		for i in p1.hand.size():
			if AIQuery.is_playable_unit_card(p1.hand[i]):
				var before: int = p1.hand.size()
				var a := GameAction.new("play_card", "player1")
				a.hand_index = i
				a.board_x = empties[0].x
				a.board_y = empties[0].y
				_apply(core, log, a)
				if p1.hand.size() < before:
					return
				break
	_apply(core, log, GameAction.new("end_turn", "player1"))


func _play_recorded_game() -> ReplayLog:
	var seed_v: int = 7
	var core := GameCore.new()
	core.setup(P1_DECK.duplicate(), P2_DECK.duplicate(), seed_v, _db)
	var log := ReplayLog.new(seed_v, P1_DECK, P2_DECK)
	var ai := AIController.new("white", _db, "player2")
	var now: int = 0
	var guard: int = 0
	while not core.is_over() and core.turn_number < 120 and guard < 6000:
		guard += 1
		now += 1000
		if core.current_player() == "player2":
			for a: GameAction in ai.tick(core, now, false):
				_apply(core, log, a)
		else:
			_drive_player1(core, log)
	# 把最終狀態附在 log 上（供比對），用 meta 欄外的暫存屬性不方便——改由呼叫端各自 simulate 比對。
	return log


func _test_record_then_replay_matches(t: Object) -> void:
	# 為了同時拿「錄製時的最終 core」與「重播 core」，這裡重跑一次錄製流程取原始 core。
	var seed_v: int = 7
	var core := GameCore.new()
	core.setup(P1_DECK.duplicate(), P2_DECK.duplicate(), seed_v, _db)
	var log := ReplayLog.new(seed_v, P1_DECK, P2_DECK)
	var ai := AIController.new("white", _db, "player2")
	var now: int = 0
	var guard: int = 0
	while not core.is_over() and core.turn_number < 120 and guard < 6000:
		guard += 1
		now += 1000
		if core.current_player() == "player2":
			for a: GameAction in ai.tick(core, now, false):
				_apply(core, log, a)
		else:
			_drive_player1(core, log)

	t.ok(log.actions.size() > 0, "錄製：有記錄到 action")

	var sim := ReplayLog.simulate(log, _db)
	t.eq(sim.score, core.score, "重播：最終分數一致（%d）" % core.score)
	t.eq(sim.turn_number, core.turn_number, "重播：最終回合數一致")
	t.eq(sim.is_over(), core.is_over(), "重播：終局狀態一致")
	t.eq(sim.stats.score_history, core.stats.score_history, "重播：每回合分數折線一致")
	t.eq(JSON.stringify(sim.stats.export_for_charts()),
		JSON.stringify(core.stats.export_for_charts()), "重播：完整統計 export 一致")


func _test_jsonl_roundtrip(t: Object) -> void:
	var log := _play_recorded_game()
	var text := log.to_jsonl()
	var back := ReplayLog.from_jsonl(text)
	t.eq(back.seed, log.seed, "JSONL：seed round-trip")
	t.eq(back.p1_deck, log.p1_deck, "JSONL：P1 牌組 round-trip")
	t.eq(back.p2_deck, log.p2_deck, "JSONL：P2 牌組 round-trip")
	t.eq(back.actions.size(), log.actions.size(), "JSONL：action 數 round-trip")
	# 序列化前後重播結果一致。
	var a := ReplayLog.simulate(log, _db)
	var b := ReplayLog.simulate(back, _db)
	t.eq(a.score, b.score, "JSONL：round-trip 後重播分數一致")
	t.eq(JSON.stringify(a.stats.export_for_charts()),
		JSON.stringify(b.stats.export_for_charts()), "JSONL：round-trip 後統計一致")


func _test_from_jsonl_empty(t: Object) -> void:
	var log := ReplayLog.from_jsonl("")
	t.eq(log.actions.size(), 0, "空 JSONL：無 action")
	t.eq(log.seed, 0, "空 JSONL：seed 預設 0")
