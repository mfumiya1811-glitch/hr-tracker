# =====================================================================
# 共通ライブラリ：.env の読み込みと Supabase REST API 呼び出し
#
# 設計方針：キーの値は絶対に画面へ出しません。
#   - 読み込み後は変数に保持するだけ
#   - エラーメッセージにキーが混ざる場合は伏字にしてから表示
# =====================================================================

function Import-DotEnv {
    param([string]$Path = (Join-Path $PSScriptRoot '.env'))

    if (-not (Test-Path $Path)) {
        throw ".env が見つかりません（$Path）。.env.example をコピーして作成してください。"
    }

    $cfg = @{}
    foreach ($line in (Get-Content $Path -Encoding UTF8)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $cfg[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim().Trim('"')
    }

    foreach ($k in @('SUPABASE_URL','SUPABASE_SERVICE_KEY')) {
        if (-not $cfg.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($cfg[$k])) {
            throw "$k が .env に設定されていません。"
        }
        if ($cfg[$k] -like '*xxxx*') {
            throw "$k がテンプレートのままです。実際の値に置き換えてください。"
        }
    }
    $cfg['SUPABASE_URL'] = $cfg['SUPABASE_URL'].TrimEnd('/')
    return $cfg
}

# キーが万が一メッセージに混入した場合に伏字化する
function Protect-Secret {
    param([string]$Text, [string]$Secret)
    if ([string]::IsNullOrEmpty($Text) -or [string]::IsNullOrEmpty($Secret)) { return $Text }
    return $Text.Replace($Secret, '***REDACTED***')
}

function Invoke-Supabase {
    param(
        [hashtable]$Cfg,
        [string]$Method = 'GET',
        [Parameter(Mandatory=$true)][string]$Path,   # 例: '/rest/v1/companies?select=*'
        $Body = $null,
        [string]$Prefer = $null
    )

    $headers = @{
        'apikey'        = $Cfg.SUPABASE_SERVICE_KEY
        'Authorization' = 'Bearer ' + $Cfg.SUPABASE_SERVICE_KEY
        'Content-Type'  = 'application/json'
    }
    if ($Prefer) { $headers['Prefer'] = $Prefer }

    $uri = $Cfg.SUPABASE_URL + $Path
    # 既定の User-Agent には "Mozilla" が入るため、Supabase に
    # 「ブラウザから秘密キーが使われた」と誤認されて拒否される。
    # サーバー側プログラムであることを示す UA を明示する。
    $args = @{
        Uri = $uri; Method = $Method; Headers = $headers
        UserAgent = 'hr-tracker/1.0 (PowerShell)'; ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        # PowerShell 5.1 は既定で UTF-8 を送らないため明示的にバイト列で渡す
        $args['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    try {
        return Invoke-RestMethod @args
    } catch {
        $msg = Protect-Secret $_.Exception.Message $Cfg.SUPABASE_SERVICE_KEY
        $detail = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = ' / ' + (Protect-Secret $_.ErrorDetails.Message $Cfg.SUPABASE_SERVICE_KEY)
        }
        throw "Supabase 呼び出しに失敗しました [$Method $Path]: $msg$detail"
    }
}
