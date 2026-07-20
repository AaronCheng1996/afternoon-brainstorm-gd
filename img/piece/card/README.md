# 棋子貼圖插槽（P14-5）

把棋子圖丟進**本目錄**即生效，不需要改任何程式。

- 檔名＝**卡牌 ID**，副檔名 `.png`，例如 `ADCW.png`、`TANKBR.png`、`CUBE.png`、`LUCKYBLOCK.png`。
  卡牌 ID 一覽可在遊戲內「百科圖鑑」或 `data/balance/card_setting.json` 查到。
- 有圖 → `PieceView` 顯示貼圖，幾何佔位形與外框環自動隱藏。
- 沒圖 → 維持現行幾何佔位形（fallback），**本目錄空著時遊戲外觀與放圖前完全相同**。
- 貼圖預設會**等比縮放到剛好塞滿一格**（96px）。想照原尺寸顯示，就把 `piece_view.tscn`
  根節點的「美術素材 → Sprite Fit Cell」取消勾選。
- 鏡像棋子（SHADOW，Fuchsia 的分身）沿用**本體職業**的貼圖，並自動套半透明。

預覽方式：在編輯器開 `scenes/battle/piece_gallery.tscn` 按 F6——全部棋子一覽，
副標題會顯示「貼圖 n / 全部 m」，按 **S** 可在「貼圖／幾何佔位」之間切換對照。

路徑慣例的裁定理由見 `docs/rebuild/08_場景編輯器化.md` §5.5。
