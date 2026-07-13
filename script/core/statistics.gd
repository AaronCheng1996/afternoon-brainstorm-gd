# P1-1 對局統計（見 docs/rebuild/01 §11，翻譯自 shared/stat_type.py + core/game_statistics.py）。
# key 格式：全域類用玩家名（player1/player2），卡牌類用 owner_JOBANDCOLOR（如 player1_ASSW）。
class_name Statistics
extends RefCounted

enum StatType {
	CARD_USE,            # card_use_count
	HIT,                 # hit_count
	DAMAGE_DEALT,        # damage_dealt
	DAMAGE_TAKEN,        # damage_taken
	DAMAGE_TAKEN_COUNT,  # damage_taken_count
	SCORED,              # scored
	ABILITY,             # ability_count
	HEALING,             # healing_amount
	HEAL_USE,            # use_heal_count
	MOVE,                # move_count
	MOVE_USE,            # use_move_count
	CUBE_USE,            # cube_used_count
	KILLED,              # killed_count
	DEATH,               # death_count
	TOKEN_USE,           # use_token_count
	ROUNDS_SURVIVED,     # rounds_survived
}

var _stats: Dictionary = {}      # StatType -> {key: int}
var score_history: Array[int] = []


func _init() -> void:
	for st: int in StatType.values():
		_stats[st] = {}


func increment(stat_type: int, key: String, value: int = 1) -> void:
	var bucket: Dictionary = _stats[stat_type]
	bucket[key] = int(bucket.get(key, 0)) + value


func get_stat(stat_type: int, key: String) -> int:
	return int(_stats[stat_type].get(key, 0))


func get_all(stat_type: int) -> Dictionary:
	return _stats[stat_type].duplicate()


func add_score_record(score: int) -> void:
	score_history.append(score)


# 匯出全部統計（終局圖表用）：{stat_value_name: {key: int}}。
func export_for_charts() -> Dictionary:
	var out: Dictionary = {}
	for st: int in StatType.values():
		out[StatType.keys()[st]] = _stats[st].duplicate()
	return out
