# P12-6 連線對戰工作階段（見 docs/rebuild/10_連線版本.md §4/§6，決策 D18/D19）。
# 每房一顆權威 GameCore 的薄包裝：純邏輯（RefCounted、零 Node）——setup、dispatch 一位席位
# 玩家的行動、消化 logic_step、伺服器權威回合計時。廣播由 NetGameServer 負責（本類只回資料）。
#
# **遊戲迴圈嚴格對齊本機 battle.gd**（dispatch → drain_events → logic_step 迴圈；見 _collect），
# 確保伺服器權威結果與本機/參考核心逐位一致（P12-6 驗收）。事件的 delay 游標於各次 drain 歸零
# 只影響動畫節奏（純演出），不影響對局狀態。
#
# **隱藏資訊（D19）**：seed 只存於 core.rng（本類建立時傳入）、永不下發；對外只吐 GameEvent 與
# GameSnapshot（皆不含 seed／牌庫序，見 GameSnapshot 鐵則）。
class_name NetGameSession
extends RefCounted

# 開發旗標用預設牌組（P12-6 跳過 BP 先驗證對戰鏈路；正式流程走 P12-8 的連線 BP，見 §6）。
# 皆為合法牌組（12 張、單位＋魔法），沿用整合測試用組合。
const DEV_P1_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]
const DEV_P2_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]

var core: GameCore = null
var turn_timer: CountdownTimer = CountdownTimer.new()
# P12-11 server 端對局紀錄（沿用 P11-2 ReplayLog 格式）：seed＋雙方牌組＋成功 action 流。
# 終局／掉線判勝時由伺服器存檔（save_replays 開時）；決定性重播免費（ReplayLog.simulate）。
var replay: ReplayLog = null
var _db: Object = null


# 開局：建權威 core（seed 只存此處）、消化開局事件與 logic_step、備妥回合計時。
# 回傳開局事件陣列（供伺服器廣播）。db 為 null 時 GameCore.setup 用 autoload Balance。
func start(p1_deck: Array, p2_deck: Array, seed_value: int, db: Object = null,
		turn_on: bool = false, turn_seconds: float = 60.0) -> Array:
	_db = db
	core = GameCore.new()
	core.setup(p1_deck.duplicate(), p2_deck.duplicate(), seed_value, db)
	replay = ReplayLog.new(seed_value, p1_deck, p2_deck)   # P12-11：起錄（seed 只存此，不下發）
	turn_timer.configure(turn_on, turn_seconds)
	var events := _collect()
	_arm_timer()
	return events


# 套用某席位玩家的行動（player 已由伺服器依席位指派——不採用 client 宣稱值）。
# 回傳 {ok, message, events, turn_changed, over}：
#   ok=false＝dispatch 拒絕（回合閘／次數不足…），message 供回傳行動者；events 為空。
#   ok=true ＝已套用，events 為本次全部表現層事件（drain＋logic）。
func apply_action(player: String, action: GameAction) -> Dictionary:
	if core == null or core.is_over():
		return _fail("battle_over")
	action.player = player   # 伺服器權威：忽略 client 宣稱的 player
	var turn_before := core.turn_number
	var res: ActionResult = core.dispatch(action)
	if not res.success:
		return {"ok": false, "message": res.message, "events": [],
			"turn_changed": false, "over": core.is_over()}
	if replay != null:
		replay.record(action)   # P12-11：只錄成功 action（＝可重播的權威流，對齊 battle 錄影）
	var events := _collect()
	var turn_changed := core.turn_number != turn_before
	if turn_changed:
		_arm_timer()
	return {"ok": true, "message": "", "events": events,
		"turn_changed": turn_changed, "over": core.is_over()}


# 伺服器每幀推進回合計時；逾時→自動 end_turn（權威裁決，見 §6）。
# 逾時時回傳同 apply_action 的結果（ok=true）；未逾時回 idle（ok=false、events 空）。
func tick(delta: float) -> Dictionary:
	if core == null or core.is_over() or not turn_timer.enabled:
		return _idle()
	if turn_timer.advance(delta):
		var cur := core.current_player()
		return apply_action(cur, GameAction.new("end_turn", cur))
	return _idle()


# 目前權威狀態的公開快照（開局／回合交接／終局校正用；不含 seed／牌庫序，D19）。
func snapshot() -> Dictionary:
	return GameSnapshot.encode(core) if core != null else {}


func is_over() -> bool:
	return core != null and core.is_over()


# --- 內部 ---

# 對齊 battle.gd 的 dispatch 後消化：先取 dispatch 事件、再跑 logic_step 迴圈（回收死亡＋逐步
# 補抽，card_to_draw 可 >1），最後取 logic 期間產生的事件（如死亡觸發的生成）。
func _collect() -> Array:
	var events := core.drain_events()
	_drain_logic()
	events.append_array(core.drain_events())
	return events


func _drain_logic() -> void:
	core.logic_step()
	var guard := 0
	while (int(core.card_to_draw["player1"]) > 0 or int(core.card_to_draw["player2"]) > 0) and guard < 256:
		guard += 1
		core.logic_step()


func _arm_timer() -> void:
	turn_timer.start()


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "message": msg, "events": [], "turn_changed": false, "over": true}


func _idle() -> Dictionary:
	return {"ok": false, "message": "", "events": [], "turn_changed": false,
		"over": core != null and core.is_over()}
