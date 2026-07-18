# P12-4 公開快照序列化（見 docs/rebuild/10 §4、決策 D19）。
# GameCore → 單一「公開快照」Dictionary，全房間共用一份（D19：手牌公開 → 無需逐客端遮蔽）。
# 內容＝盤面棋子全（公開）欄位、雙方手牌明細、資源/分數/回合/各類次數、棄牌堆、統計 export；
# 牌庫只給張數。
#
# **鐵則（D19，見 10 §1/§4）**：快照永不含 seed、不含牌庫抽序（draw_pile）、不含 revealed_deck
# ——這些是唯一的隱藏資訊，只存在權威伺服器端。此模組刻意不讀取那些欄位；快照測試會斷言
# 序列化結果不含這些鍵。
#
# 純資料、JSON 可序列化：放在 script/net/ 但零 Node 依賴（僅唯讀 core 狀態）；battle 端
# 以此重建盤面（把 `_rebuild_board` 的資料源一般化為「core 或快照」）。
class_name GameSnapshot
extends RefCounted


# GameCore → 公開快照 Dictionary（關鍵點下發/校正用；見 10 §4）。
static func encode(core: GameCore) -> Dictionary:
	return {
		"turn_number": core.turn_number,
		"current_player": core.current_player(),
		"score": core.score,
		"over": core.is_over(),
		"winner": core.winner_name(),
		"pieces": _encode_all_pieces(core),
		# D19：雙方手牌明細（公開）。
		"hands": {
			"player1": _str_array(core.player1.hand),
			"player2": _str_array(core.player2.hand),
		},
		"discard": {
			"player1": _str_array(core.player1.discard_pile),
			"player2": _str_array(core.player2.discard_pile),
		},
		# 牌庫只給張數（不洩漏抽序 → D19）。
		"deck_counts": {
			"player1": core.player1.draw_pile.size(),
			"player2": core.player2.draw_pile.size(),
		},
		"resources": {
			"luck": core.players_luck.duplicate(),
			"token": core.players_token.duplicate(),
			"totem": core.players_totem.duplicate(),
			"coin": core.players_coin.duplicate(),
		},
		"counts": {
			"attacks": core.number_of_attacks.duplicate(),
			"movings": core.number_of_movings.duplicate(),
			"cubes": core.number_of_cubes.duplicate(),
			"heals": core.number_of_heals.duplicate(),
		},
		"stats": core.stats.export_for_charts(),
		# P12-15：每回合分數序列（公開；供終局統計折線）。純 int 陣列，JSON round-trip 穩定；
		# 不含任何隱藏資訊（分數本就公開）。
		"score_history": _int_array(core.stats.score_history),
	}


# 單一棋子的公開欄位序列化（盤面重建與逐欄位驗證共用）。
# 刻意排除：hit_cards / _linker_ref / abilities（含物件參考、不可 JSON 化、屬管線內部）、
# pending_death（僅傷害管線瞬時狀態，快照取於休止點）。
static func encode_piece(p: PieceState) -> Dictionary:
	return {
		"instance_id": p.instance_id,
		"card_id": p.card_id,
		"job": p.job,
		"color_code": p.color_code,
		"owner": p.owner,
		"board_x": p.board_x,
		"board_y": p.board_y,
		"health": p.health,
		"max_health": p.max_health,
		"damage": p.damage,
		"original_damage": p.original_damage,
		"armor": p.armor,
		"extra_damage": p.extra_damage,
		"attack_uses": p.attack_uses,
		"attack_types": p.attack_types,
		"movable": p.movable,
		"shadow_attack_types": p.shadow_attack_types,
		"upgrade": p.upgrade,
		"statuses": _encode_statuses(p.statuses),
		"counters": p.counters.duplicate(true),
		"shadows": _encode_shadows(p.shadows),
	}


static func _encode_all_pieces(core: GameCore) -> Array:
	var out: Array = []
	for p: PieceState in core.get_all_pieces():
		out.append(encode_piece(p))
	return out


# statuses 正規化為純 JSON 值（{id: {value:bool, duration:int}}）。
static func _encode_statuses(statuses: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in statuses:
		var s: Dictionary = statuses[id]
		out[id] = {"value": bool(s.get("value", false)), "duration": int(s.get("duration", -1))}
	return out


# Fuchsia 鏡像（僅顯示用）：位置＋本體職業（供視圖選形狀）；不含物件參考。
static func _encode_shadows(shadows: Array) -> Array:
	var out: Array = []
	for sh: PieceState in shadows:
		var linker: PieceState = sh.get_linker()
		out.append({
			"owner": sh.owner,
			"board_x": sh.board_x,
			"board_y": sh.board_y,
			"linker_job": linker.job if linker != null else "",
		})
	return out


# 把（可能為 typed）字串陣列複製為一般 Array，JSON 序列化穩定。
static func _str_array(a: Array) -> Array:
	var out: Array = []
	out.assign(a)
	return out


# 把（可能為 typed）整數陣列複製為一般 Array（score_history 用）。
static func _int_array(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(int(x))
	return out
