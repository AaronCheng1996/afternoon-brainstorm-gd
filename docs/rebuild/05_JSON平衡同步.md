# 05 Python / Godot 雙版本平衡同步（JSON 方案）

> 使用者已拍板：兩版本用 JSON 溝通平衡數值。本文定義單一數值來源、同步機制與工作流。

## 1. 單一數值來源（canonical）

Canonical 檔案位於 **Python repo**（唯讀原則不衝突——平衡調整本來就是 Python 專案的日常改動，
由專案擁有者在 Python 側改；Godot 側只「拉取」）：

| 檔案 | 內容 | Godot 是否使用 |
|---|---|---|
| `config/card_setting.json` | 全卡牌 HP/ATK/能力數值 | ✅ 核心 |
| `config/job_dictionary.json` | 顏色代碼、RGB、職業攻擊模式 | ✅ 核心 |
| `config/campaign_setting.json` | AI 全部參數、關卡 buff、策略加成 | ✅ Phase 3 |
| `config/setting.json` | 棋盤大小、倒數秒數、token 門檻 | ✅（部分鍵） |
| `config/card_hints.json` | 卡牌提示文字（繁中） | ✅ 顯示用 |

## 2. Godot 側機制

### 2.1 同步腳本 `tools/sync_balance.ps1`

```
來源：..\AfternoonBrainstorming\FOS brainstorming\config\*.json（路徑可用參數覆蓋）
目的：data\balance\ 下同名檔案
動作：複製 5 個檔案 → 產生 data\balance\_meta.json：
      { "synced_at": ISO時間, "source_version": <Python shared/setting.py 的 VERSION 字串，
        用正則抓 'VERSION = "..."'>, "hash": 所有檔案內容串接的 SHA256 前 12 碼 }
```

只讀 Python repo、只寫 Godot repo。另提供 `--check` 模式：只比對 hash，
不一致時 exit 1（給 CI / 驗收用）。`data/balance/` **入版控**（Godot 專案必須開箱即跑）。

### 2.2 BalanceDB（autoload，`script_v2/data/balance_db.gd`）

- 啟動時載入 `data/balance/*.json`；任何缺檔/缺鍵 → `push_error` 並以醒目方式顯示（fail fast）。
- Schema 驗證（最低限度）：
  - card_setting：每色每職業必有 `health`、`damage`（int）；白名單外的鍵允許（能力參數）。
  - job_dictionary：`colors_dict`、`RGB_colors`、`attack_type_tags` 三鍵齊全。
  - campaign_setting：`thresholds/scoring/threat_model/heal/panic/ai_delay_ms/strategy_bonuses` 齊全。
- 查詢 API：
  `stats(card_id) -> {health, damage, ...}`、`param(card_id, key, default)`、
  `attack_types(job)`、`color_rgb(color)`、`ai(path)`（點路徑取 campaign 參數）、
  `data_version() -> String`（顯示在主選單角落與對戰畫面，例如 `bal 4.3.0.0 @a1b2c3d4e5f6`）。
- 卡牌 ID 規約與 Python 一致：`JOB + 色碼`（`ADCW`、`SPDKG`、`TANKC (+)` 的 `(+)` 只存在於手牌名，
  資料層一律 base id + upgrade flag）。

### 2.3 Python 硬編碼常數的鏡像

下列數值 Python 寫死在程式裡（不在 JSON）。Godot 集中放 `script_v2/core/game_config.gd`，
每個都加註解標明 Python 出處，**調整它們必須兩邊人工同步**：

| 常數 | 值 | Python 出處 |
|---|---|---|
| WIN_THRESHOLD | 10 | `game_state.py` |
| DECK_SIZE / MAX_UNIT_COPIES / MAX_MAGIC_COPIES | 12 / 2 / 3 | `draft_dispatcher.py` |
| HEAL_AMOUNT | 6 | `player.py` |
| CUBES_PER_CARD | 2 | `player.py` |
| STARTER_HAND / P1_EXTRA_ATTACK | 3 / 1 | `player.py initialize` |
| LUCK_INITIAL | 50 | `game_state.py` |
| COIN_CAP | 50 | `card_cyan.py` |
| ANIM_LUNGE_STEP | 0.32 | `shared/setting.py` |
| OVERHEAL_ARMOR_DIVISOR | 2 | `cards/base.py heal` |

（建議未來 Python 側把這些搬進 setting.json——已列入回報清單，不由本專案動手。）

## 3. 平衡調整工作流（給專案擁有者）

```
1. 改 Python repo 的 config/*.json（單一來源）
2. Python 端照常測試
3. 在 Godot repo 跑 tools/sync_balance.ps1
4. godot --headless -s tests/run_tests.gd   ← 卡牌測試全綠
5. 兩個 repo 各自 commit（Godot commit 訊息附上 balance hash）
```

版本歧異偵測：兩邊遊戲畫面都顯示資料版本字串；Godot 啟動時若 `_meta.json` 的
source_version 與已知不符只警告不阻擋（允許實驗）。

## 4. 明確不做（本輪）

- 不做 git submodule / symlink（Windows 權限與易用性問題）。
- 不做執行期跨 repo 直讀（匯出成品會斷）。
- 不動 Python 讀檔方式。
