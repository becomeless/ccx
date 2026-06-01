# ============================================================
#  ccx  ——  Claude Code API 切换器（命令：xx）
# ============================================================
#
#  安全：完全不碰任何配置文件（不写 settings.json，不开 .claude.json）。
#        MCP / 插件 / hooks 物理上不可能被它影响。
#
#  两种启用：
#    · 本次启用：只给【当前终端这一个进程】设环境变量并启动 Claude。
#        - 多终端并行、各用各 API、互不干扰；阅后即焚，关掉就没。
#    · 设为默认：把该 API 写成【用户环境变量】。
#        - 之后【新开】终端裸敲 claude 就默认用它；
#        - 不影响正在运行的会话（环境变量在进程启动时定型，运行中不变）。
#
#  受管的环境变量（工具只动这些，其它一律不碰）：
#    ANTHROPIC_BASE_URL / AUTH_TOKEN / API_KEY /
#    DEFAULT_OPUS/SONNET/HAIKU_MODEL / CLAUDE_CODE_EFFORT_LEVEL
#
#  用法：
#    pwsh -File xx.ps1                       # 交互菜单（↑↓ 选择）
#    pwsh -File xx.ps1 DeepSeek              # 直接“设为默认”到 DeepSeek
#    pwsh -File xx.ps1 DeepSeek -Session     # “本次启用”并启动 Claude
#    pwsh -File xx.ps1 -List                 # 列出所有档案
# ============================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Switch,
    [switch]$Session,
    [switch]$List,
    [string]$StoreDir,
    [ValidateSet('User', 'Process')]
    [string]$DefaultScope = 'User'   # 设为默认写到哪：User=持久(默认)，Process=仅测试用
)

if (-not $StoreDir) { $StoreDir = Join-Path $env:USERPROFILE '.cc-mini' }
$script:StoreDir     = $StoreDir
$script:StorePath    = Join-Path $StoreDir 'providers.json'
$script:DefaultScope = $DefaultScope
$script:Version      = '0.2.0'   # 发版时同步更新（与 ccx.psd1 的 ModuleVersion 保持一致）

# 受管钥匙：工具完全拥有这些键，启用时按目标档案 设置/清除，其它变量一律不动。
$script:KnownKeys = @(
    'ANTHROPIC_BASE_URL',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_API_KEY',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'CLAUDE_CODE_EFFORT_LEVEL'
)
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# API 地址预置：优先读脚本同目录的 presets.json，缺失则用内置兜底。
$BuiltinPresetsJson = @'
[
  { "name": "DeepSeek",  "url": "https://api.deepseek.com/anthropic" },
  { "name": "智谱GLM",   "url": "https://open.bigmodel.cn/api/anthropic" },
  { "name": "小米MiMo",  "url": "https://api.xiaomimimo.com/anthropic" },
  { "name": "官方Anthropic(留空)", "url": "" }
]
'@
$presetsFile = Join-Path $PSScriptRoot 'presets.json'
$script:BaseUrlPresets = @(
    if (Test-Path $presetsFile) {
        try { Get-Content -Raw -Path $presetsFile | ConvertFrom-Json } catch { $BuiltinPresetsJson | ConvertFrom-Json }
    } else { $BuiltinPresetsJson | ConvertFrom-Json }
)

# 默认档案（effort 按各家文档：官方留空、DeepSeek=max、GLM/MiMo 留空）
$DefaultStoreJson = @'
{
  "current": "官方",
  "providers": [
    { "name": "官方", "note": "", "env": {} },
    {
      "name": "DeepSeek", "note": "",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
        "CLAUDE_CODE_EFFORT_LEVEL": "max"
      }
    },
    {
      "name": "智谱GLM", "note": "",
      "env": {
        "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "GLM-4.7",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "GLM-4.7",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "glm-4.5-air"
      }
    },
    {
      "name": "小米MiMo", "note": "",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.xiaomimimo.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "mimo-v2.5-pro",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "mimo-v2.5-pro",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "mimo-v2.5-pro"
      }
    }
  ]
}
'@

# ============================================================
#  档案存取
# ============================================================
function Save-Store($store) {
    if (-not (Test-Path $script:StoreDir)) { New-Item -ItemType Directory -Path $script:StoreDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($script:StorePath, ($store | ConvertTo-Json -Depth 100), $Utf8NoBom)
}
function Get-Store {
    if (Test-Path $script:StorePath) { return Get-Content -Raw -Path $script:StorePath | ConvertFrom-Json }
    $store = $DefaultStoreJson | ConvertFrom-Json
    Save-Store $store
    Write-Host "  已在 $($script:StorePath) 生成默认档案（含官方 + 三个第三方，密钥待填）。" -ForegroundColor DarkGray
    return $store
}
function Get-ManagedKeys { return $script:KnownKeys }
function Get-ProviderEnvMap($prov) {
    $map = @{}
    if ($prov.env) { foreach ($p in $prov.env.PSObject.Properties) { $map[$p.Name] = [string]$p.Value } }
    return $map
}
function Build-ProviderEnv([hashtable]$fields) {
    $o = [ordered]@{}
    foreach ($k in $script:KnownKeys) {
        if ($fields.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace([string]$fields[$k])) { $o[$k] = [string]$fields[$k] }
    }
    return [PSCustomObject]$o
}
function Get-Note($prov) { if ($prov.PSObject.Properties.Name -contains 'note') { return [string]$prov.note } return '' }
function Set-Note($prov, $note) {
    if ($prov.PSObject.Properties.Name -contains 'note') { $prov.note = $note }
    else { $prov | Add-Member -NotePropertyName 'note' -NotePropertyValue $note }
}
function Show-State($prov) {
    if ($prov.name -eq '官方') { $s = '登录态' }
    else {
        $map = Get-ProviderEnvMap $prov
        $hasTok = -not [string]::IsNullOrWhiteSpace($map['ANTHROPIC_AUTH_TOKEN'])
        $hasKey = -not [string]::IsNullOrWhiteSpace($map['ANTHROPIC_API_KEY'])
        if (-not ($hasTok -or $hasKey)) { $s = '密钥未填' }
        elseif ($hasKey) { $s = '密钥·API_KEY' }
        else { $s = '密钥已设' }
    }
    $eff = (Get-ProviderEnvMap $prov)['CLAUDE_CODE_EFFORT_LEVEL']
    if (-not [string]::IsNullOrWhiteSpace($eff)) { $s += " · effort=$eff" }
    return $s
}

# ============================================================
#  两种启用
# ============================================================

# 设为默认：写用户环境变量（新终端裸 claude 生效；不影响运行中会话）
function Set-Default($store, $prov) {
    $envMap = Get-ProviderEnvMap $prov
    $noKey = [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_AUTH_TOKEN']) -and [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_API_KEY'])
    if ($prov.name -ne '官方' -and $noKey) { Write-Host "  ⚠ 档案 [$($prov.name)] 还没填密钥。" -ForegroundColor Yellow }

    foreach ($k in (Get-ManagedKeys)) {
        $val = if ($envMap.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($envMap[$k])) { $envMap[$k] } else { $null }
        [Environment]::SetEnvironmentVariable($k, $val, $script:DefaultScope)
    }
    $store.current = $prov.name
    Save-Store $store

    Write-Host ""
    Write-Host "  ✓ 已设为默认：$($prov.name)" -ForegroundColor Green
    Write-Host "    新开的终端裸敲  claude  就会用它；正在运行的会话不受影响。" -ForegroundColor White
    Write-Host "    （当前这个终端是旧环境，需【新开终端】才生效。）" -ForegroundColor DarkGray
    Write-Host ""
}

# 本次启用：仅当前进程设环境变量并启动 Claude（多终端隔离，阅后即焚）
function Session-Launch($store, $prov) {
    $envMap = Get-ProviderEnvMap $prov
    $noKey = [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_AUTH_TOKEN']) -and [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_API_KEY'])
    if ($prov.name -ne '官方' -and $noKey) { Write-Host "  ⚠ 档案 [$($prov.name)] 还没填密钥。" -ForegroundColor Yellow }

    foreach ($k in (Get-ManagedKeys)) {
        if ($envMap.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($envMap[$k])) { Set-Item -Path "Env:$k" -Value $envMap[$k] }
        elseif (Test-Path "Env:$k") { Remove-Item "Env:$k" }
    }
    Write-Host ""
    Write-Host "  ▶ 本次启用：$($prov.name)（仅当前终端，不影响其它终端）" -ForegroundColor Green
    Write-Host "    正在启动 Claude…（退出 Claude 后回到命令行）" -ForegroundColor DarkGray
    Write-Host ""
    if (Get-Command claude -ErrorAction SilentlyContinue) { claude }
    else { Write-Host "  未找到 claude 命令，请确认它在 PATH 中。" -ForegroundColor Red }
}

# ============================================================
#  ↑↓ 选择菜单（含数字快捷键 / 非交互回退）
# ============================================================
# 计算字符串在终端的显示宽度（CJK / 全角算 2，其余算 1），用于按显示宽度对齐。
function Get-DisplayWidth([string]$s) {
    $w = 0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int][char]$ch
        if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or
            ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or
            ($c -ge 0xFE30 -and $c -le 0xFE4F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or
            ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $w += 2 } else { $w += 1 }
    }
    return $w
}
function Pad-Display([string]$s, [int]$Width) {
    $n = $Width - (Get-DisplayWidth $s)
    if ($n -gt 0) { return $s + (' ' * $n) }
    return $s
}

# 写一行并按显示宽度补足空格清掉整行余留（重绘原地覆盖用，避免残影）。
function Write-MenuLine([string]$text, $color) {
    $w = [Console]::WindowWidth
    $dw = Get-DisplayWidth $text
    if ($dw -lt ($w - 1)) { $text = $text + (' ' * (($w - 1) - $dw)) }
    Write-Host $text -ForegroundColor $color
}

# ↑↓ 选择菜单。空串 '' = 不可选分隔空行（导航跳过）。
# 重绘时光标回到菜单顶端原地覆盖、隐藏光标 → 不闪烁。
function Select-Menu {
    param([string]$Title, [string[]]$Items, [string]$Hint, [int]$Start = 0, [hashtable]$Colors)
    $nextSel = {
        param($i, $d)
        do { $i = ($i + $d + $Items.Count) % $Items.Count } while ($Items[$i] -eq '')
        $i
    }
    $idx = $Start
    if ($Items[$idx] -eq '') { $idx = & $nextSel $idx 1 }

    # 非交互/无法操作控制台时的回退：渲染一次 + Read-Host
    $canConsole = $true
    try { $null = [Console]::CursorVisible } catch { $canConsole = $false }
    if (-not $canConsole) {
        Write-Host ''
        if ($Title) { Write-Host "  $Title" -ForegroundColor Cyan; Write-Host '' }
        for ($i = 0; $i -lt $Items.Count; $i++) { if ($Items[$i] -ne '') { Write-Host ("   {0}. {1}" -f ($i + 1), $Items[$i]) } }
        $n = (Read-Host '  输入序号 (q 取消)').Trim()
        if ($n -eq 'q') { return -1 }
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $Items.Count -and $Items[[int]$n - 1] -ne '') { return [int]$n - 1 }
        return -1
    }

    Clear-Host
    $top = [Console]::CursorTop
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            [Console]::SetCursorPosition(0, $top)
            Write-MenuLine '' 'Gray'
            if ($Title) { Write-MenuLine "  $Title" 'Cyan'; Write-MenuLine '' 'Gray' }
            for ($i = 0; $i -lt $Items.Count; $i++) {
                if ($Items[$i] -eq '') { Write-MenuLine '' 'Gray'; continue }
                if ($i -eq $idx)       { Write-MenuLine ("   ▶ {0}" -f $Items[$i]) 'Green'; continue }
                $fg = if ($Colors -and $Colors.ContainsKey($i)) { $Colors[$i] } else { 'Gray' }
                Write-MenuLine ("     {0}" -f $Items[$i]) $fg
            }
            Write-MenuLine '' 'Gray'
            if ($Hint) { Write-MenuLine "  $Hint" 'DarkGray' }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $idx = & $nextSel $idx -1 }
                'DownArrow' { $idx = & $nextSel $idx 1 }
                'Enter'     { return $idx }
                'Escape'    { return -1 }
                default {
                    $ch = $key.KeyChar
                    if ($ch -match '^\d$') { $n = [int]"$ch"; if ($n -ge 1 -and $n -le $Items.Count -and $Items[$n - 1] -ne '') { return $n - 1 } }
                    if ($ch -eq 'q') { return -1 }
                }
            }
        }
    }
    finally { [Console]::CursorVisible = $true }
}

# ============================================================
#  表单式编辑（一屏显示全部字段，选序号改单项）
# ============================================================
function Pick-BaseUrl($current, $store) {
    $entries = @()
    $seen = New-Object System.Collections.Generic.HashSet[string]
    # 1) 预置（含赞助商，带标记）
    foreach ($p in $script:BaseUrlPresets) {
        $u = [string]$p.url
        $entries += @{ label = ('{0,-18} {1}' -f $p.name, $(if ($u) { $u } else { '(空)' })); url = $u }
        [void]$seen.Add($u)
    }
    # 2) 自动收录已有档案里用过的地址
    if ($store) {
        foreach ($prov in $store.providers) {
            $u = (Get-ProviderEnvMap $prov)['ANTHROPIC_BASE_URL']
            if (-not [string]::IsNullOrWhiteSpace($u) -and -not $seen.Contains($u)) {
                [void]$seen.Add($u)
                $entries += @{ label = ('{0,-18} {1}' -f "(已有:$($prov.name))", $u); url = $u }
            }
        }
    }
    $items = @($entries.label) + '手动输入…' + '不修改'
    $sel = Select-Menu -Title "API 地址（当前：$(if($current){$current}else{'(空)'})）" -Items $items -Hint '↑↓ 选择 · Enter 确认 · q 不改'
    if ($sel -lt 0 -or $sel -eq $items.Count - 1) { return $current }   # q/Esc 或“不修改”
    if ($sel -lt $entries.Count) { return [string]$entries[$sel].url }
    $v = Read-Host '    手动输入 API 地址（回车=不改，- =清空）'        # “手动输入…”
    if ($v -eq '')  { return $current }
    if ($v -eq '-') { return '' }
    return $v.Trim()
}

# 可取消的文本输入：Esc=取消(不改)，回车空=不改，输入 - 回车=清空；支持退格与粘贴。
# 仅用于纯英文内容（密钥/模型）；中文字段（名称/备注）用 Read-Host 以兼容输入法。
function Read-Value {
    param([string]$Label, [string]$Current, [switch]$Secret)
    Write-Host ''
    Write-Host "  $Label" -ForegroundColor White
    $cur = if ([string]::IsNullOrEmpty($Current)) { '(空)' } elseif ($Secret) { '********' } else { $Current }
    Write-Host "  当前：$cur" -ForegroundColor DarkGray
    Write-Host "  回车=不改 · 输入/粘贴=替换 · 输入 - 回车=清空 · Esc=取消" -ForegroundColor DarkGray
    $canKey = $true
    try { $null = [Console]::KeyAvailable } catch { $canKey = $false }
    if (-not $canKey) {
        $v = Read-Host '  >'
        if ($v -eq '')  { return [pscustomobject]@{ Changed = $false } }
        if ($v -eq '-') { return [pscustomobject]@{ Changed = $true; Value = '' } }
        return [pscustomobject]@{ Changed = $true; Value = $v }
    }
    $buf = [System.Text.StringBuilder]::new()
    Write-Host -NoNewline '  > '
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') {
            Write-Host ''
            $s = $buf.ToString()
            if ($s -eq '')  { return [pscustomobject]@{ Changed = $false } }
            if ($s -eq '-') { return [pscustomobject]@{ Changed = $true; Value = '' } }
            return [pscustomobject]@{ Changed = $true; Value = $s }
        }
        elseif ($k.Key -eq 'Escape') {
            Write-Host '   (已取消，未修改)' -ForegroundColor DarkGray
            return [pscustomobject]@{ Changed = $false }
        }
        elseif ($k.Key -eq 'Backspace') {
            if ($buf.Length -gt 0) { [void]$buf.Remove($buf.Length - 1, 1); Write-Host -NoNewline "`b `b" }
        }
        elseif ($k.KeyChar -and [int]$k.KeyChar -ge 32) {
            [void]$buf.Append($k.KeyChar)
            Write-Host -NoNewline $(if ($Secret) { '*' } else { [string]$k.KeyChar })
        }
    }
}

function Pick-Auth($current) {
    $items = @('AUTH_TOKEN  （Bearer，多数第三方中转）', 'API_KEY  （x-api-key，官方/少数）', '不修改')
    $sel = Select-Menu -Title "认证字段（当前：$current）" -Items $items -Hint '↑↓ 选择 · Enter 确认 · q 不改'
    switch ($sel) { 0 { 'AUTH_TOKEN' } 1 { 'API_KEY' } default { $current } }
}

function Pick-Effort($current) {
    $opts  = @('low', 'medium', 'high', 'xhigh', 'max', 'auto')
    $items = @($opts) + '留空（不设）' + '不修改'
    $sel = Select-Menu -Title "effort 思考档（当前：$(if($current){$current}else{'(空)'})）" -Items $items -Hint '越往后越深入；auto=模型默认 · q 不改'
    if ($sel -lt 0 -or $sel -eq $items.Count - 1) { return $current }
    if ($sel -eq $opts.Count) { return '' }
    return $opts[$sel]
}

function Edit-Form($prov, $store) {
    $map = Get-ProviderEnvMap $prov
    $usesApiKey = -not [string]::IsNullOrWhiteSpace($map['ANTHROPIC_API_KEY'])
    $W = @{
        name   = $prov.name
        note   = Get-Note $prov
        base   = $map['ANTHROPIC_BASE_URL']
        auth   = $(if ($usesApiKey) { 'API_KEY' } else { 'AUTH_TOKEN' })
        token  = $(if ($usesApiKey) { $map['ANTHROPIC_API_KEY'] } else { $map['ANTHROPIC_AUTH_TOKEN'] })
        opus   = $map['ANTHROPIC_DEFAULT_OPUS_MODEL']
        sonnet = $map['ANTHROPIC_DEFAULT_SONNET_MODEL']
        haiku  = $map['ANTHROPIC_DEFAULT_HAIKU_MODEL']
        effort = $map['CLAUDE_CODE_EFFORT_LEVEL']
    }
    function _v($x) { if ([string]::IsNullOrWhiteSpace($x)) { '(空)' } else { $x } }
    while ($true) {
        $rows = @(
            ('名称          : {0}' -f (_v $W.name)),
            ('备注          : {0}' -f (_v $W.note)),
            ('API 地址      : {0}' -f (_v $W.base)),
            ('认证字段      : {0}' -f $W.auth),
            ('API 密钥      : {0}' -f $(if ([string]::IsNullOrWhiteSpace($W.token)) { '(空)' } else { '********' })),
            ('opus  → 模型  : {0}' -f (_v $W.opus)),
            ('sonnet→ 模型  : {0}' -f (_v $W.sonnet)),
            ('haiku → 模型  : {0}' -f (_v $W.haiku)),
            ('effort 思考档 : {0}' -f (_v $W.effort))
        )
        $items = @($rows) + '' + '保存并返回' + '放弃修改'   # '' = 分隔空行（与上方拉开距离）
        $sel = Select-Menu -Title '编辑档案  （↑↓ 选要改的项，Enter 进入；↓到底可选保存/放弃）' -Items $items -Hint '输入项内：Esc 取消该项 · 回车不改 · 输入 - 清空'
        switch ($sel) {
            0 { $v = Read-Host '  名称（回车=不改）'; if (-not [string]::IsNullOrWhiteSpace($v)) { $W.name = $v.Trim() } }
            1 { $v = Read-Host '  备注（回车=不改，- =清空）'; if ($v -eq '-') { $W.note = '' } elseif (-not [string]::IsNullOrWhiteSpace($v)) { $W.note = $v.Trim() } }
            2 { $W.base   = Pick-BaseUrl $W.base $store }
            3 { $W.auth   = Pick-Auth $W.auth }
            4 { $r = Read-Value -Label 'API 密钥' -Current $W.token -Secret;        if ($r.Changed) { $W.token  = $r.Value } }
            5 { $r = Read-Value -Label 'opus  映射模型' -Current $W.opus;            if ($r.Changed) { $W.opus   = $r.Value } }
            6 { $r = Read-Value -Label 'sonnet 映射模型' -Current $W.sonnet;          if ($r.Changed) { $W.sonnet = $r.Value } }
            7 { $r = Read-Value -Label 'haiku 映射模型（含后台任务）' -Current $W.haiku; if ($r.Changed) { $W.haiku  = $r.Value } }
            8 { $W.effort = Pick-Effort $W.effort }
            10 {
                $fields = @{ 'ANTHROPIC_BASE_URL' = $W.base
                             'ANTHROPIC_DEFAULT_OPUS_MODEL' = $W.opus
                             'ANTHROPIC_DEFAULT_SONNET_MODEL' = $W.sonnet
                             'ANTHROPIC_DEFAULT_HAIKU_MODEL' = $W.haiku
                             'CLAUDE_CODE_EFFORT_LEVEL' = $W.effort }
                if ($W.auth -eq 'API_KEY') { $fields['ANTHROPIC_API_KEY'] = $W.token } else { $fields['ANTHROPIC_AUTH_TOKEN'] = $W.token }
                $prov.name = $W.name
                $prov.env  = Build-ProviderEnv $fields
                Set-Note $prov ($W.note)
                return $true
            }
            default { return $false }
        }
    }
}

function New-Provider($store) {
    $prov = [PSCustomObject]@{ name = '新档案'; note = ''; env = [PSCustomObject]@{} }
    if (Edit-Form $prov $store) {
        if ($store.providers | Where-Object { $_.name -eq $prov.name }) {
            Write-Host "  已存在同名档案，未保存。" -ForegroundColor Yellow; Start-Sleep 1; return
        }
        $store.providers += $prov
        Save-Store $store
    }
}

# ============================================================
#  动作菜单（选中某档案后）
# ============================================================
function Action-Menu($store, $prov) {
    $opts = @(
        '本次启用    — 仅当前终端，立即启动 Claude（并行多终端推荐）',
        '设为默认    — 新终端裸敲 claude 默认用它（不影响运行中会话）',
        '编辑',
        '删除',
        '返回'
    )
    $a = Select-Menu -Title "档案：$($prov.name)    [$(Show-State $prov)]" -Items $opts -Hint '↑↓ 选择 · Enter 确认 · q 返回'
    switch ($a) {
        0 { Session-Launch $store $prov }
        1 { Set-Default $store $prov; Read-Host '  回车继续' | Out-Null }
        2 { if (Edit-Form $prov $store) { Save-Store $store } }
        3 {
            if ($prov.name -eq '官方') { Write-Host '  建议保留『官方』。' -ForegroundColor Yellow; Start-Sleep 1 }
            $ans = Read-Host "  确认删除 [$($prov.name)]? (y/N)"
            if ($ans -eq 'y' -or $ans -eq 'Y') {
                $store.providers = @($store.providers | Where-Object { $_.name -ne $prov.name })
                Save-Store $store
            }
        }
        default { }
    }
}

# ============================================================
#  主菜单
# ============================================================
function Main-Menu($store) {
    while ($true) {
        $labels = @()
        foreach ($p in $store.providers) {
            $cur  = if ($p.name -eq $store.current) { '（默认）' } else { '' }
            $note = $(if (Get-Note $p) { "  — $(Get-Note $p)" } else { '' })
            $labels += ('{0}{1}[{2}]{3}' -f (Pad-Display $p.name 16), (Pad-Display $cur 8), (Show-State $p), $note)
        }
        $n = $store.providers.Count
        $items  = @($labels) + '' + '＋ 新增档案' + '' + '退出'
        $colors = @{ ($n + 1) = 'Yellow' }   # 「＋ 新增档案」用亮黄色突出
        $sel = Select-Menu -Title "ccx v$($script:Version) · Claude Code API 切换器     （默认 = 新终端裸敲 claude 用的）" -Items $items -Colors $colors -Hint '↑↓ 选择 · Enter 进入 · q 退出'
        if ($sel -lt 0 -or $sel -eq $n + 3) { break }       # 退出 / Esc
        elseif ($sel -eq $n + 1) { New-Provider $store }     # 新增
        else { Action-Menu $store $store.providers[$sel] }   # 选中某档案
    }
}

# ============================================================
#  入口
# ============================================================
$store = Get-Store

if ($List) {
    Write-Host ''
    Write-Host "  默认档案：$($store.current)" -ForegroundColor White
    foreach ($p in $store.providers) {
        $mark = if ($p.name -eq $store.current) { '▶' } else { ' ' }
        $note = $(if (Get-Note $p) { "  — $(Get-Note $p)" } else { '' })
        Write-Host ("   {0} {1}[{2}]{3}" -f $mark, (Pad-Display $p.name 18), (Show-State $p), $note)
    }
    Write-Host ''
    return
}

if ($Switch) {
    $target = $store.providers | Where-Object { $_.name -eq $Switch } | Select-Object -First 1
    if (-not $target) {
        Write-Host "  找不到档案：$Switch" -ForegroundColor Red
        Write-Host "  现有：$($store.providers.name -join ', ')" -ForegroundColor DarkGray
        exit 1
    }
    if ($Session) { Session-Launch $store $target } else { Set-Default $store $target }
    return
}

Main-Menu $store
