# P0-1 測試 runner
# 用法：godot --headless --path <專案根> -s tests/run_tests.gd
# 掃描 tests/ 下所有 test_*.gd，逐一實例化並呼叫 run(t)。
# t 為斷言工具（見內嵌 TestContext），統計結果；有任一失敗則 exit 1。
extends SceneTree


# 傳給每個測試的斷言工具。
class TestContext extends RefCounted:
	var passed: int = 0
	var failed: int = 0
	var failures: Array[String] = []
	var _current: String = ""

	# 相等斷言。
	func eq(a: Variant, b: Variant, msg: String = "") -> void:
		if a == b:
			passed += 1
		else:
			failed += 1
			failures.append("%s | %s：期望 %s == %s" % [_current, msg, str(a), str(b)])

	# 布林斷言。
	func ok(cond: bool, msg: String = "") -> void:
		if cond:
			passed += 1
		else:
			failed += 1
			failures.append("%s | %s：期望為真" % [_current, msg])

	# 直接判定失敗（例外或不可到達分支）。
	func fail(msg: String = "") -> void:
		failed += 1
		failures.append("%s | %s" % [_current, msg])


func _initialize() -> void:
	var ctx := TestContext.new()
	var files := _discover_tests()
	files.sort()
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			ctx._current = path
			ctx.fail("無法載入測試檔")
			continue
		var inst: Object = script.new()
		ctx._current = path.get_file()
		if not inst.has_method("run"):
			push_warning("略過（無 run 方法）: " + path)
			continue
		inst.run(ctx)
	_report(ctx)
	quit(1 if ctx.failed > 0 else 0)


# 找出 tests/ 下的 test_*.gd（不含本 runner）。
func _discover_tests() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir == null:
		push_error("找不到 res://tests 目錄")
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			result.append("res://tests/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	return result


func _report(ctx: TestContext) -> void:
	print("")
	for f in ctx.failures:
		print("  FAIL  ", f)
	if ctx.failed == 0:
		print("%d passed" % ctx.passed)
	else:
		print("%d passed, %d failed" % [ctx.passed, ctx.failed])
