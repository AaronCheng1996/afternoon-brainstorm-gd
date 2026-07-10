# P1-3 能力工廠：card_id → AbilityComponentV2（見 docs/rebuild/04 §5.2）。
# 各色的能力組裝分散在 ability/cards/<color>.gd，registry 彙整其 registrations()。
# P1-3 先接 White（骨架）；後續任務逐色補上 red/blue/green…。
class_name AbilityRegistryV2
extends RefCounted

# card_id -> Callable（回傳 Array[AbilityV2]）。惰性建立一次。
static var _table: Dictionary = {}
static var _built: bool = false


static func _build_table() -> void:
	if _built:
		return
	_built = true
	_merge(WhiteCardsV2.registrations())
	_merge(RedCardsV2.registrations())
	_merge(BlueCardsV2.registrations())
	_merge(GreenCardsV2.registrations())
	_merge(OrangeCardsV2.registrations())
	_merge(DarkGreenCardsV2.registrations())
	_merge(CyanCardsV2.registrations())
	# P1-11+：_merge(FuchsiaCardsV2.registrations()) 等逐色加入。


static func _merge(regs: Dictionary) -> void:
	for card_id: String in regs.keys():
		_table[card_id] = regs[card_id]


# 依 card_id 建立掛在 piece 上的能力元件（native 由工廠 Callable 產生）。
# 未註冊的 card_id 回傳空元件（合法：多數卡 P1-3 尚未實作）。
static func build(card_id: String, piece: PieceState) -> AbilityComponentV2:
	_build_table()
	var comp := AbilityComponentV2.new(piece)
	if _table.has(card_id):
		var factory: Callable = _table[card_id]
		var abilities: Variant = factory.call()
		if abilities is Array:
			comp.native = abilities
	return comp


# 依 id 建立單一附魔能力（附魔 API 用；P1-3 先保留介面）。
# 目前無註冊的附魔範本，回傳 null；未來以名稱查表。
static func make(_enchant_id: String) -> AbilityV2:
	return null
