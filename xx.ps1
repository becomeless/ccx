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
function Select-Menu {
    param([string]$Title, [string[]]$Items, [string]$Hint, [int]$Start = 0)
    $idx = $Start
    while ($true) {
        Clear-Host
        Write-Host ''
        if ($Title) { Write-Host "  $Title" -ForegroundColor Cyan; Write-Host '' }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($i -eq $idx) { Write-Host ("   ▶ {0}" -f $Items[$i]) -ForegroundColor Green }
            else             { Write-Host ("     {0}" -f $Items[$i]) -ForegroundColor Gray }
        }
        Write-Host ''
        if ($Hint) { Write-Host "  $Hint" -ForegroundColor DarkGray }
        try { $key = [Console]::ReadKey($true) }
        catch {
            $n = (Read-Host '  输入序号选择 (q 取消)').Trim()
            if ($n -eq 'q') { return -1 }
            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $Items.Count) { return [int]$n - 1 }
            continue
        }
        switch ($key.Key) {
            'UpArrow'   { $idx = ($idx - 1 + $Items.Count) % $Items.Count }
            'DownArrow' { $idx = ($idx + 1) % $Items.Count }
            'Enter'     { return $idx }
            'Escape'    { return -1 }
            default {
                $ch = $key.KeyChar
                if ($ch -match '^\d$') { $n = [int]"$ch"; if ($n -ge 1 -and $n -le $Items.Count) { return $n - 1 } }
                if ($ch -eq 'q') { return -1 }
            }
        }
    }
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
        Clear-Host
        Write-Host "`n  —— 编辑档案 —— `n" -ForegroundColor Cyan
        Write-Host ("   1. 名称          : {0}" -f (_v $W.name))
        Write-Host ("   2. 备注          : {0}" -f (_v $W.note))
        Write-Host ("   3. API 地址      : {0}" -f (_v $W.base))
        Write-Host ("   4. 认证字段      : {0}" -f $W.auth)
        Write-Host ("   5. API 密钥      : {0}" -f $(if ([string]::IsNullOrWhiteSpace($W.token)) { '(空)' } else { '********' }))
        Write-Host ("   6. opus  → 模型  : {0}" -f (_v $W.opus))
        Write-Host ("   7. sonnet→ 模型  : {0}" -f (_v $W.sonnet))
        Write-Host ("   8. haiku → 模型  : {0}  (含后台任务)" -f (_v $W.haiku))
        Write-Host ("   9. effort 思考档 : {0}  (low/medium/high/xhigh/max/auto，留空=不设)" -f (_v $W.effort))
        Write-Host "`n  输序号修改该项（进去后回车=不改本项），s=保存，c=取消" -ForegroundColor DarkGray
        $c = (Read-Host '  >').Trim().ToLower()
        switch ($c) {
            's' {
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
            'c' { return $false }
            '1' { $v = Read-Host '    新名称（回车=不改）'; if (-not [string]::IsNullOrWhiteSpace($v)) { $W.name = $v.Trim() } }
            '2' { $v = Read-Host '    备注（回车=不改，- =清空）'; if ($v -eq '-') { $W.note = '' } elseif (-not [string]::IsNullOrWhiteSpace($v)) { $W.note = $v.Trim() } }
            '3' { $W.base = Pick-BaseUrl $W.base $store }
            '4' {
                $a = (Read-Host '    认证字段  1=AUTH_TOKEN(Bearer,多数中转)  2=API_KEY(官方/少数)  (回车=不改)').Trim()
                if ($a -eq '1') { $W.auth = 'AUTH_TOKEN' } elseif ($a -eq '2') { $W.auth = 'API_KEY' }
            }
            '5' { $v = Read-Host '    API 密钥（回车=不改，- =清空）'; if ($v -eq '-') { $W.token = '' } elseif ($v -ne '') { $W.token = $v } }
            '6' { $v = (Read-Host '    opus 映射模型（回车=不改，- =清空）').Trim();   if ($v -eq '-') { $W.opus = '' }   elseif ($v -ne '') { $W.opus = $v } }
            '7' { $v = (Read-Host '    sonnet 映射模型（回车=不改，- =清空）').Trim(); if ($v -eq '-') { $W.sonnet = '' } elseif ($v -ne '') { $W.sonnet = $v } }
            '8' { $v = (Read-Host '    haiku 映射模型（回车=不改，- =清空）').Trim();  if ($v -eq '-') { $W.haiku = '' }  elseif ($v -ne '') { $W.haiku = $v } }
            '9' { $v = (Read-Host '    effort（low/medium/high/xhigh/max/auto，回车=不改，- =清空）').Trim(); if ($v -eq '-') { $W.effort = '' } elseif ($v -ne '') { $W.effort = $v } }
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
            $labels += ('{0,-14}{1,-8}[{2}]{3}' -f $p.name, $cur, (Show-State $p), $note)
        }
        $labels += '＋ 新增档案'
        $labels += '退出'
        $sel = Select-Menu -Title 'Claude Code API 切换器     （默认 = 新终端裸敲 claude 用的）' -Items $labels -Hint '↑↓ 选择 · Enter 进入 · q 退出'
        if ($sel -lt 0 -or $sel -eq $labels.Count - 1) { break }
        elseif ($sel -eq $store.providers.Count) { New-Provider $store }
        else { Action-Menu $store $store.providers[$sel] }
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
        Write-Host ("   {0} {1,-14}[{2}]{3}" -f $mark, $p.name, (Show-State $p), $note)
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
