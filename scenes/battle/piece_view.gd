# P2-1 棋子視圖（佔位美術）。規格見 04_架構設計.md §7.1、08_場景編輯器化.md §3。
# P7-3：節點樹宣告於 piece_view.tscn（編輯器可視可編輯，美術可接手）；本腳本只用場景唯一名稱
# （`%NodeName`）綁定既有節點，不再程序建構。呼叫端一律 instantiate 場景。
# 動畫插槽（VisualRoot / SpriteSlot）已在 .tscn 備好，實際動畫由 combat_scheduler 驅動——換圖不改程式。
# P14-5：`configure()` 會自動查 `res://img/piece/card/<card_id>.png`（見 ArtSlots），有圖即啟用
# SpriteSlot、隱藏幾何佔位形；目錄空著時行為與放圖前完全相同。美術只要丟檔案，不需碰程式。
class_name PieceView
extends Node2D

const PieceShapesScript := preload("res://script/view/piece_shapes.gd")

const CELL_SIZE := 96.0
# 棋子本體維持「純色」（職業/派別填色）；描邊改為中立深色，僅作形狀定義。
# 擁有者（先手紅／後手藍）改由「棋子所在格的地格外框」呈現（見 battle._persist_draw）。
# P14-4：佔位美術的三個色改 @export（美術可在編輯器調；預設值＝P14-4 前的常數）。
# 派別色不在這裡——一律走 Balance.color_rgb 資料驅動（鐵則，見 08 §5.0）。
# 特效暫態色（受擊白閃/火花/施法環/殘影）＝下方「特效參數」群組（P14-6）。
@export_group("佔位美術配色")
## 中立深色描邊（貼近棋盤底色，讓形狀有清晰邊界）。
@export var edge_color: Color = Color(0.09, 0.10, 0.12)
## CUBE 方塊的填色。
@export var cube_fill: Color = Color(0.70, 0.70, 0.70)
## LUCKYBLOCK 幸運方塊的填色。
@export var luckyblock_fill: Color = Color(1.0, 0.84, 0.16)
@export_group("")

# P14-5 美術素材插槽：`configure()` 會查 `<sprite_dir>/<card_id>.png`——**有圖就用圖**
# （SpriteSlot 顯示、幾何佔位形與外框環隱藏），**無圖維持現行幾何佔位**（行為與放圖前完全相同）。
# 美術只要把檔案丟進目錄即生效，不用改程式（路徑慣例見 ArtSlots／11_美術指南.md）。
@export_group("美術素材")
## 棋子貼圖目錄；檔名＝card_id（如 `ADCW.png`）。留空＝用 ArtSlots 預設慣例目錄。
@export_dir var sprite_dir: String = ArtSlots.PIECE_DIR
## 勾選時把貼圖等比縮放到剛好塞滿一格（CELL_SIZE）；取消則照貼圖原尺寸顯示。
@export var sprite_fit_cell: bool = true
@export_group("")

# P14-6 特效與動畫參數：P9-2/P9-3 的演出常數全數改 @export（**預設值＝改版前的常數**，
# 畫面不變）。美術/企劃可在 piece_view.tscn 直接調手感，不必讀程式；效果預覽場景＝
# `scenes/battle/anim_demo.tscn`（編輯器 F6）。
# **不變性**：`play_attack`/`play_hurt`/`play_death`/`play_cast` 的 `if instant: return`
# 提前返回＝瞬時模式零特效，任何參數都不得繞過它（既有斷言守護）。
@export_group("特效：受擊")
## 受擊白閃的亮度色（>1 為過曝）。
@export var hurt_flash_color: Color = Color(1.8, 1.8, 1.8, 1.0)
## 白閃亮起／回復的時間（秒）。
@export var hurt_flash_in: float = 0.05
@export var hurt_flash_out: float = 0.13
## 受擊抖動的水平位移（像素）與去/回時間（秒）。
@export var hurt_shake_offset: float = 4.0
@export var hurt_shake_out: float = 0.04
@export var hurt_shake_back: float = 0.09
## 命中頓幀：壓扁比例、壓扁時間、定格時間、回彈時間（秒）。
@export var hurt_squash: Vector2 = Vector2(1.18, 0.84)
@export var hurt_squash_time: float = 0.03
@export var hurt_hold_time: float = 0.045
@export var hurt_recover_time: float = 0.12
@export_group("")

@export_group("特效：粒子")
## 受擊小火花：顆數、存活秒數、初速下/上限、顆粒大小、顏色。
@export var hit_particles: int = 8
@export var hit_particle_life: float = 0.35
@export var hit_particle_speed_min: float = 60.0
@export var hit_particle_speed_max: float = 150.0
@export var hit_particle_size: float = 2.5
@export var hit_particle_color: Color = Color(1.0, 0.92, 0.62)
## 死亡碎片：顆數、存活秒數、初速下/上限、顆粒大小（顏色＝棋子本體填色，故無參數）。
@export var death_particles: int = 16
@export var death_particle_life: float = 0.5
@export var death_particle_speed_min: float = 90.0
@export var death_particle_speed_max: float = 220.0
@export var death_particle_size: float = 3.5
@export_group("")

@export_group("特效：死亡與殘影")
## 死亡淡出：時間（秒）、縮到的比例、旋轉弧度。
@export var death_fade_time: float = 0.28
@export var death_shrink_scale: Vector2 = Vector2(0.4, 0.4)
@export var death_spin: float = 0.6
## 殘影：初始不透明度、放大倍率、淡出時間（秒）。
@export var afterimage_alpha: float = 0.5
@export var afterimage_scale: float = 1.4
@export var afterimage_time: float = 0.32
@export_group("")

@export_group("特效：施法環")
## 本體脈動：放大比例、放大／回復時間（秒）。
@export var cast_pulse_scale: Vector2 = Vector2(1.15, 1.15)
@export var cast_pulse_up: float = 0.09
@export var cast_pulse_down: float = 0.12
## 能量環：邊數、半徑（像素）、不透明度、起始／結束縮放、擴散時間（秒）。
@export var cast_ring_segments: int = 20
@export var cast_ring_radius: float = 30.0
@export var cast_ring_alpha: float = 0.7
@export var cast_ring_scale_from: float = 0.3
@export var cast_ring_scale_to: float = 1.5
@export var cast_ring_time: float = 0.3
@export_group("")

@export_group("特效：攻擊位移")
## 遠程拉弓的後拉距離（像素）與去/回佔 `lunge_step` 的比例。
@export var draw_back_distance: float = 5.0
@export var draw_back_out_ratio: float = 0.3
@export var draw_back_in_ratio: float = 0.4
## 近戰撲擊的衝刺距離（像素）；去/回各佔 `lunge_step` 的一半（命中判在撲到位時）。
@export var lunge_distance: float = 18.0
## 移動到新格的滑行時間（秒）。
@export var move_time: float = 0.2
@export_group("")

const OUTLINE_SCALE := 1.16                    # 外框比本體略大，形成描邊環
const SHADOW_ALPHA := 0.45

# 狀態圖示（沿用舊 UI buff 圖；見 04 §6）。圖檔已貼於 piece_view.tscn 的 StatusIcons 子節點。
const STATUS_ORDER := ["numbness", "anger", "moving"]

var card_id: String = ""
var owner_id: int = 0        # 1=先手, 2=後手, 0=中立
var is_shadow: bool = false

# 動畫（P2-2）：animation_set 為 null 時用 fallback；instant=true 時所有動畫瞬時完成。
var animation_set: PieceAnimationSet = null
var instant: bool = false
var _base_visual_pos := Vector2.ZERO

# P9-2：命中/死亡特效容器。粒子與殘影生成到此層（而非本視圖），使其在本視圖被 queue_free
# 之後仍能存活播完。呼叫端（battle/anim_demo）於建立視圖時設定；null 時退回本視圖自身。
var fx_layer: Node = null

# 節點參考（_bind_nodes 後有效，取自 .tscn 內宣告的 `%` 唯一名稱節點）。
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

var _bound: bool = false


func _ready() -> void:
	_bind_nodes()


# 依 card_id 組裝視覺。db 為 BalanceDB（預設用 autoload Balance）；
# shadow=true 時為 Fuchsia 鏡像（沿用 shadow_job 形狀、半透明、不顯數值）。
func configure(a_card_id: String, a_owner: int, db: Object = null, shadow: bool = false, shadow_job: String = "") -> void:
	_bind_nodes()
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

	# 描邊色：中立深色（擁有者顏色已改由地格外框呈現，棋子本體維持純色）。
	var oc := edge_color
	if shadow:
		oc.a = SHADOW_ALPHA
	outline_shape.color = oc

	# P14-5：查美術貼圖——有圖則啟用 SpriteSlot 並隱藏幾何佔位形，無圖維持佔位（現況）。
	# 查的是「本體的 card_id」；鏡像（SHADOW）沿用本體職業的形狀慣例，貼圖亦查 shape_key。
	apply_sprite(ArtSlots.piece_texture(shape_key if shadow else card_id, sprite_dir))

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


# P14-5 套用（或取消）美術貼圖。tex 非 null＝顯示 SpriteSlot 並隱藏幾何佔位形與外框環；
# null＝還原幾何佔位（fallback）。configure() 會自動查檔呼叫本方法，外部亦可直接指定貼圖。
# 幾何佔位形雖被隱藏，polygon/color 仍保留——死亡碎片與殘影（_spawn_death_particles/
# _spawn_afterimage）以它為色/形來源，隱藏不影響特效。鏡像（SHADOW）半透明規則沿用 SHADOW_ALPHA。
func apply_sprite(tex: Texture2D) -> void:
	_bind_nodes()
	sprite_slot.texture = tex
	sprite_slot.visible = tex != null
	placeholder_shape.visible = tex == null
	outline_shape.visible = tex == null
	if tex == null:
		return
	# 貼圖以格中心對齊（Sprite2D 預設 centered），本視圖原點＝格左上角。
	sprite_slot.position = center_offset()
	sprite_slot.modulate.a = SHADOW_ALPHA if is_shadow else 1.0
	if sprite_fit_cell:
		var src: Vector2 = tex.get_size()
		var longest: float = maxf(src.x, src.y)
		var k: float = (CELL_SIZE / longest) if longest > 0.0 else 1.0
		sprite_slot.scale = Vector2(k, k)
	else:
		sprite_slot.scale = Vector2.ONE


# 是否正在用美術貼圖（而非幾何佔位形）。供 piece_gallery 統計與測試判定。
func has_sprite() -> bool:
	_bind_nodes()
	return sprite_slot.texture != null and sprite_slot.visible


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
	_bind_nodes()
	health_label.text = str(health)


# --- 動畫（P2-2，見 04 §7.2/7.3）。以 fallback 程序動畫驅動 VisualRoot；換美術改 SpriteSlot 不動介面 ---

func set_animation_set(a_set: PieceAnimationSet) -> void:
	animation_set = a_set


# 攻擊演出：遠程（有投射物）發射箭矢並於命中點播特效；近戰則向目標撲擊並在命中點濺出派別色火花。
# fx_layer 收納投射物/特效（P9-3：投射物、命中特效皆以 aset.fx_color 派別色上色）。
func play_attack(target_global: Vector2, a_fx_layer: Node) -> void:
	_bind_nodes()
	if instant:
		return   # 瞬時模式：不生成任何特效節點（零特效不變性；投射物/命中特效皆純演出）
	var aset := _aset()
	if aset.has_projectile() and a_fx_layer != null:
		_fire_projectile(target_global, a_fx_layer, aset)
	else:
		_melee_lunge(target_global, aset)


# 受擊演出（P9-2 強化）：白閃＋抖動＋局部命中頓幀（squash-and-hold）＋受擊粒子。
# 頓幀＝瞬間壓扁後短暫定格再彈回，強調打擊瞬間；粒子為程序生成（CPUParticles2D），非點陣素材。
func play_hurt() -> void:
	_bind_nodes()
	if instant:
		return
	var tw := create_tween()
	tw.tween_property(visual_root, "modulate", hurt_flash_color, hurt_flash_in)
	# 回復＝取消染色（恆等值，非可調參數，故用 Color.WHITE 而非 @export）。
	tw.tween_property(visual_root, "modulate", Color.WHITE, hurt_flash_out)
	var shake := create_tween()
	shake.tween_property(visual_root, "position",
		_base_visual_pos + Vector2(hurt_shake_offset, 0), hurt_shake_out)
	shake.tween_property(visual_root, "position", _base_visual_pos, hurt_shake_back)
	# 局部命中頓幀：壓扁 → 短暫定格 → 回彈（TRANS_BACK 收尾帶輕微過衝）。
	var punch := create_tween()
	punch.tween_property(visual_root, "scale", hurt_squash, hurt_squash_time)
	punch.tween_interval(hurt_hold_time)
	punch.tween_property(visual_root, "scale", Vector2(1, 1), hurt_recover_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_hit_particles()


# 死亡演出（P9-2 強化）：淡出縮小＋碎裂旋轉＋短暫殘影（afterimage）＋碎片粒子。
# 殘影與粒子掛在 fx_layer（本視圖 queue_free 後仍存活播完）。
func play_death(on_done: Callable) -> void:
	_bind_nodes()
	if instant:
		if on_done.is_valid():
			on_done.call()
		return
	_spawn_afterimage()
	_spawn_death_particles()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual_root, "modulate:a", 0.0, death_fade_time)
	tw.tween_property(visual_root, "scale", death_shrink_scale, death_fade_time)
	tw.tween_property(visual_root, "rotation", death_spin, death_fade_time)
	tw.chain().tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call())


func play_move(to_global: Vector2) -> void:
	_bind_nodes()
	if instant:
		global_position = to_global
		return
	var tw := create_tween()
	tw.tween_property(self, "global_position", to_global, move_time)


# 施法/能力觸發演出（P9-3 強化）：本體脈動 ＋ 一圈派別色向外擴散的能量環（程序生成）。
# 由 CAST 事件驅動（core 在能力型攻擊時發出）；瞬時模式不演出。
func play_cast() -> void:
	_bind_nodes()
	if instant:
		return
	var tw := create_tween()
	tw.tween_property(visual_root, "scale", cast_pulse_scale, cast_pulse_up)
	tw.tween_property(visual_root, "scale", Vector2(1, 1), cast_pulse_down)
	_spawn_cast_ring()


# 中心（本地 / 全域）。
func center_offset() -> Vector2:
	return Vector2(CELL_SIZE, CELL_SIZE) * 0.5


func center_global() -> Vector2:
	return to_global(center_offset())


func _aset() -> PieceAnimationSet:
	if animation_set == null:
		animation_set = PieceAnimationSet.fallback()
	return animation_set


func _fire_projectile(target_global: Vector2, layer: Node, aset: PieceAnimationSet) -> void:
	var flight: float = 0.0 if instant else aset.lunge_step * aset.hit_ratio
	var proj: Node2D = aset.projectile.instantiate()
	layer.add_child(proj)
	if proj.has_method("set_color"):
		proj.set_color(aset.fx_color)   # P9-3：投射物染派別色
	var impact_scene: PackedScene = aset.impact
	var fx_color: Color = aset.fx_color
	var is_instant := instant
	# 命中回呼只捕捉區域變數＋呼叫 static _play_impact，不參考本視圖（self）——投射物飛行期間
	# 排程器可能已判定結束並重建棋盤而釋放本視圖（飛行 tween 不計入排程忙碌），此時回呼仍需安全執行。
	proj.launch(center_global(), target_global, flight, func() -> void:
		PieceView._play_impact(impact_scene, layer, target_global, fx_color, is_instant), is_instant)
	if not instant:
		# 拉弓小後拉。
		var dir := (target_global - center_global()).normalized()
		var tw := create_tween()
		tw.tween_property(visual_root, "position", _base_visual_pos - dir * draw_back_distance,
			aset.lunge_step * draw_back_out_ratio)
		tw.tween_property(visual_root, "position", _base_visual_pos,
			aset.lunge_step * draw_back_in_ratio)


# 近戰撲擊（P9-3）：向目標衝刺後回位，命中瞬間（撲到位時）在目標點濺出派別色命中特效。
func _melee_lunge(target_global: Vector2, aset: PieceAnimationSet) -> void:
	if instant:
		return
	var dir := (to_local(target_global) - center_offset()).normalized()
	var tw := create_tween()
	tw.tween_property(visual_root, "position", _base_visual_pos + dir * lunge_distance,
		aset.lunge_step * 0.5)
	tw.tween_property(visual_root, "position", _base_visual_pos, aset.lunge_step * 0.5)
	# 撲到位時（lunge_step*0.5）於目標點播派別色命中特效（獨立時間軸，避免與撲擊 tween 交纏）。
	# fx 容器先取為區域變數，回呼不參考 self（撲擊 tween 綁定本節點，本視圖釋放時自動終止，此為雙保險）。
	var impact_scene: PackedScene = aset.impact if aset.impact != null else _default_impact()
	var fx_color: Color = aset.fx_color
	var fx_parent := _fx_parent()
	var hit := create_tween()
	hit.tween_interval(aset.lunge_step * 0.5)
	hit.tween_callback(func() -> void:
		PieceView._play_impact(impact_scene, fx_parent, target_global, fx_color, false))


# 於 at_global 播放命中特效（染 tint）。impact_scene 為 null 時不播。static：不依賴本視圖存活。
static func _play_impact(impact_scene: PackedScene, layer: Node, at_global: Vector2, tint: Color, is_instant: bool) -> void:
	if impact_scene == null or layer == null or not is_instance_valid(layer):
		return
	var fl: Node2D = impact_scene.instantiate()
	layer.add_child(fl)
	if fl.has_method("set_color"):
		fl.set_color(tint)
	fl.global_position = at_global
	fl.play(is_instant)


func _default_impact() -> PackedScene:
	return load("res://scenes/battle/impact_flash.tscn")


# --- P9-2 命中/死亡特效（程序生成粒子；不使用點陣素材，見鐵則 3） ---

# 特效容器：優先 fx_layer（本視圖釋放後仍存活），否則掛本視圖自身。
func _fx_parent() -> Node:
	return fx_layer if fx_layer != null else self


# 受擊小火花：向上噴濺、受重力回落，隨命中閃光色系。
func _spawn_hit_particles() -> void:
	var p := _make_burst(hit_particles, hit_particle_life, hit_particle_speed_min,
		hit_particle_speed_max, hit_particle_color, hit_particle_size)
	p.global_position = center_global()
	p.emitting = true


# 死亡碎片：以本體填色向四面爆開，數量更多、初速更大。
func _spawn_death_particles() -> void:
	var fill := placeholder_shape.color
	fill.a = 1.0
	var p := _make_burst(death_particles, death_particle_life, death_particle_speed_min,
		death_particle_speed_max, fill, death_particle_size)
	p.global_position = center_global()
	p.emitting = true


# 施法能量環（P9-3）：一圈派別色圓環於本體中心向外擴散並淡出，標示「能力觸發」。
func _spawn_cast_ring() -> void:
	var ring := Polygon2D.new()
	var seg: int = maxi(3, cast_ring_segments)
	var pts := PackedVector2Array()
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		pts.append(Vector2(cos(a), sin(a)) * cast_ring_radius)
	ring.polygon = pts
	var c := placeholder_shape.color
	c.a = cast_ring_alpha
	ring.color = c
	ring.z_index = z_index + 1
	_fx_parent().add_child(ring)
	ring.global_position = center_global()
	ring.scale = Vector2(cast_ring_scale_from, cast_ring_scale_from)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(cast_ring_scale_to, cast_ring_scale_to), cast_ring_time)
	tw.tween_property(ring, "modulate:a", 0.0, cast_ring_time)
	tw.chain().tween_callback(ring.queue_free)


# 短暫殘影：複製本體多邊形，於原位放大並淡出。
func _spawn_afterimage() -> void:
	var ghost := Polygon2D.new()
	ghost.polygon = placeholder_shape.polygon
	var c := placeholder_shape.color
	c.a = afterimage_alpha
	ghost.color = c
	ghost.z_index = z_index
	_fx_parent().add_child(ghost)
	ghost.global_position = placeholder_shape.global_position
	ghost.scale = placeholder_shape.global_scale
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "scale", ghost.scale * afterimage_scale, afterimage_time)
	tw.tween_property(ghost, "modulate:a", 0.0, afterimage_time)
	tw.chain().tween_callback(ghost.queue_free)


# 一次性粒子爆發（CPUParticles2D，one_shot 完成後自我釋放）。
func _make_burst(amount: int, lifetime: float, vmin: float, vmax: float, color: Color, size: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 320)
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.6
	p.color = color
	p.z_index = z_index + 1
	p.finished.connect(p.queue_free)
	_fx_parent().add_child(p)
	return p


# --- 內部 ---

func _fill_color(data: Object, color_code: String) -> Color:
	if color_code != "":
		return data.color_rgb(color_code)
	if card_id == "LUCKYBLOCK":
		return luckyblock_fill
	if card_id == "CUBE":
		return cube_fill
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


# 綁定 .tscn 內宣告的節點（場景唯一名稱 `%`）。idempotent：_ready 與各公開方法皆會呼叫，
# 首次生效。`%` 於 instantiate 後即可解析（不需先加入場景樹），故 headless 亦適用。
func _bind_nodes() -> void:
	if _bound:
		return
	_bound = true
	visual_root = %VisualRoot
	outline_shape = %OutlineShape
	placeholder_shape = %PlaceholderShape
	sprite_slot = %SpriteSlot
	stats_overlay = %StatsOverlay
	status_root = %StatusIcons
	job_label = %JobLabel
	name_label = %NameLabel
	health_label = %HealthLabel
	attack_label = %AttackLabel
	armor_label = %ArmorLabel
	extra_label = %ExtraLabel
	status_icons = {
		"numbness": %NumbnessIcon,
		"anger": %AngerIcon,
		"moving": %MovingIcon,
	}
	_base_visual_pos = visual_root.position
