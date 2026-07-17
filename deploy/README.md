# 架伺服器（Ubuntu 專用連線伺服器）

午後激盪連線版＝**專用伺服器＋房間制**（決策 D18）：一台常駐主機跑 headless 的
`script/net/server_main.gd`，玩家用戶端連上開房/加房對戰。規格見
[`../docs/rebuild/10_連線版本.md`](../docs/rebuild/10_連線版本.md) §5/§9。

本目錄提供部署三件套：

| 檔案 | 用途 |
|---|---|
| `run_server.sh` | 手動啟動腳本（bash） |
| `afternoon-brainstorm-server.service` | systemd unit 範本（常駐：自動重啟/開機自啟/journald） |
| `server_config.json` | 伺服器設定範本（埠/房間數/觀戰上限/席位保留秒數/存紀錄） |

---

## 1. 前置

- **主機**：Ubuntu，固定 IP、直連公網（無需 NAT 穿透）。
- **Godot**：下載 **Godot 4.7 stable** Linux 版執行檔（headless 亦可用一般版加 `--headless`），
  例如放到 `/opt/godot/Godot_v4.7-stable_linux.x86_64`。
- **專案**：把本 repo（含 `project.godot`）放到主機，例如 `/opt/afternoon-brainstorm`。
  首次建議先跑一次 `--headless --import` 讓 Godot 建好 `.godot/` global class 快取。

## 2. 開防火牆埠（預設 24242/UDP）

ENet 走 UDP。預設埠 **24242**（避開 Steam 用戶端 27000–27100，見 §9）：

```bash
sudo ufw allow 24242/udp
sudo ufw reload
```

改埠時同步改 `server_config.json`（或 `ExecStart` 的 `port=`）與 ufw 規則。

## 3. 設定檔

把 `server_config.json` 複製到 Godot 的 user 目錄（Linux 預設）：

```bash
mkdir -p ~/.local/share/godot/app_userdata/AfternoonBrainstorming_godot
cp deploy/server_config.json \
   ~/.local/share/godot/app_userdata/AfternoonBrainstorming_godot/server_config.json
```

> 目錄名以 `project.godot` 的 `config/name` 為準；不確定可先跑一次伺服器看 log 的 `user://` 路徑。
> 命令列 `key=value`（在 `--` 之後）會再覆蓋設定檔——見 `server_main.parse_config`。

設定鍵：`port`、`max_rooms`、`max_clients`、`spectator_limit`、`seat_hold_seconds`
（斷線重連保留秒數，P12-10）、`save_replays`（對局結束存 `user://replays/*.jsonl`，P11-2 格式）。

## 4. 手動啟動（驗證用）

```bash
chmod +x deploy/run_server.sh
GODOT=/opt/godot/Godot_v4.7-stable_linux.x86_64 \
PROJECT=/opt/afternoon-brainstorm \
deploy/run_server.sh port=24242 max_rooms=16
```

看到 `[server] 午後激盪 專用伺服器啟動：埠 24242…` 即成功。`Ctrl-C` 結束。

## 5. 常駐（systemd）

1. 編輯 `afternoon-brainstorm-server.service`：改 `User/Group`、兩個 `Environment` 路徑、
   `ExecStart` 的 Godot 與專案路徑。
2. 安裝並啟用：

```bash
sudo cp deploy/afternoon-brainstorm-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now afternoon-brainstorm-server
sudo systemctl status afternoon-brainstorm-server
journalctl -u afternoon-brainstorm-server -f      # 追 log
```

崩潰或 `SIGTERM` 後自動重啟；開機自啟；stdout/stderr 進 journald。

## 6. 用戶端連線

用戶端內建預設伺服器位址（`net_host`，預設 `127.0.0.1`，**部署時改成主機公網 IP**）
與埠（`net_port`，預設 24242），玩家可於「線上對戰」畫面手動修改（存 `user://settings.json`）。
朋友拿到同版遊戲即可直連——**版本閘**（遊戲版本＋資料版本）保證新舊版不會混連。

## 7. 安全與展望

- ENet 無內建加密，密碼/暱稱走明文 UDP——定位朋友圈同樂可接受（§9）。日後公開見生人再評估 DTLS。
- 伺服器端輸入全部當不可信：`NetMessage` schema 驗證＋dispatch 合法性雙層擋；seed 永不下發（D19）。
- **Steam 之路**（§9.5）：傳輸集中於單一工廠 `NetTransport`，未來換 `SteamMultiplayerPeer`
  只改一檔，RPC 不動。

> **實機部署與跨機驗證屬人工步驟**（本 repo 只提供腳本/範本/設定與 headless soak 驗收）。
