# P15-5 連線測試共用匯流排（test util，**不是**測試檔——檔名不以 `test_` 開頭，
# 故 `run_tests.gd` 的探索不會撿到它）。
#
# 由來：同程序 `_Bus` 原本在 13 個 net 測試檔各有一份**功能完全相同**的內嵌副本
# （唯一差異是 test_net_transport 那份在 `nodes` 上多一行註解）。此處收斂為單一定義。
#
# 用途：headless 測試無法跑 @rpc-over-ENet（`-s` harness 沒有運行樹、不建實際連線，
# 見各 net 測試檔頭註），因此改用「同程序匯流排」——把 NetPeerBase 子類的 `_transmit`
# 改接到本類的 `route`，直接把封包字串交給對端的 `_ingest`。傳輸層以外的協定邏輯
# （編解碼、握手版本閘、房間狀態機、席位權威、廣播扇出）都能忠實驗證。
#
# 用法：
#   const NetTestBus := preload("res://tests/net_test_bus.gd")
#   class _WiredServer extends NetGameServer:
#       var bus: NetTestBus
#       func _transmit(peer_id: int, text: String) -> void:
#           bus.route(SERVER_ID, peer_id, text)
extends RefCounted

var nodes: Dictionary = {}   # peer_id -> NetPeerBase 子類實例


func add(id: int, node: Object) -> void:
	nodes[id] = node


# 把 from_id 送出的封包交給 to_id 的 `_ingest`（對端不存在＝靜默丟棄，等同封包遺失）。
func route(from_id: int, to_id: int, text: String) -> void:
	var target: Object = nodes.get(to_id, null)
	if target != null:
		target._ingest(from_id, text)
