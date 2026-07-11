# P2-2 棋子動作插槽集（可擴充）。見 04 §7.2。
# 每張卡之後可在 data/animation_sets/<card_id>.tres 指定自己的 set 覆寫佔位動畫——換圖不改程式。
# 目前 proc 名對應 PieceView 內建的 fallback 程序動畫；projectile/impact 為可選投射物與命中特效場景。
class_name PieceAnimationSet
extends Resource

# 動作程序名（PieceView 解讀）：待機/準備/攻擊/被擊/死亡/施法。
@export var idle_proc: String = "breathe"
@export var ready_proc: String = "lean"
@export var attack_proc: String = "lunge"
@export var hurt_proc: String = "flash_shake"
@export var death_proc: String = "fade_shrink"
@export var cast_proc: String = "pulse_ring"

# 撲擊/命中節奏（對齊 R §10：0.32s 一步、命中在 0.55 比例）。
@export var lunge_step: float = 0.32
@export var hit_ratio: float = 0.55

# 遠程攻擊插槽：非 null 時改為發射投射物並在命中點播放特效（近戰為 null＝直接撲擊）。
@export var projectile: PackedScene = null
@export var impact: PackedScene = null

# 未來擴充（"victory"/"taunt"…）。
@export var extra: Dictionary = {}


# 全棋子共用的預設 fallback（近戰撲擊、無投射物）。
static func fallback() -> PieceAnimationSet:
	return PieceAnimationSet.new()


# ADC 遠程示範：三角形箭矢投射物 + 命中閃光（驗證投射物/特效插槽可用）。
static func adc_ranged() -> PieceAnimationSet:
	var s := PieceAnimationSet.new()
	s.projectile = load("res://scenes/battle/projectile.tscn")
	s.impact = load("res://scenes/battle/impact_flash.tscn")
	return s


func has_projectile() -> bool:
	return projectile != null
