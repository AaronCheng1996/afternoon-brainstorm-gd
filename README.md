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

## 架伺服器（連線版專用伺服器）

連線版＝**專用伺服器＋房間制**（D18）：一台常駐主機跑 headless 的 `script/net/server_main.gd`，
玩家用戶端連上開房/加房對戰（伺服器權威、手牌公開 D19、seed 不下發）。

- 最快啟動（本機驗證）：

  ```powershell
  & "<godot>\Godot_v4.7-stable_win64.exe" --headless --path "<專案根>" -s script/net/server_main.gd -- port=24242 max_rooms=16
  ```

- **Ubuntu 部署**（bash 啟動腳本＋systemd unit 範本＋`ufw allow 24242/udp`＋`server_config.json`）：
  見 [`deploy/README.md`](deploy/README.md)。預設埠 **24242/UDP**；對局結束 server 端存
  `user://replays/*.jsonl`（P11-2 格式）；斷線重連保留秒數 `seat_hold_seconds`（預設 60）。
- 用戶端內建預設位址（設定畫面「線上對戰」可改，存 `user://settings.json`）；版本閘保證新舊版不混連。
- 規格：[`docs/rebuild/10_連線版本.md`](docs/rebuild/10_連線版本.md)（§5 房間、§9 部署、§9.5 Steam 展望）。

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

## 美術協作（換美術不改程式）

**完整上手指南＝[`docs/rebuild/11_美術指南.md`](docs/rebuild/11_美術指南.md)**（Phase 14 產出）。三十秒版：

- **丟檔案即生效**：棋子圖 `img/piece/card/<card_id>.png`、棋盤底圖 `img/board/skin_ortho.png`／
  `skin_iso.png`、場景背景 `img/UI/bg/<場景名>.png`。**沒放檔案就維持現行的幾何佔位/純色背景**，
  可以一次換一張、中途畫面不會壞。各目錄內有 `README.md` 就近說明。
- **全域樣式**：`theme/main_theme.tres`（色盤、字級、按鈕樣式）＋三個具名色
  （先手紅/後手藍/頁籤選中黃），改一處全案生效；細節見 `theme/色盤說明.md`。
- **元件長相**：手牌鈕、卡片列、房間列等抽成 `scenes/**/[名稱].tscn` **item 模板場景**（無腳本）。
- **棋盤位置/格距**：拖 `battle.tscn` 的 `BoardAnchorOrtho`／`BoardAnchorIso`，格線/棋子/高亮整組隨動。
- **特效手感**：`piece_view.tscn`／`projectile.tscn`／`impact_flash.tscn`／`battle.tscn` 的
  「特效：*」@export 群組。
- **預覽**：`scenes/battle/piece_gallery.tscn`（全棋子一覽，S 切貼圖/佔位）與
  `scenes/battle/anim_demo.tscn`（攻擊演出，空白鍵重播、I 切瞬時），編輯器按 **F6** 執行。
- **禁區**：`%` 場景唯一名稱不可改名/刪除、容器結構不可重組、`script/core` 不可動、
  派別色不可硬編（一律 `Balance.color_rgb`）。詳見指南 §7。

---

## 文件

`docs/rebuild/`：`00_總覽`（目標/鐵則/重大決策）、`01_遊戲規則規格`、`02_卡牌能力總表`、`03_CPU_AI規格`、`04_架構設計`、`05_JSON平衡同步`、`06_任務清單`（主執行清單）、`07_爬塔模式與新功能`、`08_場景編輯器化`、**`09_程式碼導覽`（每個檔案的職責說明，review 入口）**、**`10_連線版本`（Phase 12 規格定稿）**、**`11_美術指南`（美術接手入口，Phase 14 產出）**、`歸檔_已完成任務`、`進度日誌`。（`驗收_*.md` 為 Phase 2 時期的歷史檢查表；現行人工驗收清單在 `06`「人工協作待辦」。）
