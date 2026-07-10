# P1-3 驗收：能力系統骨架（沉默 / 附魔）（見 docs/rebuild/06 P1-3、04 §5.5）。
extends RefCounted


func _make_core(seed_v: int) -> GameCore:
	var db: Object = load("res://script_v2/data/balance_db.gd").new()
	var core := GameCore.new()
	var deck: Array = []
	for _i in 12:
		deck.append("ADCW")
	core.setup(deck, deck, seed_v, db)
	return core


func run(t: Object) -> void:
	var core := _make_core(1)

	var piece := PieceState.make("TANKW", "player1", 0, 0, core.balance)
	var box: Dictionary = {"n": 0}
	var tags: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	var ab := AbilityV2.new("test_refresh", TriggerV2.Type.ON_REFRESH, [CounterEffect.new(box)], tags)

	# --- grant 後新能力生效 ---
	piece.abilities.grant(ab)
	core.refresh_piece(piece)
	t.eq(box["n"], 1, "grant 後 ON_REFRESH 觸發（n=1）")

	# --- silence(id) 後不觸發 ---
	piece.abilities.silence("test_refresh")
	t.ok(not piece.abilities.is_ability_active(ab), "silence(id) 後 is_ability_active=false")
	core.refresh_piece(piece)
	t.eq(box["n"], 1, "沉默(by id) 期間不觸發（n 維持 1）")

	# --- clear_silence 恢復 ---
	piece.abilities.clear_silence()
	core.refresh_piece(piece)
	t.eq(box["n"], 2, "clear_silence 後恢復觸發（n=2）")

	# --- silence_tag 後不觸發 ---
	piece.abilities.silence_tag(AbilityComponentV2.Tag.TRIGGERED)
	core.refresh_piece(piece)
	t.eq(box["n"], 2, "沉默(by tag) 期間不觸發（n 維持 2）")

	# --- clear_silence 再恢復 ---
	piece.abilities.clear_silence()
	core.refresh_piece(piece)
	t.eq(box["n"], 3, "clear_silence 後再恢復（n=3）")

	# --- clear_granted 移除附魔能力 ---
	piece.abilities.clear_granted()
	core.refresh_piece(piece)
	t.eq(box["n"], 3, "clear_granted 後能力移除，不再觸發（n 維持 3）")

	# --- MOD_DAMAGE 類串接：附魔 +2 傷害加成 ---
	var atk := PieceState.make("ADCW", "player1", 0, 0, core.balance); atk.extra_damage = 0
	var vic := PieceState.make("TANKW", "player2", 1, 0, core.balance)
	vic.health = 20; vic.max_health = 20; vic.armor = 0
	atk.set_numb(false); vic.set_numb(false)
	core.player1.on_board.append(atk); core.player2.on_board.append(vic)
	var mtags: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	atk.abilities.grant(AbilityV2.new("bonus2", TriggerV2.Type.MOD_DAMAGE_BONUS, [BonusEffect.new(2)], mtags))
	CombatV2.damage_calculate(core, vic, 3, atk, false, 0.0)
	t.eq(vic.health, 15, "MOD_DAMAGE_BONUS 串接：3+2=5 傷害，20→15")

	core.balance.free()


# --- 測試用假效果 ---

# 每次觸發把計數 +1。
class CounterEffect extends AbilityEffectV2:
	var box: Dictionary
	func _init(b: Dictionary) -> void:
		box = b
	func execute(_ctx: AbilityContextV2) -> Variant:
		box["n"] = int(box.get("n", 0)) + 1
		return null


# MOD 類：把 ctx.value 加上固定量並回傳。
class BonusEffect extends AbilityEffectV2:
	var amount: int
	func _init(a: int) -> void:
		amount = a
	func execute(ctx: AbilityContextV2) -> Variant:
		return ctx.value + amount
