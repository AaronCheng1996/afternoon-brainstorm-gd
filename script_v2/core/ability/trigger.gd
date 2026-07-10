# P1-3 能力觸發點（見 docs/rebuild/04 §5.1）。
# 必須完整覆蓋 Python 的 hook 集（cards/base.py 的各多型方法）。
# 命名加 V2 以與舊碼 script/events/game_trigger.gd 的 GameTrigger 區隔（Phase 6 收編再統一）。
class_name TriggerV2
extends RefCounted

enum Type {
	ON_DEPLOY,                  # deploy()：棋子放置後
	ON_REFRESH,                 # on_refresh()：擁有者回合開始
	ON_SETTLE,                  # on_settle()：回合結束計分（MOD 類，回傳分數）
	ON_UPDATE,                  # update()：每 logic_step
	ON_ABILITY_HIT,             # ability(target)：傷害管線步驟 3「攻擊附帶」（回傳 bool）
	MOD_DAMAGE_BONUS,           # damage_bonus()：管線步驟 4（MOD，回傳新值）
	MOD_DAMAGE_REDUCE,          # damage_reduce()：管線步驟 5（MOD，回傳新值）
	MOD_FIELD_INTERCEPT,        # on_field_effect_trigger()：管線步驟 6（全場，含 priority，回傳 Dictionary）
	BLOCK_DAMAGE,               # damage_block()：管線步驟 2（回傳 bool，True 整段取消）
	ON_AFTER_DAMAGE,            # after_damage_calculated()：管線步驟 9
	ON_BEEN_ATTACKED,           # been_attacked()：管線步驟 8
	ON_KILLED,                  # killed(victim)：我殺了人
	ON_BEEN_KILLED,             # been_killed(attacker)：我被殺
	ON_DIE,                     # die()：回收時
	CAN_BE_KILLED,              # can_be_killed()：死亡判定（回傳 bool，True＝保護不死）
	ON_MOVE_BROADCAST,          # move_broadcast(mover)：任何棋子移動後（全場廣播）
	ON_AFTER_MOVEMENT,          # after_movement()：自己移動後
	CUSTOM_MOVE,                # custom_move()：攔截移動（保留，回傳 bool）
	ON_AFTER_ATTACK_BROADCAST,  # after_attack_broadcast()：每次成功結算後全場廣播
	ON_TOKEN_GAINED,            # Blue after_token()：Token 引擎轉發
	ON_TOKEN_DRAW,              # Blue token_draw()：Token 引擎轉發
	ATTACK_OVERRIDE,            # attack() 覆寫：整個攻擊流程客製
}
