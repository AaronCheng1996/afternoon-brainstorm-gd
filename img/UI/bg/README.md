# 場景背景圖插槽（P14-5）

把背景圖丟進**本目錄**即生效，不需要改任何程式。檔名＝場景名，副檔名 `.png`：

| 檔名 | 蓋住的畫面 |
|---|---|
| `main_menu.png` | 主選單 |
| `draft.png` | 選秀（BP） |
| `battle.png` | 對戰 |
| `end_game.png` | 終局統計 |
| `encyclopedia.png` | 百科圖鑑 |
| `online_lobby.png` | 線上大廳／房間 |

- 有圖 → 該場景的 `BackgroundImage`(TextureRect) 自動填圖並顯示，蓋在純色 `Background` 之上。
- 沒圖 → 維持 `.tscn` 裡的純色 `Background`（**本目錄空著時外觀與放圖前完全相同**）。
- 縮放模式預設為「保持長寬比並填滿」（超出的部分裁掉）。要改成拉伸或平鋪，
  直接在編輯器選該場景的 `BackgroundImage` 改 Stretch Mode 即可。
- 基準解析度 1024×768；圖請以此比例製作，其他解析度由 `canvas_items` stretch 處理。

棋盤底圖（俯視／45 度各一張）放在 `img/board/`：`skin_ortho.png`、`skin_iso.png`。
