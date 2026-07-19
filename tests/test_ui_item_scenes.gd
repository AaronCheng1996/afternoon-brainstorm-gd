# P14-3 item 模板場景 headless 測試（見 docs/rebuild/06 P14-3、08 §5.2）。
#
# 這些場景是「美術可單開檔案調樣式」的入口：程式端 instantiate 後只填資料與信號，
# 尺寸/字級/對齊/唯讀等樣式一律由 .tscn 決定。本檔守兩件事：
#   (1) **預設樣式＝P14-3 前的程式硬編值**——改版不得改變外觀（06 Phase 14 鐵則）。
#   (2) 節點型別正確（呼叫端以靜態型別接住 instantiate 結果，型別錯會在執行期炸）。
# 美術要調樣式時，改 .tscn 後本檔的對應斷言會紅——這是提醒「外觀基準變了」，
# 確認是刻意調整後同步更新此處期望值即可（非 bug）。
extends RefCounted

const HandCardScene := preload("res://scenes/battle/hand_card_button.tscn")
const HandCardReadonlyScene := preload("res://scenes/battle/hand_card_button_readonly.tscn")
const ExhibitCardScene := preload("res://scenes/draft/exhibit_card.tscn")
const DeckRowScene := preload("res://scenes/draft/deck_row_button.tscn")
const CardRowScene := preload("res://scenes/encyclopedia/card_row_button.tscn")
const ColorTabScene := preload("res://scenes/encyclopedia/color_tab_button.tscn")
const JobTabScene := preload("res://scenes/encyclopedia/job_tab_button.tscn")
const DerivButtonScene := preload("res://scenes/encyclopedia/deriv_button.tscn")
const AttackIconScene := preload("res://scenes/encyclopedia/attack_icon.tscn")
const ReplayRowScene := preload("res://scenes/menu/replay_row_button.tscn")
const RoomRowScene := preload("res://scenes/online/room_row_button.tscn")
const StatCellScene := preload("res://scenes/end_game/stat_cell.tscn")
const KeywordTipScene := preload("res://scenes/ui/keyword_tip.tscn")


func run(t: Object) -> void:
	_test_button_items(t)
	_test_hand_card_readonly(t)
	_test_attack_icon(t)
	_test_stat_cell(t)
	_test_keyword_tip(t)


# 各 Button 型 item：型別、最小尺寸、字級＝P14-3 前的硬編值。
# 表格＝[場景, 標籤, 最小尺寸, 字級]。
func _test_button_items(t: Object) -> void:
	var cases: Array = [
		[HandCardScene, "battle 手牌鈕（可點）", Vector2(96, 64), 12],
		[HandCardReadonlyScene, "battle 手牌鈕（唯讀）", Vector2(78, 48), 11],
		[ExhibitCardScene, "draft 展示卡", Vector2(122, 58), 12],
		[DeckRowScene, "draft 牌組列", Vector2(160, 26), 12],
		[CardRowScene, "圖鑑卡片列", Vector2(248, 30), 13],
		[ColorTabScene, "圖鑑色頁籤", Vector2(66, 30), 13],
		[JobTabScene, "圖鑑職業頁籤", Vector2(58, 28), 13],
		[DerivButtonScene, "圖鑑衍生物鈕", Vector2(0, 28), 13],
		[ReplayRowScene, "主選單回放列", Vector2(496, 40), 14],
		[RoomRowScene, "大廳房間列", Vector2(560, 40), 14],
	]
	for c: Array in cases:
		var b: Node = c[0].instantiate()
		var tag: String = c[1]
		t.ok(b is Button, "item：%s 為 Button" % tag)
		t.eq(b.custom_minimum_size, c[2], "item：%s 最小尺寸＝改版前硬編值" % tag)
		t.eq(b.get_theme_font_size("font_size"), c[3], "item：%s 字級＝改版前硬編值" % tag)
		b.free()

	# 圖鑑卡片列刻意靠左對齊（清單可讀性）；其餘按鈕維持置中預設。
	var row: Button = CardRowScene.instantiate()
	t.eq(row.alignment, HORIZONTAL_ALIGNMENT_LEFT, "item：圖鑑卡片列靠左對齊")
	row.free()
	# 衍生物鈕最小寬刻意為 0＝寬度隨文字，勿誤套頁籤的固定寬。
	var deriv: Button = DerivButtonScene.instantiate()
	t.eq(deriv.custom_minimum_size.x, 0.0, "item：衍生物鈕最小寬為 0（寬度隨文字）")
	deriv.free()


# 唯讀手牌列（D19 手牌公開）：`disabled` 必須由場景設好——它是「點擊無作用」的保證，
# 掉了會讓對手手牌變成可點（net 模式下即為非法輸入來源）。
func _test_hand_card_readonly(t: Object) -> void:
	var ro: Button = HandCardReadonlyScene.instantiate()
	t.ok(ro.disabled, "item：唯讀手牌鈕預設 disabled（點擊無作用）")
	ro.free()
	var on: Button = HandCardScene.instantiate()
	t.ok(not on.disabled, "item：可點手牌鈕預設非 disabled")
	on.free()


# 攻擊範圍圖示：尺寸與兩個縮放模式（換圖時維持等比置中、不被容器拉變形）。
func _test_attack_icon(t: Object) -> void:
	var tr: Node = AttackIconScene.instantiate()
	t.ok(tr is TextureRect, "item：攻擊圖示為 TextureRect")
	t.eq(tr.custom_minimum_size, Vector2(52, 52), "item：攻擊圖示尺寸＝改版前硬編值")
	t.eq(tr.expand_mode, TextureRect.EXPAND_IGNORE_SIZE, "item：攻擊圖示 expand_mode")
	t.eq(tr.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "item：攻擊圖示 stretch_mode")
	tr.free()


# 終局統計儲存格／圖表文字：共通樣式＝黑描邊（覆蓋任何底色皆可讀）＋不吃滑鼠事件。
# 字級與字色由呼叫端逐格指定（P14-4 再收斂），故此處只驗共通部分。
func _test_stat_cell(t: Object) -> void:
	var l: Node = StatCellScene.instantiate()
	t.ok(l is Label, "item：統計儲存格為 Label")
	t.eq(l.mouse_filter, Control.MOUSE_FILTER_IGNORE, "item：統計儲存格不吃滑鼠事件")
	t.eq(l.get_theme_constant("outline_size"), 4, "item：統計儲存格黑描邊寬度")
	t.eq(l.get_theme_color("font_outline_color"), Color(0, 0, 0, 0.9), "item：統計儲存格描邊色")
	l.free()


# 關鍵字浮窗：`top_level`（脫離父容器裁切，以視窗座標定位）與高 z_index 是它能正確浮在
# HUD 之上的前提；預設隱藏（懸停才顯示）。內文節點名為 TipLabel＝程式契約，改名會壞。
func _test_keyword_tip(t: Object) -> void:
	var tip: Node = KeywordTipScene.instantiate()
	t.ok(tip is PanelContainer, "item：關鍵字浮窗為 PanelContainer")
	t.ok(tip.top_level, "item：浮窗 top_level（脫離父容器裁切）")
	t.eq(tip.z_index, 4096, "item：浮窗 z_index 高於 HUD")
	t.ok(not tip.visible, "item：浮窗預設隱藏")
	t.eq(tip.custom_minimum_size, Vector2(240, 0), "item：浮窗最小寬＝改版前硬編值")
	var label: Node = tip.get_node_or_null("TipLabel")
	t.ok(label != null, "item：浮窗內文節點 TipLabel 存在（程式契約，勿改名）")
	if label != null:
		t.ok(label is RichTextLabel, "item：浮窗內文為 RichTextLabel")
		t.ok(label.bbcode_enabled, "item：浮窗內文啟用 BBCode（解釋文帶顏色標記）")
		t.ok(label.fit_content, "item：浮窗內文 fit_content（高度隨文字）")
		t.eq(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "item：浮窗內文自動換行")
		t.eq(label.custom_minimum_size, Vector2(220, 0), "item：浮窗內文最小寬＝改版前硬編值")
	tip.free()
