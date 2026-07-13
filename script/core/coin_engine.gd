# P1-10 金幣引擎（Cyan 系；見 docs/rebuild/02 §Cyan，Python 出處 cards/card_cyan.py CyanCard.get_coins）。
# 主題：金幣累積上限 50；升級卡於生成時付費（price_check 在 GameCore._cyan_price_check）。
# 純靜態函式，操作傳入的 GameCore（保持 core 無 Node 依賴）。
class_name CoinEngine
extends RefCounted

# 金幣上限（Python 硬編碼於 get_coins；05 §4 建議未來移入 setting.json）。
const COIN_MAX: int = 50


# 獲得 value 金幣，累積不超過上限（見 get_coins）。
static func gain(core: GameCore, owner: String, value: int) -> void:
	var cur: int = int(core.players_coin[owner])
	core.players_coin[owner] = mini(cur + value, COIN_MAX)
