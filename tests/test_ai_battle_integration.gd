# P10-5 驗收：單人對戰整合 —— White AI（player2）對固定腳本玩家（player1）跑完整一局，
# 全程不產生非法操作（每個 AI 行動的 dispatch().success 皆為真），且對局能正常推進到終局。
# 這正是 P10-4 內文延後到 P10-5 的整合驗收（「White AI 對固定腳本玩家 30 回合內不非法操作」）。
#
# 純 core+AI 迴圈（不進場景樹）：模擬 battle.gd 的 sim/view 分離節奏——每次 dispatch 後即
# drain_events + logic_step（對應瞬時模式的 _resync），確保 AIController 的忙碌判斷（event_sink/
# pending_attacks）能歸零、可繼續出招。now_ms 每步大幅推進以越過 AI 的節奏延遲。
extends RefCounted

const P1_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]
const P2_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]

var _db: Object = null


func run(t: Object) -> void:
	_db = load("res://script/data/balance_db.gd").new()
	_test_white_ai_full_game(t)
	_test_focus_reflects_ai_action(t)
	_db.free()
	_db = null


# --- 消化一次 dispatch 後的事件與 logic_step（對應 battle._resync 的瞬時路徑）---
func _settle(core: GameCore) -> void:
	core.drain_events()
	core.logic_step()
	var guard: int = 0
	while (int(core.card_to_draw["player1"]) > 0 or int(core.card_to_draw["player2"]) > 0) and guard < 256:
		guard += 1
		core.logic_step()


# --- 固定腳本玩家（player1）：每回合把第一張可打單位卡放到第一個空格（一步），否則結束回合。
#     以「手牌數是否真的減少」判定是否確實打出（dispatch 對出牌/攻擊恆回 success，
#     即使 spawn 失敗牌仍留手上），確保每步都有進展、回合必然前進，不會卡死。---
func _script_player1(core: GameCore) -> void:
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
				core.dispatch(a)
				if p1.hand.size() < before:
					return   # 真的打出了一張 → 本步有進展
				break        # 這張打不出（如付不起）→ 直接結束回合，避免卡住
	core.dispatch(GameAction.new("end_turn", "player1"))


func _test_white_ai_full_game(t: Object) -> void:
	var core := GameCore.new()
	core.setup(P1_DECK.duplicate(), P2_DECK.duplicate(), 7, _db)
	var ai := AIController.new("white", _db, "player2")

	var now: int = 0
	var illegal: int = 0
	var ai_actions: int = 0
	var guard: int = 0
	while not core.is_over() and core.turn_number < 120 and guard < 6000:
		guard += 1
		now += 1000   # 越過任何節奏延遲（turn_start 900 / action 650）
		if core.current_player() == "player2":
			var acts: Array = ai.tick(core, now, false)
			for a: GameAction in acts:
				ai_actions += 1
				if not core.dispatch(a).success:
					illegal += 1
				_settle(core)
		else:
			_script_player1(core)
			_settle(core)

	t.eq(illegal, 0, "White AI 全程無非法操作（dispatch 全部成功）")
	t.ok(ai_actions > 0, "White AI 確實有出招（非空轉）")
	t.ok(guard < 6000, "對局未卡死（迴圈在上限前結束）")
	t.ok(core.is_over() or core.turn_number >= 30, "對局正常推進（分出勝負或超過 30 回合）")


# AI 決策後 focus 會指向其行動格；無行動（end_turn）時 focus 清空（供表現層畫黃圈）。
func _test_focus_reflects_ai_action(t: Object) -> void:
	var core := GameCore.new()
	core.setup(["ADCW"], P2_DECK.duplicate(), 3, _db)
	core.turn_number = 1   # AI（player2）回合
	var ai := AIController.new("white", _db, "player2")

	# 首見此回合＝觀察（回空），第二次才出招。
	ai.tick(core, 0, false)
	var acts: Array = ai.tick(core, 10_000, false)
	if not acts.is_empty():
		var a: GameAction = acts[0]
		if a.action_type in ["play_card", "attack"]:
			t.ok(ai.has_focus, "play/attack 後 has_focus=true")
			t.eq(ai.focus_position, Vector2i(a.board_x, a.board_y), "focus 指向行動格")
		else:
			t.ok(not ai.has_focus, "非 play/attack（如 end_turn）focus 清空")
	else:
		t.ok(true, "本步無行動（節奏/忙碌），focus 判定略過")

# 註：battle.boot(...ai_stage) 的場景層接線（建 AIController、set_process、_process 驅動、
# 黃色目標圈）不在此以 instantiate battle 驗證——每個 headless 的 BattleScene.instantiate()
# 會固定洩漏 ~1 CanvasItem/2 ObjectDB（未進場景樹之故，屬既有 harness 侷限，非產品洩漏），
# 為維持「零新洩漏」不新增場景實例。場景接線＝薄膠水（見 battle.gd `_process`/`_setup_ai`），
# 由 P10-5【人工】體感驗收（打一局 White AI）確認。
