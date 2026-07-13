# P1-1 玩家狀態（翻譯自 core/player.py）。deck/hand/牌庫/棄牌堆/revealed_deck 與抽牌邏輯。
class_name PlayerState
extends RefCounted

var name: String
var deck: Array[String] = []
var hand: Array[String] = []
var draw_pile: Array[String] = []
var discard_pile: Array[String] = []
var revealed_deck: Array[String] = []   # 牌組前 6 張 + 之後每抽到新名字就加入（AI/遮蔽用）
var on_board: Array = []                 # Array[PieceState]


func _init(player_name: String, deck_list: Array) -> void:
	name = player_name
	deck.assign(deck_list)
	# revealed_deck 初始 = 牌組前 6 張（見 player.py __post_init__）。
	revealed_deck.assign(deck.slice(0, 6))


# 抽一張牌（見 player.py draw_card）：牌庫空則洗棄牌堆重建牌庫再抽。
func draw_card(rng: RngService) -> void:
	var card_name := ""
	if not draw_pile.is_empty():
		card_name = draw_pile.pop_back()      # Python list.pop() 取尾端
		hand.append(card_name)
	elif not discard_pile.is_empty():
		rng.shuffle(discard_pile)
		draw_pile.assign(discard_pile)
		discard_pile.clear()
		card_name = draw_pile.pop_back()
		hand.append(card_name)
	# 牌庫與棄牌堆皆空：抽不到牌（card_name 保持空）。
	if card_name != "":
		if revealed_deck.count(card_name) < deck.count(card_name):
			revealed_deck.append(card_name)
