# P1-9 圖騰引擎（DarkGreen 深綠主題）。純靜態，操作傳入的 GameCore。
# 翻譯自 cards/card_dark_green.py DarkGreenCard.engraved_totem：
#   對 owner 的 players_totem 增加 times × (engraved_totem_coefficient ^ 場上 SPDKG 數)。
#   即每有一張 SPDKG 在場，本次刻印量翻倍（2^n；係數讀 DarkGreen/SP/engraved_totem_coefficient=2）。
class_name TotemEngineV2
extends RefCounted


# 刻印圖騰 times 次（times<=0 為無效）。
static func engrave(core: GameCore, owner: String, times: int) -> void:
	if times <= 0:
		return
	var coef: int = int(core.balance.param("SPDKG", "engraved_totem_coefficient", 2))
	var n: int = 0
	for c: PieceState in core.get_player(owner).on_board:
		if c.card_id == "SPDKG":
			n += 1
	var per: int = _int_pow(coef, n)
	core.players_totem[owner] += times * per


# 整數次方（避免浮點誤差）。
static func _int_pow(base: int, exp: int) -> int:
	var r: int = 1
	for _i in exp:
		r *= base
	return r
