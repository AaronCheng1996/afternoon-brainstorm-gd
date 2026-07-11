# P2-4 選秀 BP 分派器（翻譯自 core/draft_dispatcher.py DraftDispatcher._execute，本機模式）。
# 純邏輯（RefCounted，零 Node 依賴）。LAN（lan_server/lan_client）與暫停/重連（D8）本輪不做。
# 限制：牌組 12 張上限；單位同名 ≤2；魔法（CUBES/MOVE/MOVEO/HEAL）≤3。
class_name DraftDispatcherV2
extends RefCounted

const MAGIC_CARDS := ["CUBES", "MOVE", "MOVEO", "HEAL"]
const MAX_DECK := 12
const MAX_UNIT := 2
const MAX_MAGIC := 3

# 回合限定行動：僅當前可編輯玩家可執行。
const TURN_GATED := ["add_card", "remove_card", "remove_last_card", "advance_phase", "confirm_start"]


func dispatch(action: DraftActionV2, state: DraftStateV2) -> DraftResultV2:
	return _execute(action, state)   # 本機模式（LAN 略）


func _execute(action: DraftActionV2, state: DraftStateV2) -> DraftResultV2:
	var deck: Array = state.get_deck(action.player)

	if TURN_GATED.has(action.action_type) and state.current_editor() != action.player:
		return DraftResultV2.new(false, "Not your turn")

	match action.action_type:
		"add_card":
			if action.card_name == "" or action.card_name == "None":
				return DraftResultV2.new(false)
			if deck.size() >= MAX_DECK:
				return DraftResultV2.new(false, "Deck is full")
			var is_magic: bool = MAGIC_CARDS.has(action.card_name)
			var limit: int = MAX_MAGIC if is_magic else MAX_UNIT
			if deck.count(action.card_name) >= limit:
				return DraftResultV2.new(false, "Over limit")
			deck.append(action.card_name)
			return DraftResultV2.new(true)
		"remove_card":
			if action.card_name != "" and deck.has(action.card_name):
				deck.remove_at(deck.rfind(action.card_name))   # 移除最後一張同名
			return DraftResultV2.new(true)
		"remove_last_card":
			if not deck.is_empty():
				deck.remove_at(deck.size() - 1)
			return DraftResultV2.new(true)
		"advance_phase":
			if not state.can_advance():
				return DraftResultV2.new(false, "Phase not ready")
			state.advance_phase()
			return _advanced_result(state)
		"confirm_start":
			# 對齊 Python：confirm_start 不檢查 can_advance，直接進下一階段。
			state.advance_phase()
			return _advanced_result(state)
		"toggle_timer":
			state.timer_mode = "countdown" if state.timer_mode == "timer" else "timer"
			return DraftResultV2.new(true)
		"toggle_file_save":
			state.file_auto_delete = not state.file_auto_delete
			return DraftResultV2.new(true)
	return DraftResultV2.new(false, "unknown action: " + action.action_type)


func _advanced_result(state: DraftStateV2) -> DraftResultV2:
	var r := DraftResultV2.new(true)
	r.phase_advanced = true
	r.ready_to_start = state.phase == "done"
	return r
