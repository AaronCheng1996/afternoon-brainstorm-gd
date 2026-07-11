# P2-1 棋子視圖（佔位美術）。規格見 04_架構設計.md §7.1。
# piece_view.tscn 的根腳本；子節點於 configure() 時程序建立（headless 可測資料組裝，無需進場景樹）。
# 動畫插槽（VisualRoot / SpriteSlot）先做好結構，實際動畫由 P2-2 驅動——換圖不改程式：
# 美術到位時填 SpriteSlot 並隱藏 PlaceholderShape 即可。
class_name PieceView
extends Node2D

const PieceShapesScript := preload("res://script/view/piece_shapes.gd")

const CELL_SIZE := 96.0
const P1_OUTLINE := Color(0.90, 0.22, 0.22)   # 先手：紅外框
const P2_OUTLINE := Color(0.25, 0.45, 0.92)   # 後手：藍外框
const NEUTRAL_OUTLINE := Color(0.55, 0.55, 0.55)
const OUTLINE_SCALE := 1.16                    # 外框比本體略大，形成描邊環
const SHADOW_ALPHA := 0.45
const CUBE_FILL := Color(0.70, 0.70, 0.70)
const LUCKYBLOCK_FILL := Color(1.0, 0.84, 0.16)

# 狀態圖示（沿用舊 UI buff 圖；見 04 §6）。以 preload 常數持有，避免 runtime load 殘留於資源快取。
const TEX_NUMBNESS := preload("res://img/UI/buff/stun.png")
const TEX_ANGER := preload("res://img/UI/buff/rage.png")
const TEX_MOVING := preload("res://img/UI/buff/move.png")
const STATUS_TEXTURES := {
	"numbness": TEX_NUMBNESS,
	"anger": TEX_ANGER,
	"moving": TEX_MOVING,
}
const STATUS_ORDER := ["numbness", "anger", "moving"]

var card_id: String = ""
var owner_id: int = 0        # 1=先手, 2=後手, 0=中立
var is_shadow: bool = false

# 動畫（P2-2）：animation_set 為 null 時用 fallback；instant=true 時所有動畫瞬時完成。
var animation_set: PieceAnimationSet = null
var instant: bool = false
var _base_visual_pos := Vector2.ZERO

# 節點參考（configure/_ensure_built 後有效）。
var visual_root: Node2D
var outline_shape: Polygon2D
var placeholder_shape: Polygon2D
var sprite_slot: Sprite2D          # 動畫插槽：之後放美術（Sprite2D/AnimatedSprite2D）
var stats_overlay: Node2D
var status_root: Node2D
var job_label: Label
var name_label: Label
var health_label: Label
var attack_label: Label
var armor_label: Label
var extra_label: Label
var status_icons: Dictionary = {}   # status_id -> TextureRect

var _built: bool = false


# 依 card_id 組裝視覺。db 為 BalanceDB（預設用 autoload Balance）；
# shadow=true 時為 Fuchsia 鏡像（沿用 shadow_job 形狀、半透明、不顯數值）。
func configure(a_card_id: String, a_owner: int, db: Object = null, shadow: bool = false, shadow_job: String = "") -> void:
	_ensure_built()
	card_id = a_card_id
	owner_id = a_owner
	is_shadow = shadow
	var data: Object = db if db != null else Balance

	var job: String = data.job_of(card_id)
	var color_code: String = data.color_code_of(card_id)
	var shape_key: String = shadow_job if shadow else (job if job != "" else card_id)
	var extra_scale: float = 1.1 if shadow else 1.0

	# 形狀（本體 + 外框環）。
	placeholder_shape.polygon = PieceShapesScript.scaled(shape_key, CELL_SIZE, extra_scale)
	outline_shape.polygon = PieceShapesScript.scaled(shape_key, CELL_SIZE, extra_scale * OUTLINE_SCALE)

	# 填色（本體＝職業色）。
	var fill := _fill_color(data, color_code)
	if shadow:
		fill.a = SHADOW_ALPHA
	placeholder_shape.color = fill

	# 外框色（擁有者）。
	var oc := NEUTRAL_OUTLINE
	if owner_id == 1:
		oc = P1_OUTLINE
	elif owner_id == 2:
		oc = P2_OUTLINE
	if shadow:
		oc.a = SHADOW_ALPHA
	outline_shape.color = oc

	# 中央職業碼 / 特殊符號。
	job_label.text = _center_glyph(job, shape_key)
	job_label.modulate = _readable_on(fill)

	# 卡名（繁中，取自 card_text；shadow 顯示「影」）。
	if shadow:
		name_label.text = "影 " + shape_key
	else:
		var info: Dictionary = data.text(card_id)
		name_label.text = String(info.get("name", card_id))

	# 數值（shadow 不顯）。
	if shadow:
		_set_stats_visible(false)
	else:
		var s: Dictionary = data.stats(card_id)
		update_stats(int(s.get("health", 0)), int(s.get("damage", 0)), int(s.get("armor", 0)), 0)

	# 狀態圖示預設全關。
	for id in STATUS_ORDER:
		set_status(id, false)


# 更新數值標籤（供對戰時即時刷新）。armor/extra 為 0 時隱藏。
func update_stats(health: int, damage: int, armor: int, extra_damage: int) -> void:
	_set_stats_visible(true)
	health_label.text = str(health)
	attack_label.text = str(damage)
	armor_label.text = str(armor)
	armor_label.visible = armor > 0
	extra_label.text = "+%d" % extra_damage
	extra_label.visible = extra_damage > 0


# 切換狀態圖示（numbness/anger/moving）。
func set_status(status_id: String, on: bool) -> void:
	if status_icons.has(status_id):
		status_icons[status_id].visible = on


func is_status_visible(status_id: String) -> bool:
	return status_icons.has(status_id) and status_icons[status_id].visible


# 僅更新 HP 標籤（被攻擊後結算用）。
func set_health_display(health: int) -> void:
	_ensure_built()
	health_label.text = str(health)


# --- 動畫（P2-2，見 04 §7.2/7.3）。以 fallback 程序動畫驅動 VisualRoot；換美術改 SpriteSlot 不動介面 ---

func set_animation_set(a_set: PieceAnimationSet) -> void:
	animation_set = a_set


# 攻擊演出：遠程（有投射物）發射箭矢並於命中點播特效；近戰則向目標撲擊。fx_layer 收納投射物/特效。
func play_attack(target_global: Vector2, fx_layer: Node) -> void:
	_ensure_built()
	var aset := _aset()
	if aset.has_projectile() and fx_layer != null:
		_fire_projectile(target_global, fx_layer, aset)
	else:
		_melee_lunge(target_global, aset)


func play_hurt() -> void:
	_ensure_built()
	if instant:
		return
	var tw := create_tween()
	tw.tween_property(visual_root, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.05)
	tw.tween_property(visual_root, "modulate", Color(1, 1, 1, 1), 0.13)
	var shake := create_tween()
	shake.tween_property(visual_root, "position", _base_visual_pos + Vector2(4, 0), 0.04)
	shake.tween_property(visual_root, "position", _base_visual_pos, 0.09)


func play_death(on_done: Callable) -> void:
	_ensure_built()
	if instant:
		if on_done.is_valid():
			on_done.call()
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual_root, "modulate:a", 0.0, 0.28)
	tw.tween_property(visual_root, "scale", Vector2(0.4, 0.4), 0.28)
	tw.chain().tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call())


func play_move(to_global: Vector2) -> void:
	_ensure_built()
	if instant:
		global_position = to_global
		return
	var tw := create_tween()
	tw.tween_property(self, "global_position", to_global, 0.2)


func play_cast() -> void:
	_ensure_built()
	if instant:
		return
	var tw := create_tween()
	tw.tween_property(visual_root, "scale", Vector2(1.15, 1.15), 0.09)
	tw.tween_property(visual_root, "scale", Vector2(1, 1), 0.12)


# 中心（本地 / 全域）。
func center_offset() -> Vector2:
	return Vector2(CELL_SIZE, CELL_SIZE) * 0.5


func center_global() -> Vector2:
	return to_global(center_offset())


func _aset() -> PieceAnimationSet:
	if animation_set == null:
		animation_set = PieceAnimationSet.fallback()
	return animation_set


func _fire_projectile(target_global: Vector2, fx_layer: Node, aset: PieceAnimationSet) -> void:
	var flight: float = 0.0 if instant else aset.lunge_step * aset.hit_ratio
	var proj: Node2D = aset.projectile.instantiate()
	fx_layer.add_child(proj)
	var impact_scene: PackedScene = aset.impact
	var is_instant := instant
	proj.launch(center_global(), target_global, flight, func() -> void:
		if impact_scene != null:
			var fl: Node2D = impact_scene.instantiate()
			fx_layer.add_child(fl)
			fl.global_position = target_global
			fl.play(is_instant), is_instant)
	if not instant:
		# 拉弓小後拉。
		var dir := (target_global - center_global()).normalized()
		var tw := create_tween()
		tw.tween_property(visual_root, "position", _base_visual_pos - dir * 5.0, aset.lunge_step * 0.3)
		tw.tween_property(visual_root, "position", _base_visual_pos, aset.lunge_step * 0.4)


func _melee_lunge(target_global: Vector2, aset: PieceAnimationSet) -> void:
	if instant:
		return
	var dir := (to_local(target_global) - center_offset()).normalized()
	var tw := create_tween()
	tw.tween_property(visual_root, "position", _base_visual_pos + dir * 18.0, aset.lunge_step * 0.5)
	tw.tween_property(visual_root, "position", _base_visual_pos, aset.lunge_step * 0.5)


# --- 內部 ---

func _fill_color(data: Object, color_code: String) -> Color:
	if color_code != "":
		return data.color_rgb(color_code)
	if card_id == "LUCKYBLOCK":
		return LUCKYBLOCK_FILL
	if card_id == "CUBE":
		return CUBE_FILL
	return Color.WHITE


func _center_glyph(job: String, shape_key: String) -> String:
	if is_shadow:
		return shape_key
	if job != "":
		return job
	if card_id == "LUCKYBLOCK":
		return "?"
	if card_id == "CUBE":
		return "■"
	return card_id


# 依填色明暗選白/黑字，確保可讀。
func _readable_on(fill: Color) -> Color:
	var lum := fill.r * 0.299 + fill.g * 0.587 + fill.b * 0.114
	return Color.BLACK if lum > 0.6 else Color.WHITE


func _set_stats_visible(v: bool) -> void:
	health_label.visible = v
	attack_label.visible = v
	if not v:
		armor_label.visible = false
		extra_label.visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	visual_root = Node2D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)

	outline_shape = Polygon2D.new()
	outline_shape.name = "OutlineShape"
	visual_root.add_child(outline_shape)

	placeholder_shape = Polygon2D.new()
	placeholder_shape.name = "PlaceholderShape"
	visual_root.add_child(placeholder_shape)

	sprite_slot = Sprite2D.new()          # 動畫插槽（P2-2 起使用；美術到位換此節點）
	sprite_slot.name = "SpriteSlot"
	sprite_slot.visible = false
	visual_root.add_child(sprite_slot)

	stats_overlay = Node2D.new()
	stats_overlay.name = "StatsOverlay"
	add_child(stats_overlay)

	job_label = _make_label("JobLabel", 22, HORIZONTAL_ALIGNMENT_CENTER)
	job_label.position = Vector2(0, CELL_SIZE * 0.5 - 16)
	job_label.size = Vector2(CELL_SIZE, 24)
	stats_overlay.add_child(job_label)

	name_label = _make_label("NameLabel", 12, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.position = Vector2(-4, -18)
	name_label.size = Vector2(CELL_SIZE + 8, 16)
	name_label.modulate = Color(0.9, 0.9, 0.9)
	stats_overlay.add_child(name_label)

	health_label = _make_label("HealthLabel", 15, HORIZONTAL_ALIGNMENT_LEFT)
	health_label.position = Vector2(2, CELL_SIZE - 20)
	health_label.size = Vector2(CELL_SIZE * 0.5, 20)
	health_label.modulate = Color(0.55, 1.0, 0.55)
	stats_overlay.add_child(health_label)

	attack_label = _make_label("AttackLabel", 15, HORIZONTAL_ALIGNMENT_RIGHT)
	attack_label.position = Vector2(CELL_SIZE * 0.5 - 2, CELL_SIZE - 20)
	attack_label.size = Vector2(CELL_SIZE * 0.5, 20)
	attack_label.modulate = Color(1.0, 0.75, 0.4)
	stats_overlay.add_child(attack_label)

	armor_label = _make_label("ArmorLabel", 13, HORIZONTAL_ALIGNMENT_RIGHT)
	armor_label.position = Vector2(CELL_SIZE * 0.5, -2)
	armor_label.size = Vector2(CELL_SIZE * 0.5 - 2, 18)
	armor_label.modulate = Color(0.6, 0.85, 1.0)
	armor_label.visible = false
	stats_overlay.add_child(armor_label)

	extra_label = _make_label("ExtraLabel", 13, HORIZONTAL_ALIGNMENT_RIGHT)
	extra_label.position = Vector2(CELL_SIZE * 0.5 - 2, CELL_SIZE - 36)
	extra_label.size = Vector2(CELL_SIZE * 0.5, 18)
	extra_label.modulate = Color(1.0, 0.5, 0.5)
	extra_label.visible = false
	stats_overlay.add_child(extra_label)

	status_root = Node2D.new()
	status_root.name = "StatusIcons"
	add_child(status_root)
	var ix := 2.0
	for id in STATUS_ORDER:
		var icon := TextureRect.new()
		icon.name = id
		icon.texture = STATUS_TEXTURES[id]
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(18, 18)
		icon.position = Vector2(ix, 2)
		icon.visible = false
		status_root.add_child(icon)
		status_icons[id] = icon
		ix += 20.0


func _make_label(node_name: String, font_size: int, align: int) -> Label:
	var l := Label.new()
	l.name = node_name
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	# 描邊讓文字在任何底色上可讀。
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l
