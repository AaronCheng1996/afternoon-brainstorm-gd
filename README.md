# 午後激盪（Afternoon Brainstorming）— Godot 重構版

Godot 4.7 重構版，規則以 Python 原版為唯一基準。
原版（規則基準）：<https://github.com/RobinLiu69/AfternoonBrainstorming>

4×4 棋盤卡牌對戰：出牌佈署棋子、攻擊、移動、治療、放方塊，每回合結算計分，任一方分數絕對值達門檻（預設 ±10）即勝。

---

## 目前範圍（本輪交付）

**本機雙人（hot-seat）**：主選單 → 選秀 BP → 對戰 → 終局統計 → 回選單。

- 10 色 × 8 職業全卡牌 + 特殊卡/衍生物（能力系統 v2，含沉默/附魔）。
- 佔位美術（幾何圖形＋文字）＋動畫插槽（待機/攻擊/投射物/受擊/死亡/施法）。
- 平衡數值以 JSON 為單一來源，由 Python 原版同步。

**後續（尚未做）**：CPU AI（Phase 3，延後）、戰役模式（已移除，教學改由爬塔承擔）、爬塔 endless（Phase 5，擱置）。詳見 `docs/rebuild/`。

---

## 執行

需要 Godot **4.7 stable**。

- 直接開專案執行：入口場景為 `scenes/menu/main_menu.tscn`。
- 或在編輯器對任一場景按 **F6** 單獨執行：
  - `scenes/menu/main_menu.tscn`　主選單（完整流程入口）
  - `scenes/draft/draft.tscn`　　　選秀 BP
  - `scenes/battle/battle.tscn`　　對戰（預設牌組）
  - `scenes/battle/piece_gallery.tscn`　棋子佔位美術一覽
  - `scenes/battle/anim_demo.tscn`　攻擊演出示範

## 測試（headless）

零外部依賴的自製 runner，掃 `tests/test_*.gd` 逐一執行：

```powershell
& "<godot>\Godot_v4.7-stable_win64.exe" --headless --path "<專案根>" -s tests/run_tests.gd
```

- 輸出 `NNN passed`、全綠時 exit 0；有失敗 exit 1。
- 新增含 `class_name` 的檔案後，headless 需先跑一次 `--headless --import` 重建 global class 快取，runner 才認得（`.godot/` 為 gitignore 快取）。

## 平衡同步（Python → Godot）

平衡數值 canonical 在 Python 原版 `config/*.json`，**單向**複製到本專案 `data/balance/`：

```powershell
tools/sync_balance.ps1            # 預設來源 ..\AfternoonBrainstorming\FOS brainstorming\config
tools/sync_balance.ps1 -Check     # 只檢查是否一致（未變 exit 0）
```

產生 `data/balance/_meta.json`（來源版本 + hash）。載入時由 `Balance`（autoload `script/data/balance_db.gd`）驗 schema 並提供查詢。

---

## 架構（Sim / View 分離）

```
script/core/     純規則核心（RefCounted，零 Node 依賴）
                    game_core / combat / turn_engine / piece_state / ...
                    ability/  能力系統 v2（trigger 全表、沉默/附魔）
                    faction 引擎：token / luck / totem / coin / shadow
                    draft_*   選秀 BP 邏輯
script/data/     balance_db.gd（autoload Balance）、settings_store.gd
script/view/     piece_animation_set / combat_scheduler（表現層協定）
scenes/          menu / draft / battle / end_game 場景（Node 世界）
data/balance/       由 Python 同步來的平衡 JSON
data/card_text.json 顯示名/描述/提示
tests/              headless 測試（翻譯自 Python tests/）
tools/              sync_balance.ps1 等
docs/rebuild/       重構規劃與規格（00 總覽起）
```

**鐵律**：`script/core` 不得 `extends Node` / `get_tree()` / `load("res://scenes...")`。
核心只吃 `GameAction`、吐 `GameEventV2` 陣列 + 可查詢狀態；場景層訂閱事件播動畫，靠事件是否清空判斷是否可再操作。

## 換美術（不改程式）

佔位視覺集中在 `scenes/battle/piece_view.gd`（`PieceViewV2`）：

- 每棋子有 `VisualRoot/SpriteSlot`（`Sprite2D`）動畫插槽，目前隱藏、以 `PlaceholderShape`（Polygon2D）＋文字佔位。
- 到位美術：填 `SpriteSlot` 並隱藏 `PlaceholderShape` 即可；每張卡可在 `PieceAnimationSet` 指定待機/攻擊/投射物/命中/受擊/死亡/施法，沒指定的自動用 fallback。
- 換圖不動規則核心與場景輸入流程。

---

## 文件

`docs/rebuild/`：`00_總覽`（目標/鐵則/重大決策）、`01_遊戲規則規格`、`02_卡牌能力總表`、`03_CPU_AI規格`、`04_架構設計`、`05_JSON平衡同步`、`06_任務清單`（主執行清單）、`07_爬塔模式與新功能`。人工驗收檢查表：`驗收_對戰.md`、`驗收_BP.md`、`驗收_選單流程.md`。
