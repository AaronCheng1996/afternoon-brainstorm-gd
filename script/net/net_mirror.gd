# P12-12 連線對戰「顯示鏡像」（見 docs/rebuild/10_連線版本.md §4/§11.2-4，決策 D18/D19）。
# 連線客端沒有權威 GameCore（seed 只在 server，D19）。本模組把一份公開快照（GameSnapshot）
# 還原成一顆「唯讀顯示用 GameCore」——只為讓 battle 場景的既有讀取碼（HUD／記分板／攻擊範圍
# 預覽／手牌列）原樣重用（§11.2-4「快照 → display 鏡像盤面，重用既有讀取碼」）。
#
# **鐵則（§11.2-4）**：鏡像**嚴禁被 dispatch**——唯一寫入者是快照重建。net 模式的 `_do` 只送網路，
# 絕不對鏡像呼叫 dispatch/logic_step。鏡像的隱藏欄位（seed/牌庫抽序）本來就不在快照裡：
# rng 留 null、draw_pile 只還原「張數」（以佔位空字串填滿，僅供 `.size()` 讀取）。
#
# 純資料（RefCounted、零 Node）；還原用的棋子經 PieceState.make() 取得能力元件（顯示無害、
# 永不觸發，因為不 dispatch），再以快照公開欄位覆寫。分數/回合/資源等 HUD 讀取面皆忠實。
#
# **統計（core.stats）刻意不還原**：鏡像的 `stats` 是一顆空的 Statistics。
# 注意快照**自 P12-15 起有帶 `score_history`**（供終局折線）——原本此處註記「快照未帶」已過時
# （P15-3 更正）。終局折線並不經鏡像：battle 的 `_finish_net_game` 直接從快照取 score_history
# 交給 end_game。因此鏡像上「記分板趨勢留空」是現況而非必然；若日後要讓連線對戰的記分板
# 也顯示趨勢，把 `snap["score_history"]` 灌回 `core.stats.score_history` 即可（屬行為變更，
# 需另開任務，不在 review 範圍）。
class_name NetMirror
extends RefCounted


# 公開快照 Dictionary → 顯示用 GameCore（唯讀）。db＝BalanceDB 實例（客端有 autoload Balance）。
static func build(snap: Dictionary, db: Object) -> GameCore:
	var core := GameCore.new()
	core.balance = db
	core.config = GameConfig.new()
	core.board = BoardState.new()
	core.stats = Statistics.new()
	core.rng = null   # 顯示鏡像不隨機、不 dispatch（D19：seed 不在客端）
	core.player1 = PlayerState.new("player1", [])
	core.player2 = PlayerState.new("player2", [])
	core.neutral_pieces = []

	# turn_number 決定 current_player()（回合偶＝player1）；快照的 current_player 由此重現。
	core.turn_number = int(snap.get("turn_number", 0))
	core.score = int(snap.get("score", 0))

	_apply_map(core.players_luck, snap.get("resources", {}).get("luck", {}))
	_apply_map(core.players_token, snap.get("resources", {}).get("token", {}))
	_apply_map(core.players_totem, snap.get("resources", {}).get("totem", {}))
	_apply_map(core.players_coin, snap.get("resources", {}).get("coin", {}))
	var counts: Dictionary = snap.get("counts", {})
	_apply_map(core.number_of_attacks, counts.get("attacks", {}))
	_apply_map(core.number_of_movings, counts.get("movings", {}))
	_apply_map(core.number_of_cubes, counts.get("cubes", {}))
	_apply_map(core.number_of_heals, counts.get("heals", {}))

	# 手牌（公開，D19）／棄牌堆（明細）／牌庫（只有張數 → 佔位填滿，僅供 size 讀取）。
	var hands: Dictionary = snap.get("hands", {})
	var discard: Dictionary = snap.get("discard", {})
	var deck_counts: Dictionary = snap.get("deck_counts", {})
	_fill_player(core.player1, hands.get("player1", []), discard.get("player1", []),
		int(deck_counts.get("player1", 0)))
	_fill_player(core.player2, hands.get("player2", []), discard.get("player2", []),
		int(deck_counts.get("player2", 0)))

	# 盤面棋子（含 Fuchsia 鏡像）。owner 決定歸入哪一方 on_board 或 neutral。
	for pd: Dictionary in snap.get("pieces", []):
		var p := _decode_piece(pd, db)
		match p.owner:
			"player1": core.player1.on_board.append(p)
			"player2": core.player2.on_board.append(p)
			_: core.neutral_pieces.append(p)
		core.board.set_occupied(p.pos(), true)

	if bool(snap.get("over", false)):
		core.mark_over(String(snap.get("winner", "")))
	return core


# 把 JSON 還原的整數映射套進目標字典（保留 neutral 等既有鍵）。
static func _apply_map(target: Dictionary, src: Variant) -> void:
	if typeof(src) != TYPE_DICTIONARY:
		return
	for k in src:
		target[k] = int(src[k])


# 填手牌／棄牌／牌庫（牌庫只還原張數：以空字串佔位，net 模式永不抽牌，只讀 size）。
static func _fill_player(p: PlayerState, hand: Variant, discard: Variant, deck_count: int) -> void:
	p.hand.assign(_str_array(hand))
	p.discard_pile.assign(_str_array(discard))
	var pile: Array[String] = []
	for _i in maxi(0, deck_count):
		pile.append("")
	p.draw_pile = pile


# 單一棋子公開欄位 → PieceState（顯示用）。經 make() 取形狀/能力（永不觸發），再覆寫快照欄位。
static func _decode_piece(pd: Dictionary, db: Object) -> PieceState:
	var card_id := String(pd.get("card_id", ""))
	var owner := String(pd.get("owner", "neutral"))
	var p := PieceState.make(card_id, owner, int(pd.get("board_x", 0)), int(pd.get("board_y", 0)),
		db, bool(pd.get("upgrade", false)))
	p.health = int(pd.get("health", p.health))
	p.max_health = int(pd.get("max_health", p.max_health))
	p.damage = int(pd.get("damage", p.damage))
	p.original_damage = int(pd.get("original_damage", p.original_damage))
	p.armor = int(pd.get("armor", p.armor))
	p.extra_damage = int(pd.get("extra_damage", p.extra_damage))
	p.attack_uses = int(pd.get("attack_uses", p.attack_uses))
	p.attack_types = String(pd.get("attack_types", p.attack_types))
	p.movable = bool(pd.get("movable", p.movable))
	p.shadow_attack_types = String(pd.get("shadow_attack_types", p.shadow_attack_types))
	p.statuses = _decode_statuses(pd.get("statuses", {}))
	p.counters = (pd.get("counters", {}) as Dictionary).duplicate(true)
	# Fuchsia 鏡像（僅顯示；linker=本體，用 WeakRef，不成環）。先覆寫 attack_types 再建鏡像，
	# make_shadow 才讀得到正確的 shadow_attack_types。
	for shd: Dictionary in pd.get("shadows", []):
		var sh := PieceState.make_shadow(p, String(shd.get("owner", owner)),
			int(shd.get("board_x", 0)), int(shd.get("board_y", 0)), false)
		p.shadows.append(sh)
	return p


# 快照 statuses（{id:{value,duration}}）→ PieceState.statuses（value 為真才保留，對齊 set_status 語義）。
static func _decode_statuses(src: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(src) != TYPE_DICTIONARY:
		return out
	for id in src:
		var s: Dictionary = src[id]
		if bool(s.get("value", false)):
			out[id] = {"value": true, "duration": int(s.get("duration", -1))}
	return out


static func _str_array(a: Variant) -> Array:
	var out: Array = []
	if typeof(a) == TYPE_ARRAY:
		for x in a:
			out.append(String(x))
	return out
