# P11-1 純邏輯倒數計時器（RefCounted，零 Node 依賴、可 headless 測）。
# 表現層（draft/battle）持有一個，每幀以 `advance(delta)` 推進；到點時 advance 回傳 true 恰一次。
# 關閉（enabled=false）或秒數 ≤0 時：start 不啟動、advance 恆回 false（「關閉時無作用」）。
class_name CountdownTimer
extends RefCounted

var enabled: bool = false
var limit: float = 0.0        # 秒
var remaining: float = 0.0
var running: bool = false


# 設定啟用與秒數（不自動啟動；需再呼叫 start）。
func configure(is_enabled: bool, seconds: float) -> void:
	enabled = is_enabled
	limit = maxf(0.0, seconds)


# 開始一輪倒數。關閉或秒數 ≤0 時不啟動（running 保持 false）。
func start() -> void:
	if enabled and limit > 0.0:
		remaining = limit
		running = true
	else:
		running = false
		remaining = 0.0


func stop() -> void:
	running = false


# 推進 delta 秒；跨越 0 的那一次回傳 true（並停止），其餘回傳 false。
func advance(delta: float) -> bool:
	if not running:
		return false
	remaining -= delta
	if remaining <= 0.0:
		remaining = 0.0
		running = false
		return true
	return false


# 剩餘比例（0..1，供進度條/顯示）。未啟動或無限制時回 0。
func fraction() -> float:
	if limit <= 0.0 or not running:
		return 0.0
	return clampf(remaining / limit, 0.0, 1.0)


# 剩餘整數秒（無條件進位，顯示用；如 0.2 秒仍顯示 1）。
func remaining_seconds() -> int:
	return int(ceil(remaining)) if running else 0
