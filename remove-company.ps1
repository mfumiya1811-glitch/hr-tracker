# =====================================================================
# 企業を削除する
#
#   -Disable  巡回対象から外すだけ（データは残る／元に戻せる）
#   -Purge    企業ごと完全に削除（人事データも全件消える／戻せない）
#
# 使い方:
#   powershell -NoProfile -ExecutionPolicy Bypass -File remove-company.ps1 -Name "武田薬品工業" -Disable
#   powershell -NoProfile -ExecutionPolicy Bypass -File remove-company.ps1 -Name "武田薬品工業" -Purge
#
# -Purge は、消える件数を表示したうえで企業名の入力を求めます。
# =====================================================================
param(
    [Parameter(Mandatory=$true)][string]$Name,
    [switch]$Disable,
    [switch]$Purge,
    [switch]$Force          # 確認を省略（自動実行用）
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib.ps1')

if (-not $Disable -and -not $Purge) {
    Write-Host '[NG] -Disable か -Purge のどちらかを指定してください。' -ForegroundColor Red
    Write-Host '     -Disable : 巡回対象から外すだけ（データは残る）'
    Write-Host '     -Purge   : 企業ごと完全に削除（戻せない）'
    exit 1
}
if ($Disable -and $Purge) {
    Write-Host '[NG] -Disable と -Purge は同時に指定できません。' -ForegroundColor Red
    exit 1
}

$cfg = Import-DotEnv -Path (Join-Path $PSScriptRoot '.env')
$enc = [Uri]::EscapeDataString($Name)

# --- 対象企業を特定 ---
$co = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/companies?select=id,name,enabled&name=eq.$enc"
if ($co.Count -eq 0) {
    Write-Host "[NG] 「$Name」という企業は登録されていません。" -ForegroundColor Red
    Write-Host ''
    Write-Host '登録されている企業:'
    Get-SupabaseRows -Cfg $cfg -Path '/rest/v1/companies?select=name&order=id' | ForEach-Object { Write-Host "  ・$($_.name)" }
    exit 1
}
$id = $co[0].id

# --- 影響範囲を表示 ---
$events   = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/hr_events?select=id&company_id=eq.$id"
$articles = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/articles?select=id&company_id=eq.$id"
$rosters  = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/roster_snapshots?select=id&company_id=eq.$id"

Write-Host ''
Write-Host "対象: $Name (id=$id)" -ForegroundColor Cyan
Write-Host "  人事データ    : $($events.Count) 件"
Write-Host "  取得済み記事  : $($articles.Count) 件"
Write-Host "  役員名簿      : $($rosters.Count) 件"
Write-Host ''

# --- 巡回対象から外すだけ ---
if ($Disable) {
    Invoke-Supabase -Cfg $cfg -Method 'PATCH' -Path "/rest/v1/companies?id=eq.$id" -Body @{ enabled = $false } | Out-Null
    Write-Host "[OK] 「$Name」を巡回対象から外しました。データはそのまま残っています。" -ForegroundColor Green
    Write-Host "     戻すとき: remove-company.ps1 の代わりに add-company.ps1 -Name `"$Name`" -Enable" -ForegroundColor DarkGray
    exit 0
}

# --- 完全削除（確認あり） ---
Write-Host '!!! 完全削除は取り消せません !!!' -ForegroundColor Red
Write-Host "上記 $($events.Count) 件の人事データもまとめて消えます。" -ForegroundColor Red
Write-Host ''

if (-not $Force) {
    Write-Host "続ける場合は、企業名をそのまま入力してください（中止する場合は Enter だけ）"
    $answer = Read-Host "確認のため入力"
    if ($answer -ne $Name) {
        Write-Host ''
        Write-Host '中止しました。何も削除していません。' -ForegroundColor Yellow
        exit 0
    }
}

Invoke-Supabase -Cfg $cfg -Method 'DELETE' -Path "/rest/v1/companies?id=eq.$id" | Out-Null

# --- 結果を検証 ---
$after   = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/companies?select=id&name=eq.$enc"
$evAfter = Get-SupabaseRows -Cfg $cfg -Path "/rest/v1/hr_events?select=id&company_id=eq.$id"
if ($after.Count -eq 0 -and $evAfter.Count -eq 0) {
    Write-Host ''
    Write-Host "[OK] 「$Name」と関連データ $($events.Count) 件を削除しました。" -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host "[NG] 削除しきれていません（企業 $($after.Count) 件 / 人事 $($evAfter.Count) 件が残存）" -ForegroundColor Red
    exit 1
}
