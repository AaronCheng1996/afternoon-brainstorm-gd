# P14-6 特效與動畫參數編輯器化 headless 驗收。見 docs/rebuild/06 P14-6、08 §5.2。
#
# 本輪把 P9 演出的硬編常數改成 @export（美術可在編輯器調手感）。兩件事必須守住：
#   ①**預設值＝改版前的常數**——畫面不變。下面逐項釘住原值，改壞了會轉紅。
#   ②**瞬時模式零特效不變性**——`if instant: return` 的提前返回不得被任何參數繞過
#     （既有 test_piece_view 已守受擊/死亡/施法；這裡補「改了參數也不會繞過」）。
# 另驗參數確實有效（改了就會反映到實際生成的特效節點上），避免「@export 只是擺著沒人讀」。
extends RefCounted

const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")
const BattleScene := preload("res://scenes/battle/battle.tscn")
const AnimDemoScene := preload("res://scenes/battle/anim_demo.tscn")
const ProjectileScene := preload("res://scenes/battle/projectile.tscn")
const ImpactScene := preload("res://scenes/battle/impact_flash.tscn")
const SchedulerScript := preload("res://script/view/combat_scheduler.gd")


func run(t: Object) -> void:
	var db: Object = load("res://script/data/balance_db.gd").new()
	_test_piece_view_defaults(t)
	_test_piece_view_params_effective(t, db)
	_test_instant_invariance_with_custom_params(t, db)
	_test_projectile_and_impact(t)
	_test_scheduler_float_params(t)
	_test_battle_shake_params(t)
	_test_anim_demo_skeleton(t)
	db.free()


# ① 預設值＝改版前常數（逐項對照 08 §5.2 的盤查紀錄）。
func _test_piece_view_defaults(t: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	# 受擊。
	t.ok(v.hurt_flash_color.is_equal_approx(Color(1.8, 1.8, 1.8, 1.0)), "預設：受擊白閃色")
	t.ok(is_equal_approx(v.hurt_flash_in, 0.05) and is_equal_approx(v.hurt_flash_out, 0.13),
		"預設：白閃 0.05/0.13")
	t.ok(is_equal_approx(v.hurt_shake_offset, 4.0), "預設：受擊抖動 4px")
	t.ok(is_equal_approx(v.hurt_shake_out, 0.04) and is_equal_approx(v.hurt_shake_back, 0.09),
		"預設：抖動 0.04/0.09")
	t.ok(v.hurt_squash.is_equal_approx(Vector2(1.18, 0.84)), "預設：頓幀壓扁 (1.18,0.84)")
	t.ok(is_equal_approx(v.hurt_squash_time, 0.03) and is_equal_approx(v.hurt_hold_time, 0.045)
		and is_equal_approx(v.hurt_recover_time, 0.12), "預設：頓幀 0.03＋0.045＋0.12")
	# 粒子。
	t.eq(v.hit_particles, 8, "預設：受擊火花 8 顆")
	t.ok(is_equal_approx(v.hit_particle_life, 0.35), "預設：火花 0.35s")
	t.ok(is_equal_approx(v.hit_particle_speed_min, 60.0)
		and is_equal_approx(v.hit_particle_speed_max, 150.0), "預設：火花初速 60–150")
	t.ok(is_equal_approx(v.hit_particle_size, 2.5), "預設：火花 2.5px")
	t.ok(v.hit_particle_color.is_equal_approx(Color(1.0, 0.92, 0.62)), "預設：火花色")
	t.eq(v.death_particles, 16, "預設：死亡碎片 16 顆")
	t.ok(is_equal_approx(v.death_particle_life, 0.5), "預設：碎片 0.5s")
	t.ok(is_equal_approx(v.death_particle_speed_min, 90.0)
		and is_equal_approx(v.death_particle_speed_max, 220.0), "預設：碎片初速 90–220")
	t.ok(is_equal_approx(v.death_particle_size, 3.5), "預設：碎片 3.5px")
	# 死亡與殘影。
	t.ok(is_equal_approx(v.death_fade_time, 0.28), "預設：死亡淡出 0.28s")
	t.ok(v.death_shrink_scale.is_equal_approx(Vector2(0.4, 0.4)), "預設：死亡縮到 0.4")
	t.ok(is_equal_approx(v.death_spin, 0.6), "預設：死亡旋轉 0.6")
	t.ok(is_equal_approx(v.afterimage_alpha, 0.5) and is_equal_approx(v.afterimage_scale, 1.4)
		and is_equal_approx(v.afterimage_time, 0.32), "預設：殘影 0.5／×1.4／0.32s")
	# 施法環。
	t.ok(v.cast_pulse_scale.is_equal_approx(Vector2(1.15, 1.15)), "預設：施法脈動 1.15")
	t.ok(is_equal_approx(v.cast_pulse_up, 0.09) and is_equal_approx(v.cast_pulse_down, 0.12),
		"預設：脈動 0.09/0.12")
	t.eq(v.cast_ring_segments, 20, "預設：能量環 20 邊")
	t.ok(is_equal_approx(v.cast_ring_radius, 30.0), "預設：能量環半徑 30")
	t.ok(is_equal_approx(v.cast_ring_alpha, 0.7), "預設：能量環不透明度 0.7")
	t.ok(is_equal_approx(v.cast_ring_scale_from, 0.3) and is_equal_approx(v.cast_ring_scale_to, 1.5)
		and is_equal_approx(v.cast_ring_time, 0.3), "預設：能量環 0.3→1.5／0.3s")
	# 攻擊位移。
	t.ok(is_equal_approx(v.draw_back_distance, 5.0), "預設：拉弓後拉 5px")
	t.ok(is_equal_approx(v.draw_back_out_ratio, 0.3) and is_equal_approx(v.draw_back_in_ratio, 0.4),
		"預設：拉弓去/回 0.3/0.4")
	t.ok(is_equal_approx(v.lunge_distance, 18.0), "預設：近戰撲擊 18px")
	t.ok(is_equal_approx(v.move_time, 0.2), "預設：移動滑行 0.2s")
	v.free()


# 參數確實被讀到：改粒子數/大小/色/環邊數後，實際生成的節點跟著變。
func _test_piece_view_params_effective(t: Object, db: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("ADCW", 1, db)
	var fx := Node2D.new()
	v.fx_layer = fx

	v.hit_particles = 3
	v.hit_particle_size = 9.0
	v.hit_particle_color = Color(0.1, 0.2, 0.3, 1.0)
	v.play_hurt()
	var p: CPUParticles2D = _first_of(fx, "CPUParticles2D")
	t.ok(p != null, "受擊：生成粒子節點")
	if p != null:
		t.eq(p.amount, 3, "受擊粒子數吃 @export")
		t.ok(is_equal_approx(p.scale_amount_min, 9.0), "受擊粒子大小吃 @export")
		t.ok(p.color.is_equal_approx(Color(0.1, 0.2, 0.3, 1.0)), "受擊粒子色吃 @export")

	v.cast_ring_segments = 6
	v.cast_ring_radius = 12.0
	v.play_cast()
	var ring: Polygon2D = _first_of(fx, "Polygon2D")
	t.ok(ring != null, "施法：生成能量環")
	if ring != null:
		t.eq(ring.polygon.size(), 6, "能量環邊數吃 @export")
		t.ok(is_equal_approx(ring.polygon[0].length(), 12.0), "能量環半徑吃 @export")
		t.ok(is_equal_approx(ring.color.a, v.cast_ring_alpha), "能量環不透明度吃 @export")

	fx.free()
	v.free()


# ② 瞬時模式零特效不變性：即使把參數調成誇張值，instant=true 一樣不生任何特效節點。
func _test_instant_invariance_with_custom_params(t: Object, db: Object) -> void:
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("ADCW", 1, db)
	v.instant = true
	v.hit_particles = 999
	v.death_particles = 999
	v.cast_ring_segments = 64
	v.afterimage_alpha = 1.0
	var fx := Node2D.new()
	v.fx_layer = fx
	v.play_hurt()
	v.play_cast()
	t.eq(fx.get_child_count(), 0, "瞬時＋自訂參數：受擊/施法仍零特效")
	var done := [false]
	v.play_death(func() -> void: done[0] = true)
	t.ok(done[0], "瞬時＋自訂參數：死亡仍立即回呼")
	t.eq(fx.get_child_count(), 0, "瞬時＋自訂參數：死亡仍零特效")
	t.ok(v.visual_root.scale.is_equal_approx(Vector2.ONE), "瞬時＋自訂參數：不改縮放")
	fx.free()
	v.free()


func _test_projectile_and_impact(t: Object) -> void:
	var p: Node2D = ProjectileScene.instantiate()
	t.ok(p.fill_color.is_equal_approx(Color(1.0, 0.85, 0.3)), "預設：投射物填色")
	t.eq(p.arrow_polygon.size(), 4, "預設：箭矢 4 點")
	p._build()
	var body: Polygon2D = p.get_node_or_null("Body")
	t.ok(body != null and body.color.is_equal_approx(p.fill_color), "投射物本體吃 fill_color")
	t.ok(body != null and body.polygon == p.arrow_polygon, "投射物本體吃 arrow_polygon")
	p.set_color(Color(0, 1, 0))
	t.ok(body.color.is_equal_approx(Color(0, 1, 0)), "set_color（派別色）仍蓋過預設")
	p.free()

	var f: Node2D = ImpactScene.instantiate()
	t.ok(f.fill_color.is_equal_approx(Color(1.0, 0.95, 0.6)), "預設：命中閃光填色")
	t.ok(is_equal_approx(f.duration, 0.20), "預設：命中閃光 0.20s")
	t.ok(is_equal_approx(f.ring_radius, 10.0) and f.ring_segments == 16, "預設：閃光環 r10／16 邊")
	t.ok(is_equal_approx(f.scale_from, 0.3) and is_equal_approx(f.scale_to, 1.6),
		"預設：閃光 0.3→1.6")
	f.free()


func _test_scheduler_float_params(t: Object) -> void:
	var s: Node = SchedulerScript.new()
	t.eq(s.damage_font_size, 18, "預設：傷害飄字字級 18")
	t.ok(s.damage_color.is_equal_approx(Color(1.0, 0.5, 0.4)), "預設：傷害飄字色")
	t.ok(s.damage_offset.is_equal_approx(Vector2(-8, -20)), "預設：傷害飄字起始偏移")
	t.ok(is_equal_approx(s.damage_rise, -28.0), "預設：傷害飄字上飄 -28")
	t.ok(is_equal_approx(s.damage_duration, 0.6), "預設：傷害飄字 0.6s")

	# 參數有效：改字級/色後生成的 Label 跟著變（非瞬時模式才生飄字）。
	var fx := Node2D.new()
	s.setup(func(_c: Vector2i) -> Node: return null, fx,
		func(_c: Vector2i) -> Vector2: return Vector2(50, 50))
	s.instant = false
	s.damage_font_size = 33
	s.damage_color = Color(0, 0, 1)
	s._spawn_float(Vector2i(0, 0), 7)
	var l: Label = _first_of(fx, "Label")
	t.ok(l != null, "飄字：生成 Label")
	if l != null:
		t.eq(l.text, "-7", "飄字文字＝傷害值")
		t.eq(l.get_theme_font_size("font_size"), 33, "飄字字級吃 @export")
		t.ok(l.get_theme_color("font_color").is_equal_approx(Color(0, 0, 1)), "飄字顏色吃 @export")
		# P14-4 裁定：黑描邊沿用 theme 預設，不再逐節點 override。
		t.ok(not l.has_theme_color_override("font_outline_color"), "飄字不再逐節點覆寫描邊色")
	# 瞬時模式不生飄字（不變性）。
	s.instant = true
	var before: int = fx.get_child_count()
	s._spawn_float(Vector2i(0, 0), 7)
	t.eq(fx.get_child_count(), before, "瞬時模式：不生飄字")
	fx.free()
	s.free()


func _test_battle_shake_params(t: Object) -> void:
	var b: Node2D = BattleScene.instantiate()
	t.ok(is_equal_approx(b.shake_strength, 6.0), "預設：震動幅度 6")
	t.eq(b.shake_steps, 5, "預設：震動 5 步")
	t.ok(is_equal_approx(b.shake_step_time, 0.03), "預設：每步 0.03s")
	t.ok(is_equal_approx(b.shake_return_time, 0.04), "預設：歸位 0.04s")
	t.eq(b.res_float_font_size, 16, "預設：資源飄字字級 16")
	t.ok(b.res_float_offset.is_equal_approx(Vector2(150, 4)), "預設：資源飄字起始偏移")
	t.ok(is_equal_approx(b.res_float_slot_step, 22.0), "預設：資源飄字每筆下移 22")
	t.ok(is_equal_approx(b.res_float_rise, -26.0), "預設：資源飄字上飄 -26")
	t.ok(is_equal_approx(b.res_float_duration, 0.9), "預設：資源飄字 0.9s")
	# 瞬時模式不震（不變性）：_camera_shake 提前返回，不建立 tween、不改位置。
	b._bind_nodes()
	b._instant = true
	var pos: Vector2 = b.position
	b._camera_shake()
	t.ok(b.position.is_equal_approx(pos), "瞬時模式：擊殺不震鏡頭")
	b.free()


# anim_demo 骨架進 .tscn（P14-6），含可在 Inspector 調飄字的 CombatScheduler 節點。
func _test_anim_demo_skeleton(t: Object) -> void:
	var d: Node2D = AnimDemoScene.instantiate()
	for path: String in ["Background", "TitleLabel", "HelpLabel", "StatusLabel",
			"GridLayer", "BoardLayer", "FxLayer", "CombatScheduler"]:
		t.ok(d.get_node_or_null(path) != null, "anim_demo 骨架節點：" + path)
	var sched: Node = d.get_node_or_null("CombatScheduler")
	t.ok(sched != null and sched.get_script() != null, "anim_demo：CombatScheduler 已掛腳本")
	t.ok(sched != null and sched.damage_font_size == 18,
		"anim_demo：排程器參數可在 Inspector 調（預設 18）")
	t.ok(is_equal_approx(d.shake_strength, 6.0), "anim_demo 預設：震動幅度 6")
	d.free()


# 取容器內第一個指定型別的子節點（含後來新增的；找不到回 null）。
func _first_of(parent: Node, type_name: String) -> Variant:
	for c in parent.get_children():
		if c.is_class(type_name):
			return c
	return null
