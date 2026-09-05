# =====================================================================
# GitHub に公開する
#
# 事前に https://github.com/new で「hr-tracker」という名前の
# Public リポジトリを作っておいてください（README等は追加しない）。
#
# 使い方:
#   powershell -NoProfile -ExecutionPolicy Bypass -File publish.ps1
#   （GitHubのユーザー名を聞かれます）
#
#   ユーザー名が分かっていれば直接渡せます:
#   powershell -NoProfile -ExecutionPolicy Bypass -File publish.ps1 -User ユーザー名
# =====================================================================
param(
    [string]$User,
    [string]$Repo = 'hr-tracker'
)
# git は警告を標準エラーに出すため 'Stop' にすると誤って中断してしまう。
# 成否は各コマンドの終了コード（$LASTEXITCODE）で明示的に判定する。
$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

Write-Host ''
Write-Host '=== GitHub へ公開 ===' -ForegroundColor Cyan
Write-Host ''

# --- 1. ユーザー名を決める ---
if ([string]::IsNullOrWhiteSpace($User)) {
    Write-Host 'GitHub のユーザー名を入力してください。'
    Write-Host '（https://github.com にログインしたとき、右上のアイコンに表示される名前です）'
    Write-Host ''
    $User = Read-Host 'GitHub ユーザー名'
}
$User = $User.Trim()
if ($User -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$') {
    Write-Host "[NG] ユーザー名の形式が正しくありません: $User" -ForegroundColor Red
    Write-Host '     英数字とハイフンのみです。メールアドレスではありません。' -ForegroundColor DarkGray
    exit 1
}
$url   = "https://github.com/$User/$Repo.git"
$pages = "https://$User.github.io/$Repo/"

# --- 2. 秘密ファイルが混ざっていないか最終確認 ---
$tracked = git ls-files
if ($tracked -contains '.env') {
    Write-Host '[NG] .env が Git の管理対象に入っています。中止します。' -ForegroundColor Red
    exit 1
}
Write-Host '[OK] .env は含まれていません' -ForegroundColor Green

# --- 3. リポジトリが GitHub 側に存在するか確認 ---
Write-Host ''
Write-Host "確認中: $url"
# 存在確認の段階では認証を求めない（Public なら匿名で確認できる）。
# ここでログイン画面が出ると、リポジトリ未作成の場合に分かりにくいため。
$prevPrompt = $env:GIT_TERMINAL_PROMPT
$prevGcm    = $env:GCM_INTERACTIVE
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE     = 'never'
git ls-remote $url *> $null
$exists = ($LASTEXITCODE -eq 0)
$env:GIT_TERMINAL_PROMPT = $prevPrompt
$env:GCM_INTERACTIVE     = $prevGcm

if (-not $exists) {
    Write-Host ''
    Write-Host '[NG] そのリポジトリが見つかりませんでした。' -ForegroundColor Red
    Write-Host ''
    Write-Host '  次のどちらかです：'
    Write-Host '   ・まだ作っていない  → https://github.com/new で作成してください'
    Write-Host "                          名前は $Repo 、Public、README等は追加しない"
    Write-Host '   ・ユーザー名が違う  → もう一度実行して正しい名前を入れてください'
    Write-Host ''
    exit 1
}
Write-Host '[OK] リポジトリを確認しました' -ForegroundColor Green

# --- 4. リモートを設定して push ---
$existing = git remote 2>$null
if ($existing -contains 'origin') { git remote set-url origin $url } else { git remote add origin $url }
Write-Host ''
Write-Host 'アップロード中…（GitHubのログイン画面が出たら、ブラウザで許可してください）'
Write-Host ''
git push -u origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '[NG] アップロードに失敗しました。上のメッセージを確認してください。' -ForegroundColor Red
    exit 1
}

# --- 5. 次にやることを案内 ---
Write-Host ''
Write-Host '===================================================' -ForegroundColor Green
Write-Host '  アップロード完了' -ForegroundColor Green
Write-Host '===================================================' -ForegroundColor Green
Write-Host ''
Write-Host '残り2つ、ブラウザでの設定が必要です。'
Write-Host ''
Write-Host '【1】GitHub Pages を有効にする'
Write-Host "   https://github.com/$User/$Repo/settings/pages"
Write-Host '   Source で「main」ブランチ / 「/ (root)」を選んで Save'
Write-Host ''
Write-Host '【2】Supabase にログインの戻り先を登録する'
Write-Host '   Authentication → URL Configuration → Redirect URLs'
Write-Host '   次の2つを追加してください：'
Write-Host "     $pages" -ForegroundColor Yellow
Write-Host '     http://localhost:4321/' -ForegroundColor Yellow
Write-Host ''
Write-Host "  公開URL（数分後に見られます）: $pages" -ForegroundColor Cyan
Write-Host ''

Start-Process "https://github.com/$User/$Repo/settings/pages"
