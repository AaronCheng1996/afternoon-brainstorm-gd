# P12-4 驗收：公開快照序列化（script/net/game_snapshot.gd，見 docs/rebuild/10 §4、D19）。
# 核心保證：
#   1. GameCore → 公開快照 Dictionary，盤面棋子/手牌/資源/分數/回合/次數/棄牌/統計逐欄位一致；
#   2. **鐵則 D19**：快照不含 seed、不含牌庫抽序（draw_pile）、不含 revealed_deck；牌庫只給張數；
#   3. 快照 JSON round-trip 穩定（正規化後冪等）。
# 純 GameCore（RefCounted，零 Node）→ 無新洩漏（僅 balance_db 一個 Node，末尾釋放）。
extends RefCounted

const P1_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCG", "ADCC"]
const P2_DECK := ["ADCW", "TANKW", "APW", "HFW", "LFW", "ASSW", "HEAL", "MOVE", "CUBES", "ADCB", "ADCDKG", "ADCC"]

var _db: Object = null


func run(t: Object) -> void:
	_db = load("res://script/data/balance_db.gd").new()
	_test_encode_matches_core(t)
	_test_no_hidden_fields(t)
	_test_json_roundtrip_stable(t)
	_db.free()
	_db = null


# 建一顆帶已知中盤狀態的 GameCore（含鏡像與中立方塊）。
func _mk_core() -> GameCore:
	var core := GameCore.new()
	core.setup(P1_DECK.duplicate(), P2_DECK.duplicate(), 4242, _db)
	# 注入確定的中盤：p1 一子（含手動鏡像）、p2 一子、一顆中立方塊、資源/分數/回合。
	var p1a: PieceState = PieceState.make("ADCW", "player1", 1, 1, core.balance)
	p1a.set_numb(false)
	p1a.health = 7
	p1a.armor = 2
	p1a.extra_damage = 1
	core.player1.on_board.append(p1a)
	core.board.set_occupied(Vector2i(1, 1), true)
	var shadow: PieceState = PieceState.make_shadow(p1a, "player1", 3, 3, false)
	p1a.shadows.append(shadow)
	var p2a: PieceState = PieceState.make("TANKW", "player2", 2, 2, core.balance)
	core.player2.on_board.append(p2a)
	core.board.set_occupied(Vector2i(2, 2), true)
	var cube: PieceState = PieceState.make("CUBE", "neutral", 0, 3, core.balance)
	core.neutral_pieces.append(cube)
	core.board.set_occupied(Vector2i(0, 3), true)
	core.players_coin["player1"] = 12
	core.players_token["player2"] = 3
	core.player1.discard_pile.append("APW")
	core.score = -5
	core.turn_number = 4
	core.stats.increment(Statistics.StatType.HIT, p1a.uid(), 2)
	return core


# 1. 逐欄位一致（頂層公開狀態 + 盤面棋子全欄位）。
func _test_encode_matches_core(t: Object) -> void:
	var core := _mk_core()
	var snap: Dictionary = GameSnapshot.encode(core)

	# --- 頂層 ---
	t.eq(int(snap["turn_number"]), 4, "snap：回合數一致")
	t.eq(String(snap["current_player"]), "player1", "snap：當前玩家一致（turn 4→p1）")
	t.eq(int(snap["score"]), -5, "snap：分數一致")
	t.eq(bool(snap["over"]), false, "snap：未結束")
	t.eq(int(snap["resources"]["coin"]["player1"]), 12, "snap：P1 金幣一致")
	t.eq(int(snap["resources"]["token"]["player2"]), 3, "snap：P2 藍球一致")
	t.eq(int(snap["counts"]["attacks"]["player1"]), int(core.number_of_attacks["player1"]),
		"snap：P1 攻擊次數一致")
	# 牌庫只給張數（不洩漏抽序）。
	t.eq(int(snap["deck_counts"]["player1"]), core.player1.draw_pile.size(), "snap：P1 牌庫張數一致")
	t.eq(int(snap["deck_counts"]["player2"]), core.player2.draw_pile.size(), "snap：P2 牌庫張數一致")
	# D19：雙方手牌明細公開且與 core 一致（含內容）。
	t.eq((snap["hands"]["player1"] as Array).size(), core.player1.hand.size(), "snap：P1 手牌數一致")
	t.eq((snap["hands"]["player2"] as Array).size(), core.player2.hand.size(),
		"snap：P2 手牌數一致（D19 對手公開）")
	t.eq(String(snap["hands"]["player1"][0]), String(core.player1.hand[0]), "snap：P1 手牌內容一致")
	# 棄牌堆公開。
	t.eq((snap["discard"]["player1"] as Array).size(), core.player1.discard_pile.size(),
		"snap：P1 棄牌堆數一致")
	t.ok((snap["discard"]["player1"] as Array).has("APW"), "snap：P1 棄牌堆內容帶入")
	# 統計 export。
	t.ok((snap["stats"] as Dictionary).has("HIT"), "snap：統計 export 帶入（HIT）")

	# --- 盤面棋子逐欄位（依 instance_id 對齊 core.get_all_pieces）---
	var pieces: Array = snap["pieces"]
	t.eq(pieces.size(), core.get_all_pieces().size(), "snap：棋子數＝盤面全部棋子（含中立）")
	var by_id: Dictionary = {}
	for pd: Dictionary in pieces:
		by_id[String(pd["instance_id"])] = pd
	for piece: PieceState in core.get_all_pieces():
		var pd: Dictionary = by_id.get(piece.instance_id, {})
		t.ok(not pd.is_empty(), "snap：棋子 %s 有對應欄位" % piece.card_id)
		t.eq(String(pd["card_id"]), piece.card_id, "snap：%s card_id" % piece.card_id)
		t.eq(String(pd["owner"]), piece.owner, "snap：%s owner" % piece.card_id)
		t.eq(int(pd["board_x"]), piece.board_x, "snap：%s board_x" % piece.card_id)
		t.eq(int(pd["board_y"]), piece.board_y, "snap：%s board_y" % piece.card_id)
		t.eq(int(pd["health"]), piece.health, "snap：%s health" % piece.card_id)
		t.eq(int(pd["max_health"]), piece.max_health, "snap：%s max_health" % piece.card_id)
		t.eq(int(pd["damage"]), piece.damage, "snap：%s damage" % piece.card_id)
		t.eq(int(pd["armor"]), piece.armor, "snap：%s armor" % piece.card_id)
		t.eq(int(pd["extra_damage"]), piece.extra_damage, "snap：%s extra_damage" % piece.card_id)
		t.eq(String(pd["attack_types"]), piece.attack_types, "snap：%s attack_types" % piece.card_id)
		t.eq(_snap_status(pd, "numbness"), piece.is_numb(), "snap：%s numbness" % piece.card_id)
	# p1a 的鏡像明細（位置＋本體職業）。
	var p1a: PieceState = core.player1.on_board[0]
	var p1a_pd: Dictionary = by_id[p1a.instance_id]
	t.eq((p1a_pd["shadows"] as Array).size(), 1, "snap：p1a 帶 1 個鏡像")
	t.eq(int(p1a_pd["shadows"][0]["board_x"]), 3, "snap：鏡像 board_x")
	t.eq(String(p1a_pd["shadows"][0]["linker_job"]), "ADC", "snap：鏡像本體職業＝ADC")


# 2. D19 鐵則：快照不含 seed / draw_pile / revealed_deck。
func _test_no_hidden_fields(t: Object) -> void:
	var core := _mk_core()
	var snap: Dictionary = GameSnapshot.encode(core)
	var text: String = JSON.stringify(snap)
	t.ok(not text.contains("seed"), "snap：JSON 不含 seed")
	t.ok(not text.contains("draw_pile"), "snap：JSON 不含牌庫抽序 draw_pile")
	t.ok(not text.contains("revealed_deck"), "snap：JSON 不含 revealed_deck")
	# draw_pile 內容不外洩：抽序頂張不應出現在快照鍵集中（只給張數）。
	t.ok(not snap.has("draw_pile"), "snap：頂層無 draw_pile 鍵")


# 3. JSON round-trip 穩定（正規化後冪等）。
func _test_json_roundtrip_stable(t: Object) -> void:
	var core := _mk_core()
	var snap: Dictionary = GameSnapshot.encode(core)
	var s1: String = JSON.stringify(snap)
	var d1: Variant = JSON.parse_string(s1)
	t.ok(d1 != null, "snap：JSON 可解析")
	var s2: String = JSON.stringify(d1)
	var s3: String = JSON.stringify(JSON.parse_string(s2))
	t.eq(s2, s3, "snap：JSON round-trip 穩定（正規化後冪等）")


func _snap_status(pd: Dictionary, id: String) -> bool:
	var st: Dictionary = pd["statuses"]
	return st.has(id) and bool(st[id].get("value", false))
