# =====================================================================
# 企業を追加する／巡回対象に戻す
#
# 使い方:
#   # 新規追加
#   powershell -File add-company.ps1 -Name "大塚ホールディングス" `
#              -PressUrl "https://www.otsuka.com/jp/company/newsreleases/" `
#              -LinkTextPattern "人事|役員|組織" -Format html
#
#   # 対象外にした企業を戻す
#   powershell -File add-company.ps1 -Name "武田薬品工業" -Enable
#
# robots.txt は自動で確認し、AI クローラーを拒否している場合は
# access_status を blocked にして登録します（巡回はしません）。
# =====================================================================
param(
    [Parameter(Mandatory=$true)][string]$Name,
    [string]$PressUrl,
    [string]$LeadershipUrl,
    [string]$UrlPattern,
    [string]$LinkTextPattern = '人事|役員|組織改定|組織改正|組織改編',
    [ValidateSet('html','pdf','mixed')][string]$Format = 'mixed',
    [switch]$Enable          # 既存企業を巡回対象に戻すだけ
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib.ps1')

$cfg = Import-DotEnv -Path (Join-Path $PSScriptRoot '.env')
$enc = [Uri]::EscapeDataString($Name)
$existing = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/companies?select=id,name,enabled&name=eq.$enc"

# --- 対象に戻すだけ ---
if ($Enable) {
    if ($existing.Count -eq 0) { Write-Host "[NG] 「$Name」は登録されていません。" -ForegroundColor Red; exit 1 }
    Invoke-Supabase -Cfg $cfg -Method 'PATCH' -Path "/rest/v1/companies?id=eq.$($existing[0].id)" -Body @{ enabled = $true } | Out-Null
    Write-Host "[OK] 「$Name」を巡回対象に戻しました。" -ForegroundColor Green
    exit 0
}

if ($existing.Count -gt 0) {
    Write-Host "[NG] 「$Name」はすでに登録されています（id=$($existing[0].id)）。" -ForegroundColor Red
    Write-Host '     内容を変えたい場合は、企業マスタを直接更新してください。' -ForegroundColor DarkGray
    exit 1
}
if ([string]::IsNullOrWhiteSpace($PressUrl)) {
    Write-Host '[NG] 新規追加には -PressUrl が必要です。' -ForegroundColor Red
    exit 1
}

# --- robots.txt を確認して、AI クローラーの可否を判定 ---
$uri  = [Uri]$PressUrl
$root = "$($uri.Scheme)://$($uri.Host)"
$status = 'ok'
$note   = "robots.txt 確認済み（$(Get-Date -Format 'yyyy-MM-dd')）"
try {
    $rb = (Invoke-WebRequest -Uri "$root/robots.txt" -UseBasicParsing -UserAgent 'hr-tracker/1.0' -TimeoutSec 20 -ErrorAction Stop).Content

    # robots.txt を「User-agent 行のかたまり」ごとに解析する。
    # 正規表現1本で書くと PowerShell が $(...) を部分式として実行してしまうため、
    # 行単位で素直に読む。
    $targets = @('claudebot','claude-user','claude-web','claude-searchbot','anthropic-ai')
    $blocked = $false
    $currentAgents = @()
    $sawRule = $false
    foreach ($line in ($rb -split "`r?`n")) {
        $l = ($line -replace '#.*$', '').Trim()
        if ($l -eq '') { continue }
        if ($l -match '^(?i)user-agent\s*:\s*(.+)$') {
            if ($sawRule) { $currentAgents = @(); $sawRule = $false }
            $currentAgents += $Matches[1].Trim().ToLower()
        }
        elseif ($l -match '^(?i)disallow\s*:\s*(.*)$') {
            $sawRule = $true
            if ($Matches[1].Trim() -eq '/') {
                foreach ($a in $currentAgents) { if ($targets -contains $a) { $blocked = $true } }
            }
        }
        elseif ($l -match '^(?i)(allow|crawl-delay)\s*:') { $sawRule = $true }
    }

    if ($blocked) {
        $status = 'blocked'
        $note = "robots.txt が AI クローラーを明示的に拒否しているため巡回しない（$(Get-Date -Format 'yyyy-MM-dd')）"
        Write-Host '[!!] robots.txt が AI クローラーを拒否しています。blocked として登録します。' -ForegroundColor Yellow
    } else {
        Write-Host '[OK] robots.txt に AI クローラーの拒否設定はありません' -ForegroundColor Green
    }
} catch {
    $note = "robots.txt を取得できず（404 等）。制限なしとみなす（$(Get-Date -Format 'yyyy-MM-dd')）"
    Write-Host '[--] robots.txt がありません（＝制限なし）' -ForegroundColor DarkGray
}

# --- 登録 ---
$body = @{
    name              = $Name
    press_url         = $PressUrl
    leadership_url    = if ([string]::IsNullOrWhiteSpace($LeadershipUrl)) { $null } else { $LeadershipUrl }
    url_pattern       = if ([string]::IsNullOrWhiteSpace($UrlPattern))    { $null } else { $UrlPattern }
    link_text_pattern = $LinkTextPattern
    content_format    = $Format
    access_status     = $status
    access_note       = $note
    enabled           = ($status -ne 'blocked')
}
$res = Invoke-Supabase -Cfg $cfg -Method 'POST' -Path '/rest/v1/companies' -Body $body -Prefer 'return=representation'
Write-Host ''
Write-Host "[OK] 「$Name」を登録しました（id=$(@($res)[0].id)）" -ForegroundColor Green
Write-Host "     取得可否: $status / 形式: $Format"
Write-Host "     判定ルール: $(if ($UrlPattern) { "URL $UrlPattern" } else { "リンク文言 $LinkTextPattern" })"
Write-Host ''
Write-Host '次に巡回して人事記事を取り込みます。' -ForegroundColor Cyan
