# P14-5 素材插槽與自動載入慣例 headless 驗收。見 docs/rebuild/06 P14-5、08 §5.3/§5.5。
#
# 核心不變性：**素材目錄空著時，全案行為與放圖前完全相同**（幾何佔位形／純色背景），
# 放進符合慣例的檔案則自動生效、不改程式。兩個方向都要驗。
#
# 正向路徑用 `tests/fixtures/ADCW.png`（假貼圖）驗，**刻意不把圖放進真正的
# `res://img/piece/card/`**——那會改變遊戲實際外觀，違反本輪「預設值＝現值」的鐵則。
extends RefCounted

const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")
const GalleryScene := preload("res://scenes/battle/piece_gallery.tscn")
const BattleScene := preload("res://scenes/battle/battle.tscn")

const FIXTURE_DIR := "res://tests/fixtures/"
const FIXTURE_CARD := "ADCW"
# 專案既有的真圖，用來驗 texture_at 的正向路徑（與素材慣例無關，只要確定存在）。
const EXISTING_PNG := "res://img/board/board_slot.png"


func run(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()
	_test_paths(t)
	_test_texture_lookup(t)
	_test_piece_sprite_slot(t, db)
	_test_piece_fallback_unchanged(t, db)
	_test_status_icons(t, db)
	_test_background_slot(t)
	_test_board_skin(t)
	_test_gallery(t)
	db.free()


# --- ArtSlots 路徑慣例（純函式） ---

func _test_paths(t: Object) -> void:
	t.eq(ArtSlots.PIECE_DIR, "res://img/piece/card/", "棋子貼圖目錄＝§5.5 裁定慣例")
	t.eq(ArtSlots.BG_DIR, "res://img/UI/bg/", "場景背景目錄＝§5.5 裁定慣例")
	t.eq(ArtSlots.BOARD_SKIN_ORTHO, "res://img/board/skin_ortho.png", "俯視棋盤底圖路徑")
	t.eq(ArtSlots.BOARD_SKIN_ISO, "res://img/board/skin_iso.png", "45 度棋盤底圖路徑")

	t.eq(ArtSlots.piece_texture_path("ADCW"), "res://img/piece/card/ADCW.png", "棋子路徑＝目錄＋card_id.png")
	t.eq(ArtSlots.piece_texture_path("CUBE", "res://foo"), "res://foo/CUBE.png", "自訂目錄補斜線")
	t.eq(ArtSlots.piece_texture_path("CUBE", "res://foo/"), "res://foo/CUBE.png", "自訂目錄已有斜線不重複")
	t.eq(ArtSlots.piece_texture_path("", ""), "", "空 card_id 回空路徑（不查檔）")
	t.eq(ArtSlots.piece_texture_path("ADCW", ""), "res://img/piece/card/ADCW.png", "空目錄退回預設慣例")

	t.eq(ArtSlots.background_path("battle"), "res://img/UI/bg/battle.png", "背景路徑＝目錄＋場景名.png")
	t.eq(ArtSlots.background_path(""), "", "空場景名回空路徑")


func _test_texture_lookup(t: Object) -> void:
	t.ok(ArtSlots.texture_at("") == null, "空路徑回 null")
	t.ok(ArtSlots.texture_at("res://img/piece/card/__不存在__.png") == null, "不存在的檔回 null")
	t.ok(ArtSlots.texture_at(EXISTING_PNG) != null, "存在的圖檔可取得 Texture2D")
	t.ok(ArtSlots.piece_texture(FIXTURE_CARD, FIXTURE_DIR) != null, "fixture 貼圖可經慣例路徑取得")
	# 真正的素材目錄目前是空的 → 全卡皆無圖（＝現況）。這條若轉紅，代表有人把圖放進
	# img/piece/card/ 卻沒同步更新「預設外觀」的相關斷言。
	t.ok(ArtSlots.piece_texture("ADCW") == null, "img/piece/card/ 尚未放圖（現況＝幾何佔位）")


# --- ① 棋子貼圖：有圖啟用 SpriteSlot、無圖 fallback ---

func _test_piece_sprite_slot(t: Object, db: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	v.sprite_dir = FIXTURE_DIR
	v.configure(FIXTURE_CARD, 1, db)
	t.ok(v.has_sprite(), "有圖：SpriteSlot 啟用")
	t.ok(v.sprite_slot.visible, "有圖：SpriteSlot 顯示")
	t.ok(not v.placeholder_shape.visible, "有圖：幾何佔位形隱藏")
	t.ok(not v.outline_shape.visible, "有圖：外框環隱藏")
	t.ok(v.sprite_slot.position.is_equal_approx(v.center_offset()), "有圖：貼圖對齊格中心")
	# 64×32 的貼圖等比縮放到長邊＝CELL_SIZE(96) → 縮放 1.5。
	t.ok(is_equal_approx(v.sprite_slot.scale.x, 1.5) and is_equal_approx(v.sprite_slot.scale.y, 1.5),
		"有圖：等比縮放到長邊塞滿一格")
	# 佔位形雖隱藏，polygon/color 仍在——死亡碎片與殘影以它為色/形來源。
	t.ok(v.placeholder_shape.polygon.size() > 0, "有圖：佔位形資料保留（特效仍取得到形狀）")

	# 取消 fit → 原尺寸。
	v.sprite_fit_cell = false
	v.apply_sprite(ArtSlots.piece_texture(FIXTURE_CARD, FIXTURE_DIR))
	t.ok(v.sprite_slot.scale.is_equal_approx(Vector2.ONE), "取消 fit：貼圖照原尺寸")

	# 取消貼圖 → 還原幾何佔位。
	v.apply_sprite(null)
	t.ok(not v.has_sprite(), "取消貼圖：不再算有圖")
	t.ok(not v.sprite_slot.visible, "取消貼圖：SpriteSlot 隱藏")
	t.ok(v.placeholder_shape.visible, "取消貼圖：幾何佔位形還原")
	t.ok(v.outline_shape.visible, "取消貼圖：外框環還原")
	v.free()

	# 鏡像（SHADOW）：沿用本體職業的貼圖並套半透明（SHADOW_ALPHA）。
	var s: Node2D = PieceViewScene.instantiate()
	s.sprite_dir = FIXTURE_DIR
	s.configure("SHADOW", 1, db, true, FIXTURE_CARD)
	t.ok(s.has_sprite(), "鏡像：沿用本體 shape_key 的貼圖")
	t.ok(is_equal_approx(s.sprite_slot.modulate.a, 0.45), "鏡像：貼圖半透明（SHADOW_ALPHA）")
	s.free()


# 無圖時的行為＝改版前（現況）：佔位形與外框環照舊，SpriteSlot 不顯示。
func _test_piece_fallback_unchanged(t: Object, db: Object) -> void:
	for cid: String in ["ADCW", "TANKBR", "CUBE", "LUCKYBLOCK"]:
		var v: Node2D = PieceViewScene.instantiate()
		v.configure(cid, 1, db)   # sprite_dir＝預設慣例目錄（目前空）
		t.ok(not v.has_sprite(), "無圖 fallback：%s 不啟用貼圖" % cid)
		t.ok(v.placeholder_shape.visible and v.outline_shape.visible,
			"無圖 fallback：%s 幾何佔位形與外框環照舊" % cid)
		v.free()

	# 目錄不存在（美術還沒建目錄）亦安全：一律 fallback，不噴錯。
	var g: Node2D = PieceViewScene.instantiate()
	g.sprite_dir = "res://img/piece/__沒有這個目錄__/"
	g.configure("ADCW", 1, db)
	t.ok(not g.has_sprite(), "目錄不存在：安全 fallback")
	t.ok(g.placeholder_shape.visible, "目錄不存在：佔位形照常顯示")
	g.free()


# --- ③ 狀態 icon：已合規（.tscn 內三顆 TextureRect 已掛圖，編輯器換 texture 即可） ---
# 本項不需程式改動，這裡把「已合規」釘成斷言，避免日後有人改回程式指定貼圖。
func _test_status_icons(t: Object, db: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("ADCW", 1, db)
	for id: String in ["numbness", "anger", "moving"]:
		var icon: Object = v.status_icons.get(id, null)
		t.ok(icon is TextureRect, "狀態 icon %s 為 TextureRect（編輯器可直接換圖）" % id)
		t.ok(icon != null and icon.texture != null, "狀態 icon %s 的貼圖由 .tscn 掛好（非程式指定）" % id)
	v.free()


# --- ② 場景背景插槽：六場景皆有 BackgroundImage，無圖時隱藏 ---

func _test_background_slot(t: Object) -> void:
	var scenes := {
		"battle": "res://scenes/battle/battle.tscn",
		"draft": "res://scenes/draft/draft.tscn",
		"encyclopedia": "res://scenes/encyclopedia/encyclopedia.tscn",
		"end_game": "res://scenes/end_game/end_game.tscn",
		"main_menu": "res://scenes/menu/main_menu.tscn",
		"online_lobby": "res://scenes/online/online_lobby.tscn",
	}
	for name: String in scenes:
		var packed: PackedScene = load(scenes[name])
		var root: Node = packed.instantiate()
		var slot := root.get_node_or_null("BackgroundImage") as TextureRect
		t.ok(slot != null, "%s：有 BackgroundImage 插槽" % name)
		if slot != null:
			t.ok(not slot.visible, "%s：無圖時插槽隱藏（＝純色背景現況）" % name)
			t.ok(slot.texture == null, "%s：無圖時插槽無貼圖" % name)
			t.ok(root.get_node_or_null("Background") != null, "%s：純色 Background 仍在（無圖時的底）" % name)
		root.free()

	# apply_background 行為：查得到圖→填上並顯示；查不到→維持隱藏；slot 為 null→安全略過。
	var tr := TextureRect.new()
	t.ok(not ArtSlots.apply_background(tr, "battle"), "無背景圖：不套用")
	t.ok(not tr.visible and tr.texture == null, "無背景圖：插槽維持隱藏")
	t.ok(ArtSlots.apply_background(tr, "board_slot", "res://img/board/"), "有圖：套用成功")
	t.ok(tr.visible and tr.texture != null, "有圖：插槽顯示並填上貼圖")
	t.ok(not ArtSlots.apply_background(tr, "board_slot", "res://img/__無__/"), "改為無圖：回報未套用")
	t.ok(not tr.visible and tr.texture == null, "改為無圖：插槽退回隱藏（可逆）")
	tr.free()
	t.ok(not ArtSlots.apply_background(null, "battle"), "slot 為 null：安全略過不崩")


# --- ② 棋盤底圖插槽：兩視角各一，無圖時兩張都隱藏；位置隨 BoardAnchor ---

func _test_board_skin(t: Object) -> void:
	var b: Node2D = BattleScene.instantiate()
	var ortho := b.get_node_or_null("BoardSkinLayer/BoardSkinOrtho") as Sprite2D
	var iso := b.get_node_or_null("BoardSkinLayer/BoardSkinIso") as Sprite2D
	t.ok(ortho != null and iso != null, "battle.tscn：兩視角各有棋盤底圖插槽")
	b._bind_nodes()   # 內含 _apply_board_skin
	t.ok(not ortho.visible and not iso.visible, "無底圖：兩張皆隱藏（＝現況只有格線）")
	t.ok(ortho.texture == null and iso.texture == null, "無底圖：插槽無貼圖")
	t.ok(not ortho.centered and not iso.centered, "底圖以左上角定位（centered=false）")
	# 切視角不會讓沒圖的插槽冒出來。
	b._toggle_board_mode()
	t.ok(not ortho.visible and not iso.visible, "切視角後仍無底圖：兩張皆隱藏")
	b.free()


# --- ④ piece_gallery 美術預覽場景 ---

func _test_gallery(t: Object) -> void:
	var g: Node2D = GalleryScene.instantiate()
	for path: String in ["Background", "TitleLabel", "CaptionLabel", "GridRoot", "Camera2D"]:
		t.ok(g.get_node_or_null(path) != null, "gallery 骨架節點：" + path)
	g._build()
	t.ok(g.piece_count() > 0, "gallery：擺出棋子（全卡一覽）")
	t.eq(g.sprite_count(), 0, "gallery：img/piece/card/ 空 → 全部走幾何佔位（現況）")
	t.ok(g.caption_text().contains(ArtSlots.PIECE_DIR), "gallery 副標題標明貼圖來源目錄")
	t.ok(g.caption_text().contains("S 切"), "gallery 副標題標明 S 鍵切換")
	t.ok(g._grid_root.get_child_count() > g.piece_count(), "gallery：棋子與欄列標籤皆掛在 GridRoot")

	# 排版 @export 可調：改欄距後棋子重排（美術在編輯器就能調）。
	var first_pos: Vector2 = _first_piece(g).position
	g.left_margin += 40.0
	g.col_stride += 10.0
	g._build()
	var moved: Vector2 = _first_piece(g).position
	t.ok(not moved.is_equal_approx(first_pos), "gallery：排版 @export 改動後棋子隨之重排")

	# S 鍵的強制 fallback：無圖時統計不變（有圖時才有差異，見 _test_piece_sprite_slot）。
	g._force_fallback = true
	g._build()
	t.eq(g.sprite_count(), 0, "gallery：強制 fallback 模式仍可重建")
	t.ok(g.caption_text().contains("幾何佔位"), "gallery：fallback 模式副標題反映當前模式")
	g.free()


func _first_piece(g: Node2D) -> Node2D:
	for c in g._grid_root.get_children():
		if c is Node2D and not (c is Label):
			return c
	return null
