# 午後激盪（Afternoon Brainstorming）— Godot 重構版

Godot 4.7 重構版。**平衡數值與規則行為**以 Python 原版為唯一基準；
**美術與 UI** 自 2026-07-11 起與原版脫鉤、以 Godot 版易用性優先自由設計（決策 D16）。
原版（規則基準）：<https://github.com/RobinLiu69/AfternoonBrainstorming>

4×4 棋盤卡牌對戰：出牌佈署棋子、攻擊、移動、治療、放方塊，每回合結算計分，任一方分數絕對值達門檻（預設 ±10）即勝。

---

## 現況與路線

**已交付**（2026-07-16，1817 個 headless 測試全綠）：

- **本機雙人**（主選單 → 選秀 BP → 對戰 → 終局統計）＋**單人 vs CPU**（白/紅/藍/綠/橙/Boss 六關卡 AI）。
- **回放**：對局自動錄 JSONL（`user://replays/`），終局/主選單可重播（單步/倍速）。
- 體驗：多分辨率、全域 Theme、卡牌關鍵字高亮＋懸停解釋、**百科圖鑑**、記分板、
  終局統計圖表、**45°/俯視雙視角棋盤**（V 鍵切換）、命中/死亡演出、BP 與回合計時器（設定可開）。
- 10 色 × 8 職業全卡牌＋特殊卡/衍生物（能力系統，含沉默/附魔）；佔位美術＋動畫插槽（換圖不改程式）。
- 平衡數值以 JSON 為單一來源，由 Python 原版同步。

**進行中：Phase 12 連線版本**（規格：`docs/rebuild/10_連線版本.md`）——
專用伺服器＋房間制（開房邀請、公開/上鎖、旁觀），伺服器權威、手牌公開（D19）。
另有 P9-4 UI 美術優化（使用者帶方向的持續型）。爬塔（Phase 13）擱置中。

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
                    ability/  能力系統（trigger 全表、沉默/附魔）
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
核心只吃 `GameAction`、吐 `GameEvent` 陣列 + 可查詢狀態；場景層訂閱事件播動畫，靠事件是否清空判斷是否可再操作。

## 換美術（不改程式）

佔位視覺集中在 `scenes/battle/piece_view.gd`（`PieceView`）：

- 每棋子有 `VisualRoot/SpriteSlot`（`Sprite2D`）動畫插槽，目前隱藏、以 `PlaceholderShape`（Polygon2D）＋文字佔位。
- 到位美術：填 `SpriteSlot` 並隱藏 `PlaceholderShape` 即可；每張卡可在 `PieceAnimationSet` 指定待機/攻擊/投射物/命中/受擊/死亡/施法，沒指定的自動用 fallback。
- 換圖不動規則核心與場景輸入流程。

---

## 文件

`docs/rebuild/`：`00_總覽`（目標/鐵則/重大決策）、`01_遊戲規則規格`、`02_卡牌能力總表`、`03_CPU_AI規格`、`04_架構設計`、`05_JSON平衡同步`、`06_任務清單`（主執行清單）、`07_爬塔模式與新功能`、`08_場景編輯器化`、**`09_程式碼導覽`（每個檔案的職責說明，review 入口）**、**`10_連線版本`（Phase 12 規格定稿）**、`歸檔_已完成任務`、`進度日誌`。（`驗收_*.md` 為 Phase 2 時期的歷史檢查表；現行人工驗收清單在 `06`「人工協作待辦」。）
