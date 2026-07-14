# P2-4 選秀 BP 分派器（翻譯自 core/draft_dispatcher.py DraftDispatcher._execute，本機模式）。
# 純邏輯（RefCounted，零 Node 依賴）。LAN（lan_server/lan_client）與暫停/重連（D8）本輪不做。
# 限制：牌組 12 張上限；單位同名 ≤2；魔法（CUBES/MOVE/MOVEO/HEAL）≤3。
class_name DraftDispatcher
extends RefCounted

const MAGIC_CARDS := ["CUBES", "MOVE", "MOVEO", "HEAL"]
const MAX_DECK := 12
const MAX_UNIT := 2
const MAX_MAGIC := 3

# 回合限定行動：僅當前可編輯玩家可執行。
const TURN_GATED := ["add_card", "remove_card", "remove_last_card", "advance_phase", "confirm_start"]


func dispatch(action: DraftAction, state: DraftState) -> DraftResult:
	return _execute(action, state)   # 本機模式（LAN 略）


func _execute(action: DraftAction, state: DraftState) -> DraftResult:
	var deck: Array = state.get_deck(action.player)

	if TURN_GATED.has(action.action_type) and state.current_editor() != action.player:
		return DraftResult.new(false, "Not your turn")

	match action.action_type:
		"add_card":
			if action.card_name == "" or action.card_name == "None":
				return DraftResult.new(false)
			if deck.size() >= MAX_DECK:
				return DraftResult.new(false, "Deck is full")
			var is_magic: bool = MAGIC_CARDS.has(action.card_name)
			var limit: int = MAX_MAGIC if is_magic else MAX_UNIT
			if deck.count(action.card_name) >= limit:
				return DraftResult.new(false, "Over limit")
			deck.append(action.card_name)
			return DraftResult.new(true)
		"remove_card":
			if action.card_name != "" and deck.has(action.card_name):
				deck.remove_at(deck.rfind(action.card_name))   # 移除最後一張同名
			return DraftResult.new(true)
		"remove_last_card":
			if not deck.is_empty():
				deck.remove_at(deck.size() - 1)
			return DraftResult.new(true)
		"advance_phase":
			if not state.can_advance():
				return DraftResult.new(false, "Phase not ready")
			state.advance_phase()
			return _advanced_result(state)
		"confirm_start":
			# 對齊 Python：confirm_start 不檢查 can_advance，直接進下一階段。
			state.advance_phase()
			return _advanced_result(state)
		"toggle_timer":
			state.timer_mode = "countdown" if state.timer_mode == "timer" else "timer"
			return DraftResult.new(true)
		"toggle_file_save":
			state.file_auto_delete = not state.file_auto_delete
			return DraftResult.new(true)
	return DraftResult.new(false, "unknown action: " + action.action_type)


func _advanced_result(state: DraftState) -> DraftResult:
	var r := DraftResult.new(true)
	r.phase_advanced = true
	r.ready_to_start = state.phase == "done"
	return r


# P11-1 逾時自動補牌並進下一階段：把當前可編輯玩家的牌組補到「可進階」的最低張數，
# 再 advance_phase。補牌從 pool 依序挑第一張「合法（過 add_card 規則）」的卡，直到 can_advance。
# 純邏輯（零 Node），供 draft 計時逾時呼叫與 headless 測。回傳 advance 後的 DraftResult
# （若已無可編輯玩家＝done，回傳 phase_advanced=false 的成功結果）。
func auto_fill_and_advance(state: DraftState, pool: Array) -> DraftResult:
	var editor: String = state.current_editor()
	if editor == "":
		return DraftResult.new(true)
	var guard: int = 0
	while not state.can_advance() and guard < DraftDispatcher.MAX_DECK * 4:
		guard += 1
		var added: bool = false
		for cid: String in pool:
			var a := DraftAction.new(editor, "add_card", cid)
			if _execute(a, state).success:
				added = true
				break
		if not added:
			break   # pool 無合法可補（理論上不會發生）→ 停止補牌，仍嘗試 advance
	return _execute(DraftAction.new(editor, "advance_phase"), state)
