# P9-3 攻擊演出資料庫：依卡牌職業的攻擊模式（Balance.attack_types）決定佔位攻擊演出——
# 遠程（大範圍/最遠打擊）發射投射物並於命中點播特效；近戰直接撲擊。特效以派別色上色。
# 純表現層、零 Node 依賴（RefCounted、只讀 Balance 查詢 API），可 headless 測。
# 換美術：日後放 data/animation_sets/<card_id>.tres 覆寫（PieceAnimationSet），本庫僅為佔位預設。
class_name PieceAnimationLibrary
extends RefCounted

const AnimSetScript := preload("res://script/view/piece_animation_set.gd")
const ProjectileScene := preload("res://scenes/battle/projectile.tscn")
const ImpactScene := preload("res://scenes/battle/impact_flash.tscn")

# 攻擊模式標籤中代表「遠程」（能打到非相鄰格）的 tag。含其一即視為遠程 → 投射物演出。
# 對照 job_dictionary.attack_type_tags：ADC=large_cross、SP=farthest 為遠程；其餘（nearest/
# small_cross/small_x/nearby）為近戰。與規則無關，純決定「箭矢 vs 撲擊」的表現。
const RANGED_TAGS := ["large_cross", "large_x", "farthest", "far"]

# 特效預設色（無派別色的卡：CUBE/LUCKYBLOCK…）。
# P14-6 裁定「保留為 const，不改 @export」：本類是**純靜態函式庫**（無實例、非 Node、不進場景樹），
# @export 無處可掛、Inspector 也顯示不出來。真正給美術調的入口是**每張卡的**
# `PieceAnimationSet.fx_color`（已是 @export 的 Resource 欄位）；這裡只是「該卡查不到派別色」
# 時的最後退路，要改預設就改這一行。
const DEFAULT_FX := Color(0.95, 0.92, 0.7)


# 取某卡的佔位攻擊演出集（每次建新的輕量 Resource，隨持有它的 PieceView 一同釋放；不做靜態快取
# 以免持有 Resource 參考至行程結束）。db 為 BalanceDB（預設 autoload Balance）。
static func for_card(card_id: String, db: Object = null) -> PieceAnimationSet:
	var data: Object = db if db != null else Balance
	var aset: PieceAnimationSet = AnimSetScript.new()
	aset.fx_color = _faction_color(card_id, data)
	aset.impact = ImpactScene            # 近戰/遠程命中皆播派別色命中特效
	if is_ranged(card_id, data):
		aset.projectile = ProjectileScene   # 遠程另發射投射物
	return aset


# 該卡是否為遠程攻擊（依攻擊模式 tag）。
static func is_ranged(card_id: String, db: Object = null) -> bool:
	var data: Object = db if db != null else Balance
	var job: String = data.job_of(card_id)
	if job == "":
		return false
	var tags: String = data.attack_types(job)
	for tok: String in tags.split(" ", false):
		if tok in RANGED_TAGS:
			return true
	return false


# 派別色（供投射物/命中特效上色）。無色碼的卡回預設色。
static func _faction_color(card_id: String, db: Object) -> Color:
	var code: String = db.color_code_of(card_id)
	if code == "":
		return DEFAULT_FX
	return db.color_rgb(code)
