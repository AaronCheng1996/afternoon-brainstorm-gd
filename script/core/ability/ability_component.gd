# P1-3 能力元件（掛在 PieceState 上，純資料；見 docs/rebuild/04 §5.2、§5.5）。
# 沿用舊原型（script/abilities/）的概念與命名，但搬進 core 重寫（原型掛 Node，不合 D1）。
# 提供：附魔（grant）、沉默（silence）、依觸發點分派（run/dispatch_mod/any_true/collect_field）。
class_name AbilityComponentV2
extends RefCounted

# 能力分類標籤（沉默可依 tag 停用整類）。
enum Tag { TRIGGERED, PASSIVE, ON_ENTER, FACTION, MODIFIER }

# 持有此元件的棋子（弱參考：避免 piece.abilities ←→ component.source 的強引用循環洩漏）。
var _source_ref: WeakRef = null
var native: Array = []                # Array[AbilityV2]：registry 依 card_id 組裝
var granted: Array = []               # Array[AbilityV2]：附魔（動態掛上）
var silenced_ids: Dictionary = {}     # id -> true
var silenced_tags: Dictionary = {}    # Tag(int) -> true


func _init(owner: PieceState = null) -> void:
	_source_ref = weakref(owner)


# 取得持有此元件的棋子（可能已被回收 → null）。
func source() -> PieceState:
	return _source_ref.get_ref() if _source_ref != null else null


# --- 附魔 API（見 04 §5.5）---

func grant(a: AbilityV2) -> void:
	granted.append(a)


func clear_granted() -> void:
	granted.clear()


# --- 沉默 API（見 04 §5.5）---

func silence(id: String) -> void:
	silenced_ids[id] = true


func silence_tag(tag: int) -> void:
	silenced_tags[tag] = true


func clear_silence() -> void:
	silenced_ids.clear()
	silenced_tags.clear()


# 某能力目前是否有效（未被沉默）。
func is_ability_active(a: AbilityV2) -> bool:
	if silenced_ids.has(a.id):
		return false
	for tag: int in a.tags:
		if silenced_tags.has(tag):
			return false
	return true


func all_abilities() -> Array:
	var out: Array = []
	out.append_array(native)
	out.append_array(granted)
	return out


# 取某觸發點下、有效且 condition 通過的能力，依 priority 升冪排序。
func _active_for(trigger: int, ctx: AbilityContextV2) -> Array:
	var matched: Array = []
	for a: AbilityV2 in all_abilities():
		if a.trigger != trigger:
			continue
		if not is_ability_active(a):
			continue
		if a.condition.is_valid() and not bool(a.condition.call(ctx)):
			continue
		matched.append(a)
	if matched.size() > 1:
		matched.sort_custom(func(x: AbilityV2, y: AbilityV2) -> bool: return x.priority < y.priority)
	return matched


# 副作用型觸發（ON_KILLED / ON_BEEN_ATTACKED / ON_DEPLOY / ON_REFRESH / ON_DIE…）。
# 逐一執行效果；回傳是否有任一能力被觸發。
func run(trigger: int, ctx: AbilityContextV2) -> bool:
	var any: bool = false
	for a: AbilityV2 in _active_for(trigger, ctx):
		for e: AbilityEffectV2 in a.effects:
			e.execute(ctx)
		any = true
	return any


# 修改型觸發（MOD_DAMAGE_BONUS / MOD_DAMAGE_REDUCE / ON_SETTLE）：串接 ctx.value，回傳最終 int。
func dispatch_mod(trigger: int, ctx: AbilityContextV2) -> int:
	for a: AbilityV2 in _active_for(trigger, ctx):
		for e: AbilityEffectV2 in a.effects:
			var r: Variant = e.execute(ctx)
			if typeof(r) == TYPE_INT:
				ctx.value = r
	return ctx.value


# 布林型觸發（BLOCK_DAMAGE / ON_ABILITY_HIT / CAN_BE_KILLED / CUSTOM_MOVE）：任一效果回傳 true 即 true。
func any_true(trigger: int, ctx: AbilityContextV2) -> bool:
	for a: AbilityV2 in _active_for(trigger, ctx):
		for e: AbilityEffectV2 in a.effects:
			var r: Variant = e.execute(ctx)
			if typeof(r) == TYPE_BOOL and r:
				return true
	return false


# 攻擊覆寫（ATTACK_OVERRIDE）：卡牌可完全接管攻擊流程（見 04 §5.1）。
# 回傳 Variant：null＝無覆寫（照常攻擊）；bool＝覆寫結果（攻擊是否算成功、是否消耗次數）。
# 用途：APTG 禁攻回傳 false；ADCO（P1-8）覆寫成攻擊後自動移動等。
func dispatch_attack_override(ctx: AbilityContextV2) -> Variant:
	for a: AbilityV2 in _active_for(TriggerV2.Type.ATTACK_OVERRIDE, ctx):
		for e: AbilityEffectV2 in a.effects:
			var r: Variant = e.execute(ctx)
			if typeof(r) == TYPE_BOOL:
				return r
	return null


# 場地攔截（MOD_FIELD_INTERCEPT）：收集本棋子回傳的 {priority, value, feedback} 修改子。
func collect_field(ctx: AbilityContextV2) -> Array:
	var out: Array = []
	for a: AbilityV2 in _active_for(TriggerV2.Type.MOD_FIELD_INTERCEPT, ctx):
		for e: AbilityEffectV2 in a.effects:
			var r: Variant = e.execute(ctx)
			if typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).is_empty():
				out.append(r)
	return out
