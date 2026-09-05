# =====================================================================
# 初期セットアップ
#   1. .env と config.js を、見本ファイルから作ります
#   2. メモ帳で開きます（あとは値を貼って保存するだけ）
#
# 実行方法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '=== 初期セットアップ ===' -ForegroundColor Cyan
Write-Host ''

$pairs = @(
    @{ Sample = '.env.example';        Real = '.env';       What = 'service_role キー（管理者用）を入れるファイル' },
    @{ Sample = 'config.example.js';   Real = 'config.js';  What = 'anon public キー（公開用）を入れるファイル' }
)

$missing = @()
$toOpen  = @()

foreach ($p in $pairs) {
    $sample = Join-Path $PSScriptRoot $p.Sample
    $real   = Join-Path $PSScriptRoot $p.Real

    if (-not (Test-Path $sample)) {
        Write-Host "[NG] 見本ファイル $($p.Sample) がこのフォルダにありません。" -ForegroundColor Red
        $missing += $p.Sample
        continue
    }

    if (Test-Path $real) {
        Write-Host "[--] $($p.Real) はすでにあります。作り直しません。" -ForegroundColor DarkGray
    } else {
        Copy-Item $sample $real
        Write-Host "[OK] $($p.Real) を作りました" -ForegroundColor Green
        Write-Host "     $($p.What)" -ForegroundColor DarkGray
    }
    $toOpen += $real
}

if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host '見本ファイルが足りません。ダウンロードしたファイルを' -ForegroundColor Red
    Write-Host 'すべて同じフォルダに入れてから、もう一度実行してください。' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# .gitignore が無い場合は作る（キーを誤って公開しないため）
$gi = Join-Path $PSScriptRoot '.gitignore'
if (-not (Test-Path $gi)) {
    "config.js`r`n.env`r`n" | Out-File $gi -Encoding utf8 -NoNewline
    Write-Host '[OK] .gitignore を作りました（キーが GitHub に上がるのを防ぎます）' -ForegroundColor Green
}

Write-Host ''
Write-Host 'メモ帳を2つ開きます。' -ForegroundColor Cyan
Write-Host '  .env      → SUPABASE_URL と SUPABASE_SERVICE_KEY を書き換える'
Write-Host '  config.js → url と anonKey を書き換える'
Write-Host ''
Write-Host '書き換えたら、それぞれ Ctrl+S で保存して閉じてください。'
Write-Host 'そのあと test-connection.ps1 を実行すると、正しく設定できたか確認できます。'
Write-Host ''

# HR_NO_OPEN=1 を設定しておくとメモ帳を開きません（動作確認用）
if ($env:HR_NO_OPEN -ne '1') {
    foreach ($f in $toOpen) { Start-Process notepad.exe $f }
}
