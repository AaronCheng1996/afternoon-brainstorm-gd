# P1-6 Token 引擎（藍色系；見 docs/rebuild/02 §Blue，Python 出處 cards/card_blue.py BlueCard）。
# 主題：每「獲得一次 token」呼叫一次 got_token；累積達門檻（預設 3）換 1 抽。
# 純靜態函式，操作傳入的 GameCore（保持 core 無 Node 依賴）。
class_name TokenEngineV2
extends RefCounted


# 換一抽所需 token 數（Python game_state.how_many_token_to_draw_a_card，來源 config/setting.json）。
static func threshold(core: GameCore) -> int:
	return int(str(core.balance.setting("how_many_token_to_draw_a_card", 3)))


# 我方場上藍卡（承接 after_token / token_draw 廣播；對齊 Python isinstance(card, BlueCard)）。
static func _blue_on_board(core: GameCore, owner: String) -> Array:
	return core.get_player(owner).on_board.filter(
		func(c: PieceState) -> bool: return c.color_code == "B")


# 純加 token，不觸發流程（呼叫端隨後自行 got_token）。
static func add(core: GameCore, owner: String, amount: int) -> void:
	core.players_token[owner] += amount


# 一次「獲得 token」事件（見 Python BlueCard.got_token）：
#   1. 我方所有藍卡 after_token（ON_TOKEN_GAINED）。
#   2. 若 token ≥ 門檻 → 扣門檻、card_to_draw+1、TOKEN_USE 統計、
#      我方所有藍卡 token_draw（ON_TOKEN_DRAW）。
# 注意：門檻檢查是「一次 if」而非 while——每次 got_token 至多換 1 抽（見 P1-6 驗收）。
static func got_token(core: GameCore, owner: String) -> void:
	for c: PieceState in _blue_on_board(core, owner):
		if c.abilities != null:
			c.abilities.run(TriggerV2.Type.ON_TOKEN_GAINED, AbilityContextV2.new(core, c, null, 0, {}))
	var th: int = threshold(core)
	if int(core.players_token[owner]) >= th:
		core.players_token[owner] -= th
		core.card_to_draw[owner] += 1
		core.stats.increment(Statistics.StatType.TOKEN_USE, owner, 1)
		for c: PieceState in _blue_on_board(core, owner):
			if c.abilities != null:
				c.abilities.run(TriggerV2.Type.ON_TOKEN_DRAW, AbilityContextV2.new(core, c, null, 0, {}))


# 便捷：加 amount 個 token，並觸發 times 次 got_token。
# 多數藍卡 amount == times（每點 token 各觸發一次）；ADCB 例外（加 2 只觸發 1 次）。
static func gain(core: GameCore, owner: String, amount: int, times: int) -> void:
	add(core, owner, amount)
	for _i in times:
		got_token(core, owner)
