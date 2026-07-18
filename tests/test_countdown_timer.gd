# P11-1 驗收：純邏輯倒數計時器（script/view/countdown_timer.gd）。
# 涵蓋：關閉時無作用、倒數、逾時恰觸發一次、剩餘/比例、重啟、秒數 ≤0 不啟動。
extends RefCounted


func run(t: Object) -> void:
	_test_disabled_never_fires(t)
	_test_zero_seconds_never_starts(t)
	_test_counts_down_and_fires_once(t)
	_test_fraction_and_remaining(t)
	_test_restart(t)
	_test_stop(t)


func _test_disabled_never_fires(t: Object) -> void:
	var c := CountdownTimer.new()
	c.configure(false, 10.0)
	c.start()
	t.ok(not c.running, "關閉：start 不啟動")
	var fired := false
	for _i in 100:
		if c.advance(1.0):
			fired = true
	t.ok(not fired, "關閉：advance 恆不觸發（關閉時無作用）")
	t.eq(c.remaining_seconds(), 0, "關閉：剩餘秒為 0")


func _test_zero_seconds_never_starts(t: Object) -> void:
	var c := CountdownTimer.new()
	c.configure(true, 0.0)
	c.start()
	t.ok(not c.running, "秒數 0：不啟動")
	t.ok(not c.advance(1.0), "秒數 0：advance 不觸發")


func _test_counts_down_and_fires_once(t: Object) -> void:
	var c := CountdownTimer.new()
	c.configure(true, 3.0)
	c.start()
	t.ok(c.running, "啟用且秒數>0：已啟動")
	t.ok(not c.advance(1.0), "1s 後未到點")
	t.ok(not c.advance(1.0), "2s 後未到點")
	t.ok(c.advance(1.5), "跨越 0 →觸發")
	t.ok(not c.running, "觸發後停止")
	t.ok(not c.advance(1.0), "觸發後再 advance 不重複觸發")


func _test_fraction_and_remaining(t: Object) -> void:
	var c := CountdownTimer.new()
	c.configure(true, 10.0)
	c.start()
	t.eq(c.remaining_seconds(), 10, "初始剩餘 10 秒")
	c.advance(4.0)
	t.ok(abs(c.fraction() - 0.6) < 0.0001, "剩 6/10 →fraction≈0.6")
	t.eq(c.remaining_seconds(), 6, "剩餘 6 秒")
	c.advance(5.2)   # 剩 0.8
	t.eq(c.remaining_seconds(), 1, "剩 0.8 秒→無條件進位為 1")


func _test_restart(t: Object) -> void:
	var c := CountdownTimer.new()
	c.configure(true, 5.0)
	c.start()
	c.advance(4.0)
	c.start()   # 重啟
	t.eq(c.remaining_seconds(), 5, "重啟後剩餘回到滿值")
	t.ok(c.running, "重啟後運行中")


func _test_stop(t: Object) -> void:
	var c := CountdownTimer.new()
	c.configure(true, 5.0)
	c.start()
	c.stop()
	t.ok(not c.running, "stop 後停止")
	t.ok(not c.advance(10.0), "stop 後 advance 不觸發")
