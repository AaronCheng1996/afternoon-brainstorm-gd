# P0-1 自證測試：確認 runner 能載入並執行測試。
extends RefCounted


func run(t: Object) -> void:
	t.eq(1 + 1, 2, "1+1 應為 2")
