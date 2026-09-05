# =====================================================================
# 接続確認：.env の設定で Supabase に繋がるか、スキーマが入っているかを見る
# 実行:  powershell -NoProfile -ExecutionPolicy Bypass -File test-connection.ps1
#
# キーの値は一切表示しません。
# =====================================================================
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')

Write-Host ''
Write-Host '=== Supabase 接続確認 ===' -ForegroundColor Cyan
Write-Host ''

try {
    $cfg = Import-DotEnv
} catch {
    Write-Host "[NG] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# URL はホスト名のみ表示（キーは出さない）
$host_ = ([Uri]$cfg.SUPABASE_URL).Host
Write-Host "接続先 : $host_"
Write-Host "キー   : .env から読み込み済み（表示しません）"
Write-Host ''

$ok = $true

# --- 0. 疎通確認（URL の打ち間違いとテーブル未作成を区別する） ---
try {
    Invoke-Supabase -Cfg $cfg -Path '/rest/v1/' | Out-Null
} catch {
    $m = $_.Exception.Message
    if ($m -match 'リモート名|No such host|could not be resolved|名前を解決') {
        Write-Host '[NG] 接続先に到達できません。SUPABASE_URL を確認してください。' -ForegroundColor Red
        Write-Host '     Supabase ダッシュボード → Project Settings → API → Project URL' -ForegroundColor DarkGray
    } elseif ($m -match '401|403|JWT|apikey') {
        Write-Host '[NG] 認証に失敗しました。SUPABASE_SERVICE_KEY を確認してください。' -ForegroundColor Red
        Write-Host '     service_role キー（anon ではない方）が必要です。' -ForegroundColor DarkGray
    } else {
        Write-Host "[NG] 接続できません: $m" -ForegroundColor Red
    }
    Write-Host ''
    exit 1
}
Write-Host '[OK] 接続できました' -ForegroundColor Green
Write-Host ''

# --- 1. テーブルの存在確認 ---
$tables = @('companies','articles','hr_events','roster_snapshots','crawl_runs')
foreach ($t in $tables) {
    try {
        Invoke-Supabase -Cfg $cfg -Path "/rest/v1/$($t)?select=*&limit=1" | Out-Null
        Write-Host ("[OK] テーブル {0,-18} あり" -f $t) -ForegroundColor Green
    } catch {
        Write-Host ("[NG] テーブル {0,-18} 見つかりません" -f $t) -ForegroundColor Red
        Write-Host "     schema.sql を SQL Editor で実行してください。" -ForegroundColor DarkGray
        $ok = $false
    }
}

if (-not $ok) { Write-Host ''; exit 1 }

# --- 2. 企業マスタの中身 ---
Write-Host ''
$companies = Invoke-Supabase -Cfg $cfg -Path '/rest/v1/companies?select=name,access_status,content_format,last_crawled_at&order=name'
Write-Host "登録企業: $($companies.Count) 社" -ForegroundColor Cyan
foreach ($c in $companies) {
    $last = if ($c.last_crawled_at) { ([string]$c.last_crawled_at).Substring(0,10) } else { '未巡回' }
    Write-Host ("  - {0,-24} {1,-8} {2,-6} {3}" -f $c.name, $c.access_status, $c.content_format, $last)
}

# --- 3. イベント件数 ---
Write-Host ''
foreach ($s in @('pending','approved','rejected')) {
    $rows = Invoke-Supabase -Cfg $cfg -Path "/rest/v1/hr_events?select=id&status=eq.$s"
    Write-Host ("hr_events / {0,-9}: {1} 件" -f $s, $rows.Count)
}

# --- 4. 書き込み権限の確認（実際に入れて即消す） ---
Write-Host ''
try {
    $probeName = '__接続テスト__'
    $body = @{ name = $probeName; press_url = 'https://example.com/'; access_status = 'unknown' }
    Invoke-Supabase -Cfg $cfg -Method 'POST' -Path '/rest/v1/companies' -Body $body -Prefer 'return=representation' | Out-Null
    Invoke-Supabase -Cfg $cfg -Method 'DELETE' -Path "/rest/v1/companies?name=eq.$([Uri]::EscapeDataString($probeName))" | Out-Null
    Write-Host '[OK] 書き込み権限あり（テスト行は削除済み）' -ForegroundColor Green
} catch {
    Write-Host '[NG] 書き込みできません。service_role キーか確認してください。' -ForegroundColor Red
    Write-Host "     $($_.Exception.Message)" -ForegroundColor DarkGray
    exit 1
}

Write-Host ''
Write-Host '=== すべて正常です。巡回を開始できます。 ===' -ForegroundColor Green
Write-Host ''
