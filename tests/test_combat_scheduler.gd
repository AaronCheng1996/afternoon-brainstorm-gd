# P2-2 CombatScheduler + AnimationSet headless 驗收（動畫「觀感」由人工於編輯器跑 anim_demo.tscn 確認）。
# 這裡守可自動化的排程邏輯：依 delay 排序播放、is_busy 轉換、死亡待機、瞬時模式套用最終狀態。
extends RefCounted

const SchedulerScript := preload("res://script/view/combat_scheduler.gd")
const AnimSetScript := preload("res://script/view/piece_animation_set.gd")
const PieceViewScene := preload("res://scenes/battle/piece_view.tscn")   # P7-3：實例化場景

var _map: Dictionary = {}   # Vector2i -> view（供 _resolve 查詢，避免 inline lambda 捕獲疑慮）


# 記錄呼叫的假視圖（避免對未進場景樹的節點建 tween）。
class StubView extends RefCounted:
	var instant := false
	var log: Array = []
	var death_done: Callable = Callable()
	func play_attack(_target: Vector2, _fx: Node) -> void: log.append("attack")
	func play_hurt() -> void: log.append("hurt")
	func set_health_display(h: int) -> void: log.append("hp:%d" % h)
	func play_death(on_done: Callable) -> void:
		log.append("death")
		death_done = on_done
	func play_move(_to: Vector2) -> void: log.append("move")
	func play_cast() -> void: log.append("cast")
	func set_status(_id: String, _on: bool) -> void: log.append("status")
	func center_global() -> Vector2: return Vector2.ZERO
	func queue_free() -> void: log.append("freed")


func _resolve(pos: Vector2i) -> Object:
	return _map.get(pos, null)


func _cell(_pos: Vector2i) -> Vector2:
	return Vector2.ZERO


func run(t: Object) -> void:
	_test_animation_set(t)
	_test_timeline_order(t)
	_test_death_keeps_busy(t)
	_test_instant_terminal_state(t)


func _test_animation_set(t: Object) -> void:
	var fb := AnimSetScript.fallback()
	t.ok(not fb.has_projectile(), "fallback 為近戰（無投射物）")
	var ranged := AnimSetScript.adc_ranged()
	t.ok(ranged.has_projectile(), "adc_ranged 有投射物")
	t.ok(ranged.impact != null, "adc_ranged 有命中特效")
	# PieceView 未指定時退回 fallback。
	var db: Object = load("res://script/data/balance_db.gd").new()
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("ADCW", 1, db)
	t.ok(v._aset() != null, "PieceView 無 set 時退回 fallback")
	v.free()
	db.free()


func _test_timeline_order(t: Object) -> void:
	# ATTACK 動畫落在「攻擊者」（event.from）。三個 ATTACK：delay 0.0 / 0.32 / 0.64。
	var attacker := StubView.new()
	_map = {Vector2i(0, 0): attacker}
	var sched: Node = SchedulerScript.new()
	sched.instant = false
	sched.setup(Callable(self, "_resolve"), null, Callable(self, "_cell"))
	sched.play_events([
		GameEvent.attack(Vector2i(0, 0), Vector2i(1, 0), 0.0),
		GameEvent.attack(Vector2i(0, 0), Vector2i(1, 1), 0.32),
		GameEvent.attack(Vector2i(0, 0), Vector2i(1, 2), 0.64),
	])
	t.ok(sched.is_busy(), "播放中：忙碌")

	sched._advance(0.1)   # elapsed 0.1 → 只有 0.0 觸發
	t.eq(attacker.log.size(), 1, "第一次撲擊於 0.0")
	t.ok(sched.is_busy(), "仍忙碌（尚有兩次）")

	sched._advance(0.3)   # elapsed 0.4 → 0.32 觸發
	t.eq(attacker.log.size(), 2, "第二次撲擊於 0.32")

	sched._advance(0.3)   # elapsed 0.7 → 0.64 觸發，佇列清空
	t.eq(attacker.log.size(), 3, "第三次撲擊於 0.64")
	t.ok(not sched.is_busy(), "全部播完：不忙碌")
	sched.free()


func _test_death_keeps_busy(t: Object) -> void:
	var a := StubView.new()
	_map = {Vector2i(2, 2): a}
	var sched: Node = SchedulerScript.new()
	sched.instant = false
	sched.setup(Callable(self, "_resolve"), null, Callable(self, "_cell"))
	sched.play_events([
		GameEvent.hurt(Vector2i(2, 2), 0.1, 3),
		GameEvent.death(Vector2i(2, 2), 0.1),
	])
	sched._advance(0.2)   # hurt + death 觸發
	t.ok(a.log.has("hurt"), "受擊動畫已播")
	t.ok(a.log.has("hp:3"), "HP 標籤更新")
	t.ok(a.log.has("death"), "死亡動畫已起")
	t.ok(sched.is_busy(), "死亡動畫進行中：仍忙碌")
	a.death_done.call()   # 模擬淡出完成
	sched._advance(0.0)   # 收斂
	t.ok(not sched.is_busy(), "死亡完成後：不忙碌")
	t.ok(a.log.has("freed"), "死亡後視圖被釋放")
	a.death_done = Callable()   # 打斷 stub→death_done→closure→stub 的參考循環（真實 view 為 Node 不受影響）
	sched.free()


func _test_instant_terminal_state(t: Object) -> void:
	# 瞬時模式：play_events 後立即套用最終狀態、不忙碌。用真實 PieceView 驗 HP 標籤。
	var db: Object = load("res://script/data/balance_db.gd").new()
	var v: Node2D = PieceViewScene.instantiate()
	v.configure("TANKW", 2, db)
	_map = {Vector2i(0, 0): v}
	var sched: Node = SchedulerScript.new()
	sched.instant = true
	sched.setup(Callable(self, "_resolve"), null, Callable(self, "_cell"))
	sched.play_events([GameEvent.hurt(Vector2i(0, 0), 0.5, 7)])
	t.ok(not sched.is_busy(), "瞬時模式：play_events 後即不忙碌")
	t.eq(v.health_label.text, "7", "瞬時模式：HP 標籤直接更新為 7")
	v.free()
	sched.free()
	db.free()
	_map = {}   # 釋放對已釋放視圖的殘留參考
