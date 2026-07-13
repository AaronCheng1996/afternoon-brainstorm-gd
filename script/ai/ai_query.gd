# P10-1 CPU AI 幾何查詢層（翻譯自 Python `campaign/ai_query.py`，見 docs/rebuild/03 §2）。
# 全部為純函式（static），吃 GameCore 狀態、不碰 Node、不呼叫 rng——攻擊模式查詢刻意
# 「取同距全部候選」而非 detection()（不消耗 rng，見 03 §2 與 09 §11 決定性慣例）。
# 常數 ASS_THREAT_DAMAGE 由 campaign_setting.json（threat_model）讀取，不寫死（見 03 §8）。
class_name AIQuery
extends RefCounted


# --- 基礎幾何 ---

# 棋盤所有未佔用且合法的空格（Array[Vector2i]）。
static func empty_positions(core: GameCore) -> Array:
	var out: Array = []
	for x in BoardState.SIZE:
		for y in BoardState.SIZE:
			var p := Vector2i(x, y)
			if not core.board.occupy[p]:
				out.append(p)
	return out


static func is_corner(x: int, y: int) -> bool:
	var w := BoardState.SIZE
	var h := BoardState.SIZE
	return (x == 0 or x == w - 1) and (y == 0 or y == h - 1)


static func is_edge(x: int, y: int) -> bool:
	var w := BoardState.SIZE
	var h := BoardState.SIZE
	var on_border := (x == 0 or x == w - 1) or (y == 0 or y == h - 1)
	return on_border and not is_corner(x, y)


# 位置安全值：角落 3.0、邊 2.0、中央 1.0（見 03 §2）。
static func position_safety(x: int, y: int) -> float:
	if is_corner(x, y):
		return 3.0
	if is_edge(x, y):
		return 2.0
	return 1.0


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# --- 棋子集合 ---

# 對手場上棋子（health>0，不含 neutral）。
static func enemy_cards(core: GameCore, owner: String) -> Array:
	var out: Array = []
	for c: PieceState in core.get_player(core.opponent_name(owner)).on_board:
		if c.health > 0:
			out.append(c)
	return out


# 我方場上棋子（health>0）。
static func friendly_cards(core: GameCore, owner: String) -> Array:
	var out: Array = []
	for c: PieceState in core.get_player(owner).on_board:
		if c.health > 0:
			out.append(c)
	return out


# --- 攻擊模式查詢 ---

# 假想從 (x,y) 用 attack_types 能打到哪些敵方目標（對手 + neutral，health>0）。
# nearest/farthest 取「並列全部」而非隨機一個（評分用寬鬆版，不呼叫 detection）。依 instance_id 去重。
static func attack_targets_from_pos(core: GameCore, owner: String, x: int, y: int, attack_types: String) -> Array:
	var candidates: Array = []
	for c: PieceState in core.get_enemies_of(owner):
		if c.health > 0:
			candidates.append(c)
	if candidates.is_empty() or attack_types == "":
		return []

	var hits: Array = []
	var here := Vector2i(x, y)
	for attack_type in attack_types.split(" ", false):
		match attack_type:
			"small_cross":
				for c: PieceState in candidates:
					if absi(c.board_x - x) + absi(c.board_y - y) == 1:
						hits.append(c)
			"large_cross":
				for c: PieceState in candidates:
					var same_row: bool = c.board_y == y
					var same_col: bool = c.board_x == x
					var same_pos: bool = c.board_x == x and c.board_y == y
					if (same_row or same_col) and not same_pos:
						hits.append(c)
			"small_x":
				for c: PieceState in candidates:
					if absi(c.board_x - x) == 1 and absi(c.board_y - y) == 1:
						hits.append(c)
			"nearest":
				var nearest := _extreme_distance(candidates, here, false)
				if nearest >= 0:
					for c: PieceState in candidates:
						if manhattan(c.pos(), here) == nearest:
							hits.append(c)
			"farthest":
				var farthest := _extreme_distance(candidates, here, true)
				if farthest >= 0:
					for c: PieceState in candidates:
						if manhattan(c.pos(), here) == farthest:
							hits.append(c)

	var seen: Dictionary = {}
	var unique: Array = []
	for c: PieceState in hits:
		if not seen.has(c.instance_id):
			seen[c.instance_id] = true
			unique.append(c)
	return unique


# 候選集合對 here 的最小（reverse=false）或最大（reverse=true）曼哈頓距；空集合回 -1。
static func _extreme_distance(candidates: Array, here: Vector2i, reverse: bool) -> int:
	var best: int = -1
	for c: PieceState in candidates:
		var d: int = manhattan(c.pos(), here)
		if best < 0:
			best = d
		elif reverse:
			best = maxi(best, d)
		else:
			best = mini(best, d)
	return best


# 棋子當前位置的攻擊目標。
static func attack_targets_at(core: GameCore, attacker: PieceState) -> Array:
	return attack_targets_from_pos(core, attacker.owner, attacker.board_x, attacker.board_y, attacker.attack_types)


# 到最近敵人的曼哈頓距（無敵人回 w+h）。
static func nearest_enemy_distance(core: GameCore, owner: String, x: int, y: int) -> int:
	var enemies := enemy_cards(core, owner)
	if enemies.is_empty():
		return BoardState.SIZE + BoardState.SIZE
	var here := Vector2i(x, y)
	var best: int = -1
	for e: PieceState in enemies:
		var d: int = manhattan(here, e.pos())
		best = d if best < 0 else mini(best, d)
	return best


# 該攻擊模式在 (x,y) 覆蓋的格數（nearest/farthest 不轉換為格覆蓋 → 0）。
static func attack_coverage_cells(_core: GameCore, x: int, y: int, attack_types: String) -> int:
	if attack_types == "":
		return 0
	var w := BoardState.SIZE
	var h := BoardState.SIZE
	var cells: Dictionary = {}
	for at in attack_types.split(" ", false):
		match at:
			"small_cross":
				for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var n := Vector2i(x + d.x, y + d.y)
					if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h:
						cells[n] = true
			"small_x":
				for d: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
					var n := Vector2i(x + d.x, y + d.y)
					if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h:
						cells[n] = true
			"large_cross":
				for i in w:
					if i != x:
						cells[Vector2i(i, y)] = true
				for j in h:
					if j != y:
						cells[Vector2i(x, j)] = true
	return cells.size()


# --- 手牌與移動 ---

# 是否為「可佈署的單位牌」（排除魔法/臨時卡）。
static func is_playable_unit_card(card_name: String) -> bool:
	return not (card_name in ["HEAL", "MOVE", "MOVEO", "CUBES"])


# 我方場上「移動中」的棋子（health>0）。
static func units_with_pending_move(core: GameCore, owner: String) -> Array:
	var out: Array = []
	for c: PieceState in core.get_player(owner).on_board:
		if c.is_moving() and c.health > 0:
			out.append(c)
	return out


# 棋子的 8 鄰空格（合法且未佔用）。
static func move_destinations_for(core: GameCore, card: PieceState) -> Array:
	var cells: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := Vector2i(card.board_x + dx, card.board_y + dy)
			if not core.board.in_bounds(n):
				continue
			if core.board.occupy[n]:
				continue
			cells.append(n)
	return cells


# --- 威脅評估 ---

# 某敵方單位從其現位能否打到 (tx,ty)（target_owner＝該格所屬方；nearest/farthest 用寬鬆判定）。
static func attacker_would_hit_position(core: GameCore, attacker: PieceState, tx: int, ty: int, target_owner: String) -> bool:
	var ax := attacker.board_x
	var ay := attacker.board_y
	if attacker.attack_types == "":
		return false
	for at in attacker.attack_types.split(" ", false):
		match at:
			"small_cross":
				if absi(ax - tx) + absi(ay - ty) == 1:
					return true
			"large_cross":
				if (ax == tx or ay == ty) and not (ax == tx and ay == ty):
					return true
			"small_x":
				if absi(ax - tx) == 1 and absi(ay - ty) == 1:
					return true
			"nearest":
				var friendlies := friendly_cards(core, target_owner)
				var d_new := manhattan(Vector2i(ax, ay), Vector2i(tx, ty))
				if _hits_by_extreme(friendlies, Vector2i(ax, ay), d_new, false):
					return true
			"farthest":
				var friendlies2 := friendly_cards(core, target_owner)
				var d_new2 := manhattan(Vector2i(ax, ay), Vector2i(tx, ty))
				if _hits_by_extreme(friendlies2, Vector2i(ax, ay), d_new2, true):
					return true
	return false


# nearest：假想目標距離 ≤ 我方現有最小距離 → 會被打到；farthest：≥ 最大距離。空集合恆真。
static func _hits_by_extreme(friendlies: Array, from_pos: Vector2i, d_new: int, farthest: bool) -> bool:
	if friendlies.is_empty():
		return true
	var extreme: int = -1
	for f: PieceState in friendlies:
		var d: int = manhattan(from_pos, f.pos())
		if extreme < 0:
			extreme = d
		elif farthest:
			extreme = maxi(extreme, d)
		else:
			extreme = mini(extreme, d)
	return d_new >= extreme if farthest else d_new <= extreme


# 對手（非麻痺）所有能打到 (x,y) 的單位傷害由大到小取前 max(min_attacks, 對手攻擊次數) 個加總。
static func incoming_damage_at_position(core: GameCore, owner: String, x: int, y: int, min_attacks: int = 0) -> int:
	var opp := core.opponent_name(owner)
	var available := maxi(min_attacks, int(core.number_of_attacks.get(opp, 0)))
	if available <= 0:
		return 0

	var threats: Array = []
	for enemy: PieceState in enemy_cards(core, owner):
		if enemy.is_numb():
			continue
		if attacker_would_hit_position(core, enemy, x, y, owner):
			threats.append(enemy.damage + enemy.extra_damage)

	threats.sort()
	threats.reverse()
	var total: int = 0
	for i in mini(available, threats.size()):
		total += int(threats[i])
	return total


# 至少假設對手有 1 次攻擊的預估承傷。
static func projected_incoming_damage(core: GameCore, owner: String, x: int, y: int) -> int:
	return incoming_damage_at_position(core, owner, x, y, 1)


# 若 ASS_THREAT_DAMAGE − armor ≥ health（脆皮），回傳能斜角威脅到它的空格清單（給防禦性佈署用）。
static func cells_threatening_card(core: GameCore, card: PieceState) -> Array:
	var ass_threat: int = int(core.balance.ai("threat_model/ass_threat_damage"))
	var effective: int = ass_threat - maxi(0, card.armor)
	if card.health > effective:
		return []
	var spots: Array = []
	for p: Vector2i in empty_positions(core):
		if absi(card.board_x - p.x) == 1 and absi(card.board_y - p.y) == 1:
			spots.append(p)
	return spots
