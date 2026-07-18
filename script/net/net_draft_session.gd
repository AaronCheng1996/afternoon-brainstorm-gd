# P12-8 連線選秀工作階段（見 docs/rebuild/10_連線版本.md §6，決策 D18）。
# 每房一顆權威選秀狀態機的薄包裝：純邏輯（RefCounted、零 Node）——包 DraftState＋
# DraftDispatcher，套用一位席位玩家的選秀行動、伺服器權威選秀計時逾時自動補牌。
# 廣播由 NetGameServer 負責（本類只回資料）。BP 全公開（§6）→ 單一公開 view，無逐客端遮蔽。
#
# 規則以本機為準（DraftDispatcher）：回合閘（僅當前可編輯玩家）、12 上限、單位 ≤2、魔法 ≤3；
# 逾時＝server 執行 auto_fill_and_advance（P11-1 純函式），與本機同一套規則、結果權威。
class_name NetDraftSession
extends RefCounted

# 自動補牌候選＝各色 units（魅紫僅 4 職）＋魔法（對齊 draft.gd 的 _build_pool 選秀池；
# MOVEO 為臨時卡不入選秀）。此處刻意複寫該資料以維持 net 層與 scenes 層解耦（零場景依賴）。
const _COLORS := ["W", "R", "G", "B", "O", "DKG", "C", "F", "BR", "P"]
const _JOBS := ["ADC", "AP", "TANK", "HF", "LF", "ASS", "APT", "SP"]
const _PURPLE_JOBS := ["AP", "TANK", "HF", "ASS"]
const _MAGIC := ["CUBES", "HEAL", "MOVE"]

var state: DraftState = null
var dispatcher: DraftDispatcher = null
var phase_timer: CountdownTimer = CountdownTimer.new()
var pool: Array = []
# 對戰用 seed：於選秀完成後傳給 GameCore（seed 只存伺服器，D19）。
var seed_value: int = 0


# 開始選秀：建 DraftState／Dispatcher／補牌池，備妥（可選）選秀計時。
func start(seed_v: int, timer_on: bool = false, seconds: float = 45.0) -> void:
	state = DraftState.new()
	dispatcher = DraftDispatcher.new()
	pool = _build_pool()
	seed_value = seed_v
	phase_timer.configure(timer_on, seconds)
	_arm_timer()


# 套用某席位玩家的選秀行動（player 由伺服器依席位指派——不採 client 宣稱值）。
# 回傳 {ok, message, phase_advanced, ready_to_start, done}：
#   ok=false＝dispatcher 拒絕（回合閘／上限…），message 供回傳行動者。
func apply(player: String, action: DraftAction) -> Dictionary:
	if state == null or state.phase == "done":
		return {"ok": false, "message": "draft_over", "phase_advanced": false,
			"ready_to_start": false, "done": true}
	action.player = player   # 伺服器權威：忽略 client 宣稱的 player
	var r: DraftResult = dispatcher.dispatch(action, state)
	if not r.success:
		return {"ok": false, "message": r.message, "phase_advanced": false,
			"ready_to_start": false, "done": state.phase == "done"}
	if r.phase_advanced:
		_arm_timer()   # 進入下一階段 → 重啟該階段倒數
	return {"ok": true, "message": "", "phase_advanced": r.phase_advanced,
		"ready_to_start": r.ready_to_start, "done": state.phase == "done"}


# 伺服器每幀推進選秀計時；逾時→自動補牌並進下一階段（權威裁決，見 §6）。
# 逾時時回傳 {ok:true, timed_out:true, phase_advanced, done}；未逾時回 idle（ok:false）。
func tick(delta: float) -> Dictionary:
	if state == null or state.phase == "done" or not phase_timer.enabled \
			or state.current_editor() == "":
		return _idle()
	if phase_timer.advance(delta):
		var r: DraftResult = dispatcher.auto_fill_and_advance(state, pool)
		_arm_timer()
		return {"ok": true, "timed_out": true, "phase_advanced": true,
			"ready_to_start": r.ready_to_start, "done": state.phase == "done"}
	return _idle()


func is_done() -> bool:
	return state != null and state.phase == "done"


# 公開選秀 view（BP 全公開，D19：無 seed／無隱藏資訊）。每次行動/逾時後廣播全房。
# remaining＝server 權威選秀倒數剩餘秒（<0＝未計時，客端不顯示；相容性小追加，見 10 §11.2-6）。
func view() -> Dictionary:
	return {
		"phase": state.phase,
		"editor": state.current_editor(),
		"player1_deck": state.player1_deck.duplicate(),
		"player2_deck": state.player2_deck.duplicate(),
		"player1_count": state.player1_deck.size(),
		"player2_count": state.player2_deck.size(),
		"remaining": phase_timer.remaining_seconds() if phase_timer.running else -1,
		"done": state.phase == "done",
	}


# 完成後供伺服器建 GameCore 的雙方牌組（複本）。
func decks() -> Array:
	return [state.player1_deck.duplicate(), state.player2_deck.duplicate()]


# --- 內部 ---

func _build_pool() -> Array:
	var out: Array = []
	for code: String in _COLORS:
		var jobs: Array = _PURPLE_JOBS if code == "P" else _JOBS
		for job: String in jobs:
			out.append(job + code)
	out.append_array(_MAGIC)
	return out


# 有可編輯玩家且計時開啟 → 重啟該階段倒數；否則停。
func _arm_timer() -> void:
	if phase_timer.enabled and state.current_editor() != "":
		phase_timer.start()
	else:
		phase_timer.stop()


func _idle() -> Dictionary:
	return {"ok": false, "timed_out": false, "phase_advanced": false,
		"ready_to_start": false, "done": state != null and state.phase == "done"}
