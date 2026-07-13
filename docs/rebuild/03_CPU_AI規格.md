# 03 CPU AI 規格（Python `campaign/` 為準）

> CPU 是「評分式貪婪 AI + 各關卡加權策略」，不搜尋（唯一例外：claude 策略做 beam search）。
> 所有可調參數集中在 `config/campaign_setting.json`（會同步到 Godot `data/balance/`）。
> 出處：`campaign/ai_controller.py`、`ai_evaluator.py`、`ai_query.py`、`ai_strategies/*`。

## 1. 控制器（AIController）— 行為節奏與決策優先序

AI 扮演 player2，每幀 `tick(now_ms)` 被呼叫，回傳 0 或 1 個 GameAction。

**節奏（ms，campaign_setting.json `ai_delay_ms`）**：
回合開始等 900；一般行動間隔 650；攻擊間隔 500；
若場上還有未播完的戰鬥事件 / 攻擊佇列 / 渲染忙碌 → 每 120ms 重新檢查（AI 會等動畫播完才出手）。

**每回合初始化順序**：
1. 首次 tick：套用關卡 one-shot buff（如 green 關初始運氣 65）與初始手牌 buff（boss 關起手 4 張）。
2. 持續維護：`maintain_unit_buffs`——boss 關 AI 每個新上場單位 +1 HP（記 instance_id 防重複）。
3. AI 回合的第一個 tick：套用 per-turn buff（orange 關每 3 回合 +1 移動、boss 關每 5 回合 +1 治療），
   然後等 900ms 才開始出招。

**單步決策 `_decide_next()`（嚴格優先序）**：

```
0. 有掛起的「升級打出」二段動作 → 完成它（見 §5 Cyan 流程）
1. 有 moving 中的棋子 → 幫它選最佳目的地（score_move_destination 最高者）→ move_to
2. number_of_movings > 0 且無人 moving → 選「最佳目的地分數 > 0」的最佳棋子 → 先點它啟動移動
3. 手牌有 MOVEO 且存在可移動棋子 → 打出 MOVEO（board 參數隨便，效果是 movings+1）
4. attack = strategy.best_attack()；play = strategy.best_placement()
5. 若 attack.score >= 100（斬殺線 lethal_score_threshold）→ 立刻攻擊
6. heal = _best_heal()；若有 → 治療
7. 若 play.score >= placement_min_score(=1.0) → （Cyan 可能先 toggle_upgrade，見 §5）→ 打出
8. 若 attack.score >= 有效攻擊門檻（見下）→ 攻擊
9. 什麼都不做 → end_turn
```

**有效攻擊門檻（panic 機制）**：
基礎門檻 = 策略的 `attack_min_score`（預設 15；faction_overrides：white 10、red 12、blue 13、orange 12、boss 13）。
落後分 deficit = 對手領先的分數；deficit > 2 時：門檻 = max(8, 基礎 − (deficit−2)×3.5)。
→ 越落後越敢換血。

**AI 目標圈顯示**：當前執行 play_card/attack 的格子畫黃圈（表現層需求）。

## 2. 幾何查詢層（ai_query，全部是純函式）

- `position_safety(x,y)`：角落 3.0、邊 2.0、中央 1.0。
- `attack_targets_from_pos(owner,x,y,attack_types)`：假想從 (x,y) 用該模式能打到哪些目標
  （nearest/farthest 取「並列全部」而非隨機一個——評分用寬鬆版）。
- `attacker_would_hit_position(attacker, tx,ty, ...)`：敵單位能否打到某格
  （nearest/farthest 的判定：假想目標距離 ≤/≥ 我方現有棋子的最小/最大距離則算會被打到）。
- `incoming_damage_at_position(owner,x,y,min_attacks=0)`：
  對手（非 numbness）所有能打到該格的單位傷害由大到小取前 `max(min_attacks, 對手攻擊次數)` 個加總。
- `projected_incoming_damage`：同上但至少假設對手有 1 次攻擊。
- `cells_threatening_card(card)`：若 5 − card.armor ≥ card.health（ASS_THREAT_DAMAGE=5），
  回傳能斜角威脅到它的空格清單（給防禦性佈署用）。
- `move_destinations_for(card)`：8 鄰內的空格。
- `attack_coverage_cells(x,y,types)`：該模式在該位置覆蓋的格數（reach 用）。

## 3. 佈署評分 evaluate_placement(card_name, (x,y))

基礎分 = `HP×0.5 + ATK×1.5`，然後逐項加：

| 項目 | 公式 / 條件 |
|---|---|
| 位置安全 | safety × 職業係數：SP×4、TANK/HF×1、ASS×0.5、其他×2 |
| 距離修正 | ASS/LF 距敵 ≤2 → +2；TANK/HF 距敵 ≤1 → +3；SP 距敵 ≤2 → **−5** |
| 斬殺佈署 | 僅 ASS（入場先攻）：從該位置能殺掉的最佳目標 → +100 +目標ATK×10 +目標得分力×8 +(ADC/SP 目標再+5)；怒氣中的 HFR 視為殺不掉 |
| 防禦佈署 | 佔住「能威脅我方脆皮的空格」：每保住一隻 → +該友方 ATK×6 + HP×1.5 |
| 威脅投射 | 從該位置可打到的目標：Σ(min(ATK,目標HP)×0.3 + 目標ATK×0.5)；非入場攻擊職業再 ×0.6 |
| 被打風險 | 該格預估承傷 ≥ 自身 HP → −30；否則 −承傷×1.5 |
| 手牌保留 | 打出 ASS 本身 −20（hand_threat_value，ASS 留手上當威脅比較值錢） |
| 得分潛力 | 每回合預估得分 ×8（一般卡 1 分、SPW 2 分、方塊類 0） |
| 覆蓋範圍 | 可打到的格數 × 0.8 |
| 怕刺客 | 若 HP ≤5：周圍空的斜角格數 ×(3 + 每回合得分×1.5) 扣分 |
| 保護需求 | ADC/AP/SP：我方有 HP>5 的前排 → +4；沒有 → **−12** |

無效位置（出界/被佔）= −1000。

## 4. 攻擊評分 evaluate_attack(attacker)

麻痺中 / APTG（不攻擊卡）→ 直接 −1（不出手）。對每個可命中目標算分，取最高；
若攻擊模式是**確定性 AOE**（僅由 small_cross/small_x/large_cross 組成）→ 所有目標分數加總與單體最高取大者。

單目標分數：

```
有效傷害 = 我ATK + extra_damage
目標護盾 >= 有效傷害        → +5（磨盾）
能斬殺（HP <= 有效傷害−護盾，且非怒氣不死身） → +100 + 目標ATK×10 + 目標得分力×8
否則（削血）                → +min(有效傷害,目標HP)×2
                              + 補刀獎勵：若我方還有第二次攻擊且另一單位能收頭 → +15+目標ATK×2
                              + 若無補刀且自己不是必死之身 → −18（浪費削血懲罰）
共通： +目標ATK×3；目標是 ADC/SP → +5
反殺風險：目標ATK ≥ 我HP 且目標非麻痺（且我非不死/非必死）→ −50
目標已麻痺 → −20
```

「必死之身 attacker_doomed」：我站位的預估承傷（至少算對手 1 刀）≥ 我 HP → 反正要死，衝了。

## 5. 特殊流程

**治療 `_best_heal()`**（number_of_heals>0 時）：對每個我方棋子算
`實際回量×2 + 得分力×4 + ATK×1.5 +（HP 比例<0.4 → +10）+（這口奶能保命 → +30+ATK×3）`，
超過門檻 12 才治療（實際回量 <3 不考慮）。

**移動目的地評分 score_move_destination(card, dest)**：
- ADCO：Σ min(ATK,目標HP)×2（追殺位）
- LFO：6 − 最近敵人距離（貼臉）
- HFO：safety + 可打目標數×(ATK+extra+1)×0.6
- ASSO：能殺 → 20+目標ATK×2；否則 目標數×2
- 其他：目標數×1.5

**Cyan 升級二段流程**：想打出的卡是 Cyan 且未標 `(+)`、金幣 ≥ 價格（cost − 2×已升級SPC 數）
→ 先發 `toggle_upgrade`，下一步把記住的 (hand_index,x,y) 打出；若中途格子被佔 → 再 toggle 回來。

## 6. 各關卡策略（Strategy 子類，加成常數在 campaign_setting.json `strategy_bonuses`）

**基底 Strategy**：`best_placement` = 對每張可打手牌 × 每個空格跑 §3 再加 `placement_bonus`；
`best_attack` = 對每個我方棋子跑 §4 再加 `attack_bonus`。

| 關卡 | attack_bonus | placement_bonus |
|---|---|---|
| white | 無（純基底） | 無 |
| red | 已成長攻擊力(當前ATK−初始ATK)×6；HFR +8（怒氣中再+20）；ADCR +5；APR +7+最高目標ATK×1.5 | LFR +5 / SPR +4 / HFR +3 |
| blue | token=2 → +16、=1 → +6；SPB +12；HFB(有 token)：能殺+20、削血×1.5、上限 70；LFB 每目標+4；ADCB/ASSB +4；預期產球×4；本次攻擊會湊滿 3 球且場上有醒著的 ADCB → +12（連鎖） | TANKB 貼臉+12/次貼+5；SPB 依（我方場上+棄牌）有效命中×4.5、敵≥3 再+8、手上還有其他單位牌每張−5、無敵人−20；ADCB 依 token(2→+18,1→+6)+每個引擎友軍+4；HFB token=0 → −6、≥2 → +10；APB +5；LFB 落點小十字內 ≥2 目標+8、場上敵多+2、稀疏−6；APTB +3 |
| green | LFG 相鄰 LUCKYBLOCK 每個+45；HFG 九宮格內方塊每個+30；ADCG 行列空格×2（上限8） | APTG：相鄰空格數×8 +6；LFG：相鄰方塊×18+相鄰APTG×10；HFG：×14/×8；SPG：min(20, 運氣×0.4) |
| orange | ADCO：基礎分×0.4+移動後最大命中數×2；LFO +8；HFO +12+extra×6+多目標每個+5；ASSO 怒氣+25/佈局+4 | 機動系（ADCO/LFO/HFO/ASSO）中央開闊度×2；TANKO 貼臉+8；SPO 附近 2 格內每個機動友軍+4；APTO 每友軍+2.5 上限 12 |
| boss | 落後(score<−2)時全體攻擊 +5 | 敵方均ATK≥4 → TANK+5；敵方均HP≥6 → ASS+6 |

**關卡環境 buff（stage_buffs）**：green：AI 初始運氣 65；orange：AI 每 3 回合 +1 移動；
boss：AI 單位 +1 HP、起手 4 張、每 5 回合 +1 治療。關卡選單要顯示這些說明文字（模板見 JSON）。

**AI 牌組（`campaign/ai_decks.py`，寫死）**：
- WHITE：ADCW×2 APW TANKW×2 HFW×2 LFW ASSW×2 APTW SPW（玩家各關預設也是這副，可自組）
- RED：ADCR×2 APR TANKR×2 HFR×2 LFR×2 ASSR×2 SPR
- BLUE：ADCB×2 APB TANKB×2 HFB LFB×2 ASSB×2 APTB SPB
- GREEN：ADCG×2 APG TANKG×2 HFG×2 LFG×2 ASSG APTG SPG
- ORANGE：ADCO×2 APO TANKO×2 HFO×2 LFO×2 ASSO×2 SPO
- BOSS：ADCW ADCR TANKB TANKW LFO LFR ASSB ASSO HFO HFR SPR APTB

**戰役結構**：關卡順序 white→red→blue→green→orange→boss；
玩家戰前可用「已解鎖顏色」自組 12 張（解鎖規則：白色永遠可用＋當前關卡色＋**之前已通關**的關卡色；
通關 boss 後全色解鎖）；勝利記錄到存檔（`data/campaign_progress.json`，Godot 用 `user://`）。

## 7. Claude 策略（beam search，爬塔 boss 用；Phase 5 才做）

`ai_strategies/claude.py`。特性：需要**完整 GameState 深拷貝**與 headless dispatcher。

- 對自己回合的行動序列做 beam search：候選 = end_turn + 每張可打手牌的前 5 落點（評分排序，
  全部合計取前 10）+ 所有可攻擊棋子；beam 寬 10、深 8。
- 葉節點評估：模擬「對手一整個貪婪回合 → 我一整個貪婪回合 → 對手再一回合」，
  對手用**推斷策略**（統計對手可見卡牌的主色 → 用該色 Strategy），
  然後 `value = 分差 + 2.4×得分引擎(每回合得分,麻痺×0.5) + 0.1×物質(HP+盾)×0.5+(ATK+extra)×1.2 + 0.5×攻擊次數`。
  勝負直接 ±1e6（下下回合對手贏 ×0.9）。
- 有以「盤面簽名」為 key 的單槽 cache。
- 難度旋鈕：`beam_width`、`depth_cap` 由爬塔樓層數調整（見 07 文件）。
- **Godot 前置需求**：GameCore.clone()（深拷貝全部狀態，不含表現層），
  以及「無渲染 step」能力——這正是 D1 sim/view 分離的驗收之一。

## 8. Godot 移植注意

- ai_query / ai_evaluator 翻成 `static func` 純函式庫，吃 GameCore 狀態，不碰 Node。
- 所有常數從 BalanceDB（campaign_setting.json）讀，不得寫死。
- 控制器節奏用累積 msec 而非 Timer 節點，保持可 headless 測試。
- 單元測試基準：`tests/test_ai_evaluator.py`、`test_ai_query.py`、`test_ai_controller.py`、
  `test_campaign_strategies.py`（Python 端有完整案例可翻譯）。
