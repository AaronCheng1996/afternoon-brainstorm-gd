#!/usr/bin/env bash
# P12-11 午後激盪 專用伺服器 啟動腳本（Ubuntu / Linux）。
# 用法：./run_server.sh            以預設（或 server_config.json）啟動
#       ./run_server.sh port=24242 max_rooms=16   命令列覆蓋（key=value，見 server_main.gd）
#
# 前置：
#   1. 安裝 Godot 4.7 stable Linux headless 版（見下方 GODOT）。
#   2. ufw allow 24242/udp（見 deploy/README.md）。
#   3. 首次可先手動跑一次確認開埠成功，再交給 systemd 常駐（見 afternoon-brainstorm-server.service）。
set -euo pipefail

# --- 可調參數（部署時依主機調整；或改用環境變數覆蓋）---
# Godot 4.7 stable Linux 執行檔（headless 亦可用一般版本加 --headless）。
GODOT="${GODOT:-/opt/godot/Godot_v4.7-stable_linux.x86_64}"
# 專案根目錄（含 project.godot）。預設＝本腳本上一層。
PROJECT="${PROJECT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# server_main 進入點（SceneTree）。
ENTRY="script/net/server_main.gd"

if [[ ! -x "$GODOT" ]]; then
	echo "[run_server] 找不到 Godot 執行檔：$GODOT" >&2
	echo "[run_server] 請設 GODOT 環境變數或編輯本腳本的 GODOT 變數。" >&2
	exit 1
fi

echo "[run_server] Godot   ：$GODOT"
echo "[run_server] 專案根  ：$PROJECT"
echo "[run_server] 進入點  ：$ENTRY"
echo "[run_server] 覆蓋參數：$*"

# server_config.json 讀自 user://（Linux＝~/.local/share/godot/app_userdata/<專案名>/）。
# 命令列 key=value 於 `--` 之後傳入，覆蓋 server_config.json（見 server_main.parse_config）。
exec "$GODOT" --headless --path "$PROJECT" -s "$ENTRY" -- "$@"
