# P2-2 演出排程器：吃 core 的 GameEvent 陣列，依各事件 delay 排到時間軸播放。見 04 §7.3。
# core 不等待動畫；AI 靠 is_busy()（＝事件是否播完）決定何時出手（對齊 Python renderer_busy）。
# instant=true 時全部瞬時完成（動畫開關關閉），最終狀態與逐格播放一致。
# 位置→視圖以 resolver 解析；格→像素中心以 cell_to_global 解析（供攻擊瞄準/飄字定位）。
class_name CombatScheduler
extends Node

signal finished

# P14-6：傷害飄字的表現參數改 @export（**預設值＝改版前的常數**，畫面不變）。
# 註：本節點由 battle/anim_demo 於執行期 `.new()` 建立（非 .tscn 宣告），故編輯器 Inspector
# 看不到這幾項；要調手感就改這裡的預設值，或由呼叫端於 `setup()` 後指定。
# 之所以仍用 @export 而非 const：它們是「參數」不是「常數」，形式與其他表現層參數一致，
# 且日後若把排程器宣告進場景即可直接在編輯器調（見 11_美術指南.md）。
@export_group("傷害飄字")
## 字級與顏色。
@export var damage_font_size: int = 18
@export var damage_color: Color = Color(1.0, 0.5, 0.4)
## 相對命中格中心的起始偏移（像素）。
@export var damage_offset: Vector2 = Vector2(-8, -20)
## 上飄距離（像素，負值＝往上）與淡出時間（秒）。
@export var damage_rise: float = -28.0
@export var damage_duration: float = 0.6
@export_group("")

var instant: bool = false

# P9-2：擊殺回呼（鏡頭震動等）。DEATH 動畫起始時呼叫；瞬時模式（動畫關）不呼叫，維持結果不變。
var on_kill: Callable = Callable()

var _resolver: Callable = Callable()       # func(Vector2i) -> PieceView 或 null
var _cell_to_global: Callable = Callable()  # func(Vector2i) -> Vector2
var _fx_layer: Node = null

var _queue: Array = []          # Array[Dictionary]：{time:float, cb:Callable}
var _elapsed: float = 0.0
var _pending_anims: int = 0     # 進行中的長動畫（死亡淡出）
var _playing: bool = false


func setup(resolver: Callable, fx_layer: Node, cell_to_global: Callable = Callable()) -> void:
	_resolver = resolver
	_fx_layer = fx_layer
	_cell_to_global = cell_to_global


# 播放一批事件（通常來自 core.drain_events()）。
func play_events(events: Array) -> void:
	for e in events:
		_schedule(e)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] < b["time"])
	_elapsed = 0.0
	_playing = true
	# 瞬時模式，或本批無任何排程動畫（例如只含 SPAWN/RESOURCE 的「出牌」批——皆不進佇列）：
	# 立即結束並發 finished，不必等下一個 _process 幀。避免 net 模式的 _busy 旗標為了一個
	# 純資料批空等一幀（P12-19「busy 旗標未解除」假說的結構性防呆；死亡/攻擊等有佇列項者不受影響）。
	if instant or _queue.is_empty():
		_flush_all()


func is_busy() -> bool:
	return _playing and (not _queue.is_empty() or _pending_anims > 0)


func _process(delta: float) -> void:
	if not _playing or instant:
		return
	_advance(delta)


# 推進時間軸（_process 每幀呼叫；headless 測試可直接呼叫以模擬時間）。
func _advance(dt: float) -> void:
	if not _playing:
		return
	_elapsed += dt
	while not _queue.is_empty() and _queue[0]["time"] <= _elapsed:
		var item: Dictionary = _queue.pop_front()
		item["cb"].call()
	if _queue.is_empty() and _pending_anims == 0:
		_finish()


func _flush_all() -> void:
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		item["cb"].call()
	_finish()


func _finish() -> void:
	if not _playing:
		return
	_playing = false
	finished.emit()


func _schedule(e: GameEvent) -> void:
	match e.kind:
		GameEvent.Kind.ATTACK:
			var from: Vector2i = e.data["from"]
			var to: Vector2i = e.data["to"]
			_push(e.data.get("delay", 0.0), func() -> void:
				var av := _view(from)
				if av == null:
					return
				av.instant = instant
				av.play_attack(_center_of(to), _fx_layer))
		GameEvent.Kind.HURT:
			var at: Vector2i = e.data["at"]
			var post_health: int = e.data.get("post_health", 0)
			_push(e.data.get("delay", 0.0), func() -> void:
				var v := _view(at)
				if v == null:
					return
				v.instant = instant
				v.play_hurt()
				v.set_health_display(post_health))
		GameEvent.Kind.FLOAT:
			var at: Vector2i = e.data["at"]
			var amount: int = e.data.get("amount", 0)
			_push(e.data.get("delay", 0.0), func() -> void:
				_spawn_float(at, amount))
		GameEvent.Kind.DEATH:
			var at: Vector2i = e.data["at"]
			_push(e.data.get("delay", 0.0), func() -> void:
				var v := _view(at)
				if v == null:
					return
				v.instant = instant
				if not instant and on_kill.is_valid():
					on_kill.call()
				_pending_anims += 1
				v.play_death(func() -> void:
					_pending_anims -= 1
					if is_instance_valid(v):
						v.queue_free()))
		GameEvent.Kind.MOVE:
			var from: Vector2i = e.data["from"]
			var to: Vector2i = e.data["to"]
			_push(0.0, func() -> void:
				var v := _view(from)
				if v == null:
					return
				v.instant = instant
				v.play_move(_center_of(to)))
		GameEvent.Kind.CAST:
			var at: Vector2i = e.data["at"]
			_push(0.0, func() -> void:
				var v := _view(at)
				if v != null:
					v.instant = instant
					v.play_cast())
		GameEvent.Kind.STATUS:
			var at: Vector2i = e.data["at"]
			var sid: String = e.data.get("status_id", "")
			var on: bool = e.data.get("on", false)
			_push(0.0, func() -> void:
				var v := _view(at)
				if v != null:
					v.set_status(sid, on))
		_:
			pass   # SPAWN/RESOURCE 於對戰場景另處理


func _push(time: float, cb: Callable) -> void:
	_queue.append({"time": time, "cb": cb})


func _view(pos: Vector2i) -> Object:
	if not _resolver.is_valid():
		return null
	var v: Variant = _resolver.call(pos)
	if v == null or not is_instance_valid(v):
		return null
	return v


func _center_of(pos: Vector2i) -> Vector2:
	if _cell_to_global.is_valid():
		return _cell_to_global.call(pos)
	var v := _view(pos)
	return v.center_global() if v != null else Vector2.ZERO


func _spawn_float(at: Vector2i, amount: int) -> void:
	if instant or _fx_layer == null:
		return
	var l := Label.new()
	l.text = "-%d" % amount
	l.add_theme_font_size_override("font_size", damage_font_size)
	l.add_theme_color_override("font_color", damage_color)
	# 黑描邊沿用全域 theme 的 `Label/` 預設（同 P14-4「逐節點 override 與 theme 預設相同即刪」的裁定）。
	l.z_index = 100
	_fx_layer.add_child(l)
	l.global_position = _center_of(at) + damage_offset
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position",
		l.global_position + Vector2(0, damage_rise), damage_duration)
	tw.tween_property(l, "modulate:a", 0.0, damage_duration)
	tw.chain().tween_callback(l.queue_free)
