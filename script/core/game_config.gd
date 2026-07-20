# P1-1 遊戲常數（鏡像 Python 硬編碼值，見 docs/rebuild/05 §2.3）。
# 這些數值 Python 寫死在程式裡（不在 JSON），調整時必須兩邊人工同步。
# 每個常數標明 Python 出處。
#
# P15-1（2026-07-20）：本檔只留「實際被引用」的常數。選秀與金幣上限另有各自的
# 權威定義處（見下方「他處定義」註），原本在此的重複副本已移除以免兩邊各改一半。
class_name GameConfig
extends RefCounted

const WIN_THRESHOLD_DEFAULT: int = 10   # game_state.py win_threshold
const HEAL_AMOUNT: int = 6              # player.py heal_card
const CUBES_PER_CARD: int = 2           # player.py play_card CUBES
const STARTER_HAND: int = 3             # player.py initialize
const P1_EXTRA_ATTACK: int = 1          # player.py initialize（先手補償）
const LUCK_INITIAL: int = 50            # game_state.py players_luck
const ANIM_LUNGE_STEP: float = 0.32     # shared/setting.py 撲擊節奏
const HIT_DELAY_RATIO: float = 0.55     # 命中延遲 = ANIM_LUNGE_STEP*0.55（01 §10）
const OVERHEAL_ARMOR_DIVISOR: int = 2   # cards/base.py heal 溢出轉盾
const BOARD_SIZE: int = 4               # config/setting.json board_size

# 他處定義（勿在此重複宣告，改值請改該處）：
#   牌組上限 12／同名單位 ≤2／同名魔法 ≤3 → DraftDispatcher.MAX_DECK/MAX_UNIT/MAX_MAGIC
#   金幣上限 50                          → CoinEngine.COIN_MAX

# 勝利門檻（爬塔突變可覆寫，故為實例變數）。
var win_threshold: int = WIN_THRESHOLD_DEFAULT
