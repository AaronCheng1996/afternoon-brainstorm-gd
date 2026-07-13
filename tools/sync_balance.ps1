<#
.SYNOPSIS
  P0-2 平衡數值同步腳本（見 docs/rebuild/05_JSON平衡同步.md §2.1）。

.DESCRIPTION
  單向：只讀 Python repo 的 config/*.json，只寫本 Godot repo 的 data/balance/。
  複製 5 個平衡 JSON，並產生 data/balance/_meta.json（synced_at / source_version / hash）。
  source_version 由 Python shared/setting.py 的 `VERSION = "..."` 正則抓取。
  hash 為 5 個檔案內容（固定順序）串接後的 SHA256 前 12 碼。

.PARAMETER SourceDir
  Python config 目錄。預設為 <godot根>\..\AfternoonBrainstorming\FOS brainstorming\config。

.PARAMETER Check
  只比對：以現有 _meta.json 的 hash 與來源檔案重新計算的 hash 比較。
  一致 exit 0；不一致或缺 meta exit 1。不複製任何檔案。

.EXAMPLE
  powershell -File tools/sync_balance.ps1
  powershell -File tools/sync_balance.ps1 -Check
#>
param(
	[string]$SourceDir = "",
	[switch]$Check
)

$ErrorActionPreference = "Stop"

# 要同步的檔案（固定順序 → hash 具決定性）。
$Files = @(
	"card_setting.json",
	"job_dictionary.json",
	"campaign_setting.json",
	"setting.json",
	"card_hints.json"
)

# 路徑推導。
$GodotRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($SourceDir)) {
	$SourceDir = Join-Path $GodotRoot "..\AfternoonBrainstorming\FOS brainstorming\config"
}
$SourceDir = [System.IO.Path]::GetFullPath($SourceDir)
$DestDir = Join-Path $GodotRoot "data\balance"
$PyRoot = Split-Path -Parent $SourceDir   # ...\FOS brainstorming
$SettingPy = Join-Path $PyRoot "shared\setting.py"

# 計算來源檔案串接內容的 SHA256 前 12 碼。
function Get-BalanceHash {
	param([string]$Dir)
	$ms = New-Object System.IO.MemoryStream
	foreach ($f in $Files) {
		$p = Join-Path $Dir $f
		if (-not (Test-Path $p)) {
			throw "缺少來源檔案：$p"
		}
		$bytes = [System.IO.File]::ReadAllBytes($p)
		$ms.Write($bytes, 0, $bytes.Length)
	}
	$ms.Position = 0
	$sha = [System.Security.Cryptography.SHA256]::Create()
	$hashBytes = $sha.ComputeHash($ms)
	$ms.Dispose()
	$hex = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()
	return $hex.Substring(0, 12)
}

# 讀 Python VERSION。
function Get-SourceVersion {
	if (-not (Test-Path $SettingPy)) {
		throw "找不到 $SettingPy（無法讀取 VERSION）"
	}
	$content = Get-Content -Raw -Path $SettingPy
	if ($content -match 'VERSION\s*=\s*"([^"]+)"') {
		return $Matches[1]
	}
	throw "在 $SettingPy 找不到 VERSION 字串"
}

if (-not (Test-Path $SourceDir)) {
	Write-Error "來源目錄不存在：$SourceDir"
	exit 1
}

$sourceHash = Get-BalanceHash -Dir $SourceDir

# --- Check 模式 ---
if ($Check) {
	$metaPath = Join-Path $DestDir "_meta.json"
	if (-not (Test-Path $metaPath)) {
		Write-Host "尚未同步（無 _meta.json）"
		exit 1
	}
	$meta = Get-Content -Raw -Path $metaPath | ConvertFrom-Json
	if ($meta.hash -eq $sourceHash) {
		Write-Host "平衡資料已是最新（hash $sourceHash）"
		exit 0
	}
	else {
		Write-Host "平衡資料過期：來源 $sourceHash != 已同步 $($meta.hash)"
		exit 1
	}
}

# --- 同步模式 ---
if (-not (Test-Path $DestDir)) {
	New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
}

foreach ($f in $Files) {
	$src = Join-Path $SourceDir $f
	$dst = Join-Path $DestDir $f
	Copy-Item -Path $src -Destination $dst -Force
	Write-Host "已複製 $f"
}

$version = Get-SourceVersion
$syncedAt = [System.DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

$meta = [ordered]@{
	synced_at      = $syncedAt
	source_version = $version
	hash           = $sourceHash
}
$metaJson = ($meta | ConvertTo-Json)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $DestDir "_meta.json"), $metaJson, $utf8NoBom)

Write-Host ""
Write-Host "同步完成：version=$version hash=$sourceHash"
exit 0
