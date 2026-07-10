# P1-3 White 卡能力組裝（骨架；實際能力於 P1-4 補完）。
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[AbilityV2]）。
# P1-3 階段先註冊 8 張 White 的 card_id（能力清單暫空），確立 registry 結構。
# P1-4 依 02 §White 填入：APW 麻痺、APTW 護盾、SPW 2 分…。
class_name WhiteCardsV2
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[AbilityV2]）。
static func registrations() -> Dictionary:
	return {
		"ADCW": Callable(WhiteCardsV2, "adcw"),
		"APW": Callable(WhiteCardsV2, "apw"),
		"HFW": Callable(WhiteCardsV2, "hfw"),
		"LFW": Callable(WhiteCardsV2, "lfw"),
		"ASSW": Callable(WhiteCardsV2, "assw"),
		"APTW": Callable(WhiteCardsV2, "aptw"),
		"SPW": Callable(WhiteCardsV2, "spw"),
		"TANKW": Callable(WhiteCardsV2, "tankw"),
	}


# 以下皆為 P1-4 待填的骨架（目前無 native 能力）。
static func adcw() -> Array: return []
static func apw() -> Array: return []
static func hfw() -> Array: return []
static func lfw() -> Array: return []
static func assw() -> Array: return []
static func aptw() -> Array: return []
static func spw() -> Array: return []
static func tankw() -> Array: return []
