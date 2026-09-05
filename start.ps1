# =====================================================================
# レビュー画面を起動します
#
# 使い方: このファイルを右クリック →「PowerShell で実行」
#     または  powershell -NoProfile -ExecutionPolicy Bypass -File start.ps1
#
# http://localhost:4321 で開きます。
# file:// で直接開くとログイン（メールリンク）が戻ってこられないため、
# 必ずこのスクリプト経由で開いてください。
# 止めるときは、この黒い画面で Ctrl+C を押すか、ウィンドウを閉じます。
# =====================================================================
$ErrorActionPreference = 'Stop'
$port = 4321
$root = $PSScriptRoot

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try {
    $listener.Start()
} catch {
    Write-Host ''
    Write-Host "[NG] ポート $port を使用できません。" -ForegroundColor Red
    Write-Host '     すでにこの画面を起動していないか確認してください。' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host '  人事異動トラッカー を起動しました' -ForegroundColor Cyan
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  画面: http://localhost:$port"
Write-Host ''
Write-Host '  終わるときは、この画面で Ctrl+C を押してください。'
Write-Host '  （画面を開いている間は、この黒い画面を閉じないでください）'
Write-Host ''

Start-Process "http://localhost:$port"

$types = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
}

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
        if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }

        # 上位ディレクトリへの脱出を防ぐ
        $full = [IO.Path]::GetFullPath((Join-Path $root $rel))
        if (-not $full.StartsWith([IO.Path]::GetFullPath($root))) {
            $ctx.Response.StatusCode = 403; $ctx.Response.Close(); continue
        }
        # 秘密ファイルは絶対に配信しない
        $name = [IO.Path]::GetFileName($full)
        if ($name -eq '.env' -or $name -like '*.ps1') {
            $ctx.Response.StatusCode = 403; $ctx.Response.Close(); continue
        }

        if (Test-Path $full -PathType Leaf) {
            $ext = [IO.Path]::GetExtension($full).ToLower()
            $ctx.Response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
            $bytes = [IO.File]::ReadAllBytes($full)
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host ("  200  /{0}" -f $rel) -ForegroundColor DarkGray
        } else {
            $ctx.Response.StatusCode = 404
            Write-Host ("  404  /{0}" -f $rel) -ForegroundColor DarkYellow
        }
        $ctx.Response.Close()
    } catch {
        # クライアント切断などは無視して待ち受けを継続
    }
}
