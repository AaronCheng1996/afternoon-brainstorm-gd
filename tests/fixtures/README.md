# 測試素材（test fixtures）

只給 headless 測試用的素材，**不是遊戲資產**——遊戲執行期不會讀這裡。

- `ADCW.png`：P14-5 用的假棋子貼圖（64×32 純色，刻意非正方形以驗「等比縮放到長邊塞滿一格」）。
  `tests/test_art_slots.gd` 把 `PieceView.sprite_dir` 指到本目錄，藉此驗證
  「有圖→SpriteSlot 啟用、佔位形隱藏」的正向路徑，而**不會**動到真正的
  `res://img/piece/card/`（那裡放圖會改變遊戲外觀，違反「預設值＝現值」鐵則）。
