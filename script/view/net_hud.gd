# P15-2 連線 HUD 共用顯示文字（純靜態、零狀態、零 Node）。
#
# 由來：連線品質文字原本在 battle.gd（`net_quality_text`）、draft.gd（`_rtt_quality`）、
# online_lobby.gd（`_quality_text`）**各有一份完全相同的實作**，三個名字、同一組門檻，
# 改一處就會與另兩處不一致（lobby 那份的註解甚至已經寫成「供子場景 HUD 與大廳共用」，
# 但子場景其實各自帶著自己的副本）。此處收斂為單一定義。
#
# 只放「三個場景逐字相同」的純函式。**狀態列/階段列的組字不放這裡**——
# battle 是多行 HUD 區塊、draft 是單行以「｜」分隔的階段列，格式本就不同
# （既有測試逐字斷言），硬要共用只會逼出一個兩邊都不合身的介面。
class_name NetHud
extends RefCounted

# RTT（毫秒）→ 連線品質文字。門檻 80/160/300 為 P12-17 定值。
static func quality_text(rtt_ms: int) -> String:
	if rtt_ms < 80:
		return "良好"
	if rtt_ms < 160:
		return "普通"
	if rtt_ms < 300:
		return "偏高"
	return "不穩"
