# P14-4 具名色取用助手。見 docs/rebuild/06 P14-4、08 §5.4、theme/色盤說明.md。
#
# 為什麼需要它：跨場景共用的語意色（先手紅/後手藍/頁籤選中黃）原本在 battle/scoreboard/
# end_game/draft/encyclopedia 各自硬編一份（P14-1 盤查：P1 紅 3 處、P2 藍 4 處、選中黃 4 處），
# 改一次要改五個檔。現在單一來源＝`theme/main_theme.tres` 的 `Global/colors/*`，
# 美術改一處全案生效。
#
# 為什麼不直接用 `Control.get_theme_color()`：對戰場景 root 是 **Node2D**（battle/draft/
# encyclopedia 皆是），Node2D 沒有 theme 查詢 API。本類改查 `ThemeDB.get_project_theme()`
# ——它就是 `project.godot` 的 `gui/theme/custom` 掛上去那顆，與 Control 繼承到的同一份。
#
# 純靜態、零狀態；查不到具名色時回傳呼叫端給的 fallback（headless 或未掛 theme 也不會崩）。
class_name UIPalette
extends RefCounted

# 具名色所在的 theme「型別」。用自訂型別（非 Button/Label 等內建型別）以免與控件樣式混淆。
const TYPE := "Global"

# 跨場景語意色的鍵名（避免各處打字串出錯）。
const PLAYER1 := "player1_accent"    # 先手 P1
const PLAYER2 := "player2_accent"    # 後手 P2
const TAB_SELECTED := "tab_selected"  # 頁籤/模式鈕的「目前選中」染色


# 取具名色；theme 未掛或無此鍵時回傳 fallback。
static func color(name: String, fallback: Color) -> Color:
	var th: Theme = ThemeDB.get_project_theme()
	if th != null and th.has_color(name, TYPE):
		return th.get_color(name, TYPE)
	return fallback


# 依玩家取其代表色（"player1"/"player2"）。盤面外框、記分板、統計表共用。
static func player_color(player_name: String) -> Color:
	if player_name == "player1":
		return color(PLAYER1, Color(0.95, 0.4, 0.4))
	return color(PLAYER2, Color(0.45, 0.6, 1.0))


# 頁籤/模式鈕的選中染色（未選中一律 Color.WHITE＝不染色）。
static func tab_tint(selected: bool) -> Color:
	return color(TAB_SELECTED, Color(1, 1, 0.6)) if selected else Color.WHITE
