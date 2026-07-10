# P1-11 Fuchsia 全卡能力組裝（見 docs/rebuild/02 §Fuchsia，Python 出處 cards/card_fuchsia.py）。
# 紫紅主題：鏡像 Shadow——佈署在本體中心對稱位 (3-x, 3-y) 生成 HP1/ATK0 的 SHADOW 棋子，
# 由 linker（本體）代打（用本體 ATK、經本體 hit_cards/能力），本體移動時鏡像同步移動。
#
# 架構決策：SHADOW 不進 on_board/neutral（不可被當敵方目標、不參與計分/回收），
# 只存在於 linker.shadows。鏡像攻擊 = 從鏡像位置 detection 出目標後，以本體為 attacker
# 呼叫 CombatV2.launch_attack(custom_targets)，所有攻擊鉤子（ON_ABILITY_HIT/ON_KILLED…）
# 因此自然落在本體上（對齊 Python Shadow.attack → self.linker.launch_attack(...)）。
#
# 每個 static func 回傳該 card_id 的 native 能力陣列（Array[AbilityV2]）。
class_name FuchsiaCardsV2
extends RefCounted


# 註冊表：card_id -> Callable（回傳 Array[AbilityV2]）。含衍生物 SHADOW。
static func registrations() -> Dictionary:
	return {
		"ADCF": Callable(FuchsiaCardsV2, "adcf"),
		"APF": Callable(FuchsiaCardsV2, "apf"),
		"TANKF": Callable(FuchsiaCardsV2, "tankf"),
		"HFF": Callable(FuchsiaCardsV2, "hff"),
		"LFF": Callable(FuchsiaCardsV2, "lff"),
		"ASSF": Callable(FuchsiaCardsV2, "assf"),
		"APTF": Callable(FuchsiaCardsV2, "aptf"),
		"SPF": Callable(FuchsiaCardsV2, "spf"),
		"SHADOW": Callable(FuchsiaCardsV2, "shadow"),
	}


# ADCF：佈署生鏡像；攻擊時本體與鏡像都發動（大十字）；本體無目標時只有鏡像打也算成功。
static func adcf() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_adc_deploy", TriggerV2.Type.ON_DEPLOY, [DeploySpawnShadowEffect.new()], on_enter),
		AbilityV2.new("fuchsia_adc_attack", TriggerV2.Type.ATTACK_OVERRIDE, [BodyPlusShadowAttackEffect.new()], passive),
		AbilityV2.new("fuchsia_adc_mirror", TriggerV2.Type.ON_AFTER_MOVEMENT, [MirrorMoveEffect.new()], trig),
	]


# APF：佈署生鏡像；佈署時與每回合開始使站在鏡像格上的敵人麻痺（光環）；攻擊附帶麻痺。
static func apf() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_ap_deploy", TriggerV2.Type.ON_DEPLOY,
			[DeploySpawnShadowEffect.new(), AuraNumbEffect.new()], on_enter),
		AbilityV2.new("fuchsia_ap_aura", TriggerV2.Type.ON_REFRESH, [AuraNumbEffect.new()], trig),
		AbilityV2.new("fuchsia_ap_numb", TriggerV2.Type.ON_ABILITY_HIT, [NumbTargetEffect.new()], trig),
		AbilityV2.new("fuchsia_ap_mirror", TriggerV2.Type.ON_AFTER_MOVEMENT, [MirrorMoveEffect.new()], trig),
	]


# TANKF：佈署生鏡像；鏡像實體佔格（阻擋走位）；本體死亡時鏡像格釋放。
static func tankf() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_tank_deploy", TriggerV2.Type.ON_DEPLOY, [DeploySpawnShadowEffect.new()], on_enter),
		AbilityV2.new("fuchsia_tank_occupy", TriggerV2.Type.ON_UPDATE, [OccupyShadowCellsEffect.new()], passive),
		AbilityV2.new("fuchsia_tank_die", TriggerV2.Type.ON_DIE, [ReleaseShadowCellsEffect.new()], passive),
		AbilityV2.new("fuchsia_tank_mirror", TriggerV2.Type.ON_AFTER_MOVEMENT, [MirrorMoveEffect.new()], trig),
	]


# HFF：佈署生鏡像；攻擊時本體與鏡像都發動（九宮格）。
static func hff() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_hf_deploy", TriggerV2.Type.ON_DEPLOY, [DeploySpawnShadowEffect.new()], on_enter),
		AbilityV2.new("fuchsia_hf_attack", TriggerV2.Type.ATTACK_OVERRIDE, [BodyPlusShadowAttackEffect.new()], passive),
		AbilityV2.new("fuchsia_hf_mirror", TriggerV2.Type.ON_AFTER_MOVEMENT, [MirrorMoveEffect.new()], trig),
	]


# LFF：佈署生鏡像（鏡像攻擊模式 = nearest）；本體先打、鏡像再打；被兩者都命中的目標再吃一次本體 ATK。
static func lff() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_lf_deploy", TriggerV2.Type.ON_DEPLOY, [DeploySpawnShadowEffect.new("nearest")], on_enter),
		AbilityV2.new("fuchsia_lf_attack", TriggerV2.Type.ATTACK_OVERRIDE, [LfBodyShadowDoubleHitEffect.new()], passive),
		AbilityV2.new("fuchsia_lf_mirror", TriggerV2.Type.ON_AFTER_MOVEMENT, [MirrorMoveEffect.new()], trig),
	]


# ASSF：斬殺後在受害者位置生成不可移動鏡像（越殺越多）；攻擊時本體與所有鏡像都發動。
static func assf() -> Array:
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_ass_attack", TriggerV2.Type.ATTACK_OVERRIDE, [AssBodyShadowAttackEffect.new()], passive),
		AbilityV2.new("fuchsia_ass_kill", TriggerV2.Type.ON_KILLED, [AssSpawnShadowEffect.new()], trig),
	]


# APTF：佈署生鏡像；全場傷害攔截（priority 20）——我方棋子站在鏡像格上受傷時傷害減半（進位），
# APTF 獲得減免量（捨去）護盾。
static func aptf() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	var modifier: Array[int] = [AbilityComponentV2.Tag.MODIFIER]
	var trig: Array[int] = [AbilityComponentV2.Tag.TRIGGERED]
	return [
		AbilityV2.new("fuchsia_apt_deploy", TriggerV2.Type.ON_DEPLOY, [DeploySpawnShadowEffect.new()], on_enter),
		AbilityV2.new("fuchsia_apt_field", TriggerV2.Type.MOD_FIELD_INTERCEPT, [AptFieldEffect.new()], modifier, 20),
		AbilityV2.new("fuchsia_apt_mirror", TriggerV2.Type.ON_AFTER_MOVEMENT, [MirrorMoveEffect.new()], trig),
	]


# SPF：佈署時，最遠的我方紫紅卡（非 SPF）在 SPF 的對稱位生成不可移動鏡像。
static func spf() -> Array:
	var on_enter: Array[int] = [AbilityComponentV2.Tag.ON_ENTER]
	return [
		AbilityV2.new("fuchsia_sp_deploy", TriggerV2.Type.ON_DEPLOY, [SpGiveShadowEffect.new()], on_enter),
	]


# SHADOW（衍生物）：承傷時若 linker 是 APTF → linker 獲 value//2 護盾（Python Shadow.damage_block）。
static func shadow() -> Array:
	var passive: Array[int] = [AbilityComponentV2.Tag.PASSIVE]
	return [
		AbilityV2.new("fuchsia_shadow_block", TriggerV2.Type.BLOCK_DAMAGE, [ShadowBlockEffect.new()], passive),
	]


# --- 共用工具 ---

# 中心對稱位 (width-1-x, height-1-y)（見 board_config.get_symmetric_pos，4x4）。
static func _sym(_core: GameCore, x: int, y: int) -> Vector2i:
	return Vector2i(GameConfig.BOARD_SIZE - 1 - x, GameConfig.BOARD_SIZE - 1 - y)


# 生成一個鏡像並掛到 linker.shadows。
static func _spawn_shadow(linker: PieceState, owner: String, x: int, y: int, movable_flag: bool) -> PieceState:
	var s := PieceState.make_shadow(linker, owner, x, y, movable_flag)
	linker.shadows.append(s)
	return s


# 鏡像代打（Python Shadow.attack）：從鏡像位置 detection 目標池，以本體為 attacker 發動。
# LFF 鏡像只打對手棋子（不含中立）；其餘含中立。回傳 launch_attack 結果。
static func _shadow_attack(core: GameCore, shadow_piece: PieceState) -> bool:
	var linker: PieceState = shadow_piece.get_linker()
	if linker == null:
		return false
	var candidates: Array
	if linker.card_id == "LFF":
		candidates = core.get_player(core.opponent_name(linker.owner)).on_board.duplicate()
	else:
		candidates = core.get_enemies_of(linker.owner)
	var targets: Array = CombatV2.detection(core, shadow_piece, shadow_piece.attack_types, candidates)
	if targets.is_empty():
		return false
	return CombatV2.launch_attack(core, linker, shadow_piece.attack_types, targets)


# --- 佈署 / 移動 效果 ---

# 佈署生鏡像於本體對稱位（可移動）。shadow_type 非空時先設定本體 shadow_attack_types（LFF="nearest"）。
class DeploySpawnShadowEffect extends AbilityEffectV2:
	var shadow_type: String = ""
	func _init(st: String = "") -> void:
		shadow_type = st
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		if shadow_type != "":
			src.shadow_attack_types = shadow_type
		var pos: Vector2i = FuchsiaCardsV2._sym(ctx.core, src.board_x, src.board_y)
		FuchsiaCardsV2._spawn_shadow(src, src.owner, pos.x, pos.y, true)
		return null


# 本體移動後：所有可移動鏡像同步鏡射到本體新位置的對稱位（Python FuchsiaCard.after_movement）。
class MirrorMoveEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var pos: Vector2i = FuchsiaCardsV2._sym(ctx.core, src.board_x, src.board_y)
		for shadow_piece: PieceState in src.shadows:
			if shadow_piece.movable:
				shadow_piece.board_x = pos.x
				shadow_piece.board_y = pos.y
		return null


# --- 攻擊覆寫（ADCF / HFF）---

# 本體 launch_attack 後，所有鏡像亦代打；本體無目標時只有鏡像命中也算成功（Python Adc.attack/Hf.attack）。
class BodyPlusShadowAttackEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		if CombatV2.launch_attack(core, src, src.attack_types):
			for shadow_piece: PieceState in src.shadows:
				FuchsiaCardsV2._shadow_attack(core, shadow_piece)
			src.hit_cards.clear()
			return true
		if not src.is_numb():
			var count: int = 0
			for shadow_piece: PieceState in src.shadows:
				if FuchsiaCardsV2._shadow_attack(core, shadow_piece):
					count += 1
			src.hit_cards.clear()
			if count > 0:
				return true
		return false


# --- 攻擊覆寫（LFF）---

# 本體先打（記 body_hits），鏡像（nearest）再打；被本體與鏡像都命中且仍存活的目標，再吃一次本體 ATK。
class LfBodyShadowDoubleHitEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		if not CombatV2.launch_attack(core, src, src.attack_types):
			return false
		var body_hits: Array = src.hit_cards.duplicate()
		for shadow_piece: PieceState in src.shadows:
			FuchsiaCardsV2._shadow_attack(core, shadow_piece)
		var body_iids: Dictionary = {}
		for c: PieceState in body_hits:
			body_iids[c.instance_id] = true
		for i: int in range(body_hits.size(), src.hit_cards.size()):
			var target: PieceState = src.hit_cards[i]
			if body_iids.has(target.instance_id) and target.health > 0:
				var hurt_delay: float = core._attack_anim_cursor + GameConfig.ANIM_LUNGE_STEP * GameConfig.HIT_DELAY_RATIO
				CombatV2.damage_calculate(core, target, src.damage, src, true, hurt_delay)
				core._attack_anim_cursor += GameConfig.ANIM_LUNGE_STEP
		src.hit_cards.clear()
		return true


# --- 攻擊覆寫（ASSF）---

# 攻擊前先快照鏡像清單（本次斬殺新生的鏡像本回合不代打，Python temp_shadow_list）。
class AssBodyShadowAttackEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var temp: Array = src.shadows.duplicate()
		if CombatV2.launch_attack(core, src, src.attack_types):
			for shadow_piece: PieceState in temp:
				FuchsiaCardsV2._shadow_attack(core, shadow_piece)
			src.hit_cards.clear()
			return true
		if not src.is_numb():
			var count: int = 0
			for shadow_piece: PieceState in temp:
				if FuchsiaCardsV2._shadow_attack(core, shadow_piece):
					count += 1
			src.hit_cards.clear()
			if count > 0:
				return true
		return false


# ASSF 斬殺：在受害者位置生成不可移動鏡像（Python Ass.killed）。
class AssSpawnShadowEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var victim: PieceState = ctx.target
		if victim != null:
			FuchsiaCardsV2._spawn_shadow(src, src.owner, victim.board_x, victim.board_y, false)
		return null


# --- APF 光環 / 麻痺 ---

# 站在任一鏡像格上的敵方（含中立）麻痺（Python Ap.deploy/on_refresh）。
class AuraNumbEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		for shadow_piece: PieceState in src.shadows:
			for enemy: PieceState in core.get_enemies_of(src.owner):
				if enemy.health > 0 and enemy.board_x == shadow_piece.board_x and enemy.board_y == shadow_piece.board_y:
					enemy.set_numb(true)
		return null


# APF 攻擊附帶：目標麻痺（Python Ap.ability）。
class NumbTargetEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		if ctx.target != null:
			ctx.target.set_numb(true)
		return true


# --- TANKF 佔格 ---

# 每步將鏡像格標記為佔用（阻擋走位，Python Tank.update）。
class OccupyShadowCellsEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		for shadow_piece: PieceState in src.shadows:
			ctx.core.board.set_occupied(Vector2i(shadow_piece.board_x, shadow_piece.board_y), true)
		return null


# 本體死亡：若鏡像格上無其他存活棋子則釋放（Python Shadow.die）。
class ReleaseShadowCellsEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		for shadow_piece: PieceState in src.shadows:
			var occupied_by_piece: bool = false
			for c: PieceState in core.get_all_pieces():
				if c.health > 0 and c.board_x == shadow_piece.board_x and c.board_y == shadow_piece.board_y:
					occupied_by_piece = true
					break
			if not occupied_by_piece:
				core.board.set_occupied(Vector2i(shadow_piece.board_x, shadow_piece.board_y), false)
		return null


# --- APTF 場地攔截 ---

# 我方棋子站在鏡像格上受傷時，傷害減半（進位）；APTF 獲得減免量（捨去）護盾（Python Apt.on_field_effect_trigger）。
class AptFieldEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var victim: PieceState = ctx.target
		if src.health <= 0 or victim == null:
			return null
		if victim.owner != src.owner or victim == src:
			return null
		for shadow_piece: PieceState in src.shadows:
			if shadow_piece.board_x == victim.board_x and shadow_piece.board_y == victim.board_y:
				src.armor += int(floor(ctx.value * 0.5))
				return {"priority": 20, "value": int(ceil(ctx.value * 0.5)), "feedback": null}
		return null


# --- SPF ---

# 最遠我方紫紅卡（非 SPF）在 SPF 對稱位生成不可移動鏡像（Python Sp.deploy）。
class SpGiveShadowEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var src: PieceState = ctx.source
		var core: GameCore = ctx.core
		var targets: Array = core.get_player(src.owner).on_board.filter(func(c: PieceState) -> bool:
			return c.health > 0 and c.color_code == "F" and c.card_id != "SPF")
		if targets.is_empty():
			return null
		var pos: Vector2i = FuchsiaCardsV2._sym(core, src.board_x, src.board_y)
		for ally: PieceState in CombatV2.detection(core, src, "farthest", targets):
			FuchsiaCardsV2._spawn_shadow(ally, src.owner, pos.x, pos.y, false)
		return null


# --- SHADOW ---

# 鏡像承傷：linker 是 APTF 時 linker 獲 value//2 護盾；不真正格擋（回傳 false）（Python Shadow.damage_block）。
class ShadowBlockEffect extends AbilityEffectV2:
	func execute(ctx: AbilityContextV2) -> Variant:
		var shadow_piece: PieceState = ctx.source
		var linker: PieceState = shadow_piece.get_linker()
		if linker != null and linker.card_id == "APTF":
			linker.armor += ctx.value / 2
		return false
