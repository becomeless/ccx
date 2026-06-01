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
#    pwsh -File xx.ps1 -List                 # 列出所有配置
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
$script:Version      = '0.2.1'   # 发版时同步更新（与 ccx.psd1 的 ModuleVersion 保持一致）

# 受管钥匙：工具完全拥有这些键，启用时按目标配置 设置/清除，其它变量一律不动。
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

# 供应商目录：优先读脚本同目录的 presets.json，缺失则用内置兜底。
# 每个供应商含：name、auth（认证字段）、urls（可多个 API 地址）、models（推荐三档映射）、effort（可选）。
$BuiltinPresetsJson = @'
[
  {
    "name": "DeepSeek",
    "auth": "AUTH_TOKEN",
    "effort": "max",
    "urls": [ { "label": "Anthropic 兼容", "url": "https://api.deepseek.com/anthropic" } ],
    "models": { "opus": "deepseek-v4-pro", "sonnet": "deepseek-v4-pro", "haiku": "deepseek-v4-flash" }
  },
  {
    "name": "智谱GLM",
    "auth": "AUTH_TOKEN",
    "urls": [ { "label": "Anthropic 兼容", "url": "https://open.bigmodel.cn/api/anthropic" } ],
    "models": { "opus": "GLM-4.7", "sonnet": "GLM-4.7", "haiku": "glm-4.5-air" }
  },
  {
    "name": "小米MiMo",
    "auth": "AUTH_TOKEN",
    "urls": [
      { "label": "按量付费API", "url": "https://api.xiaomimimo.com/anthropic" },
      { "label": "TokenPlan", "url": "https://token-plan-cn.xiaomimimo.com/anthropic" }
    ],
    "models": { "opus": "mimo-v2.5-pro", "sonnet": "mimo-v2.5-pro", "haiku": "mimo-v2.5-pro" }
  },
  {
    "name": "官方Anthropic",
    "auth": "API_KEY",
    "urls": [ { "label": "(留空，用登录态)", "url": "" } ],
    "models": {}
  }
]
'@
$presetsFile = Join-Path $PSScriptRoot 'presets.json'
$script:ProviderCatalog = @(
    if (Test-Path $presetsFile) {
        try { Get-Content -Raw -Path $presetsFile | ConvertFrom-Json } catch { $BuiltinPresetsJson | ConvertFrom-Json }
    } else { $BuiltinPresetsJson | ConvertFrom-Json }
)

# 默认配置（effort 按各家文档：官方留空、DeepSeek=max、GLM/MiMo 留空）
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
#  配置存取
# ============================================================
function Save-Store($store) {
    if (-not (Test-Path $script:StoreDir)) { New-Item -ItemType Directory -Path $script:StoreDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($script:StorePath, ($store | ConvertTo-Json -Depth 100), $Utf8NoBom)
}
function Get-Store {
    if (Test-Path $script:StorePath) { return Get-Content -Raw -Path $script:StorePath | ConvertFrom-Json }
    $store = $DefaultStoreJson | ConvertFrom-Json
    Save-Store $store
    Write-Host "  已在 $($script:StorePath) 生成默认配置（含官方 + 三个第三方，密钥待填）。" -ForegroundColor DarkGray
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

# 通知系统“用户环境变量变了”，让之后新开的终端能读到（不影响已运行进程）。
# 用自己的 SendMessageTimeout：SMTO_ABORTIFHUNG + 100ms 短超时，卡住的窗口立即跳过——
# 比 .NET SetEnvironmentVariable 内部那次「每窗口 1000ms」的广播快得多。
function Invoke-EnvBroadcast {
    if (-not ('Ccx.Native' -as [type])) {
        try {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Ccx {
  public static class Native {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    public static void NotifyEnvChange() {
      UIntPtr r;
      // HWND_BROADCAST=0xffff, WM_SETTINGCHANGE=0x001A, SMTO_ABORTIFHUNG=0x0002, 100ms
      SendMessageTimeout((IntPtr)0xffff, 0x001A, UIntPtr.Zero, "Environment", 0x0002, 100, out r);
    }
  }
}
'@
        } catch { return }
    }
    try { [Ccx.Native]::NotifyEnvChange() } catch { }
}

# 写用户环境变量（仅 User 作用域用此快路径）：
#   直接写 HKCU:\Environment 注册表（瞬时、不广播），最后只做一次短超时广播。
#   对比逐个 [Environment]::SetEnvironmentVariable(_, _, 'User')：那会广播 7 次、每次每窗口
#   等到 1s，窗口一多就拖到好几秒。
function Set-UserEnv-Fast([string[]]$keys, [hashtable]$vals) {
    $reg = 'HKCU:\Environment'
    foreach ($k in $keys) {
        $v = $vals[$k]
        if ([string]::IsNullOrEmpty($v)) { Remove-ItemProperty -Path $reg -Name $k -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $reg -Name $k -Value $v -Type String }
    }
    Invoke-EnvBroadcast
}

# 设为默认：写用户环境变量（新终端裸 claude 生效；不影响运行中会话）
function Set-Default($store, $prov) {
    $envMap = Get-ProviderEnvMap $prov
    $noKey = [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_AUTH_TOKEN']) -and [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_API_KEY'])
    if ($prov.name -ne '官方' -and $noKey) { Write-Host "  ⚠ 配置 [$($prov.name)] 还没填密钥。" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  正在写入用户环境变量…" -ForegroundColor DarkGray

    $keys = @(Get-ManagedKeys)
    $vals = @{}
    foreach ($k in $keys) {
        $vals[$k] = if ($envMap.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($envMap[$k])) { $envMap[$k] } else { $null }
    }
    if ($script:DefaultScope -eq 'User' -and $IsWindows) {
        Set-UserEnv-Fast $keys $vals
    }
    else {
        foreach ($k in $keys) { [Environment]::SetEnvironmentVariable($k, $vals[$k], $script:DefaultScope) }
    }
    $store.current = $prov.name
    Save-Store $store

    Write-Host "  ✓ 已设为默认：$($prov.name)" -ForegroundColor Green
    Write-Host "    新开的终端裸敲  claude  就会用它；正在运行的会话不受影响。" -ForegroundColor White
    Write-Host "    （当前这个终端是旧环境，需【新开终端】才生效。）" -ForegroundColor DarkGray
    Write-Host ""
}

# 本次启用：仅当前进程设环境变量并启动 Claude（多终端隔离，阅后即焚）
function Session-Launch($store, $prov) {
    $envMap = Get-ProviderEnvMap $prov
    $noKey = [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_AUTH_TOKEN']) -and [string]::IsNullOrWhiteSpace($envMap['ANTHROPIC_API_KEY'])
    if ($prov.name -ne '官方' -and $noKey) { Write-Host "  ⚠ 配置 [$($prov.name)] 还没填密钥。" -ForegroundColor Yellow }

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
# 可选就地排序：传入 $OnMove（scriptblock，签名 {param($from,$to) …}，须完成数据交换并返回新的
# $Items 标签数组）与 $MovableCount（顶部前 N 项可排序）。Shift+↑↓ / PgUp·PgDn 移动选中项。
function Select-Menu {
    param([string]$Title, [string[]]$Items, [string]$Hint, [int]$Start = 0, [hashtable]$Colors,
          [scriptblock]$OnMove, [int]$MovableCount = 0)
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
            # 就地排序：Shift+↑↓ 或 PgUp/PgDn 把选中项在“可排序区”（顶部前 MovableCount 项）内上/下移。
            if ($OnMove) {
                $shift = ($key.Modifiers -band [ConsoleModifiers]::Shift) -ne 0
                $up    = ($key.Key -eq 'PageUp')   -or ($shift -and $key.Key -eq 'UpArrow')
                $down  = ($key.Key -eq 'PageDown') -or ($shift -and $key.Key -eq 'DownArrow')
                if ($up -and $idx -gt 0 -and $idx -lt $MovableCount) {
                    $Items = & $OnMove $idx ($idx - 1); $idx--; continue
                }
                if ($down -and $idx -lt ($MovableCount - 1)) {
                    $Items = & $OnMove $idx ($idx + 1); $idx++; continue
                }
            }
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
    # 1) 供应商目录里的所有 API 地址（一个供应商可有多个，带标签）
    foreach ($p in $script:ProviderCatalog) {
        foreach ($u in @($p.urls)) {
            $url = [string]$u.url
            $tag = if (@($p.urls).Count -gt 1) { "$($p.name)/$($u.label)" } else { [string]$p.name }
            $entries += @{ label = ('{0,-20} {1}' -f $tag, $(if ($url) { $url } else { '(空)' })); url = $url }
            [void]$seen.Add($url)
        }
    }
    # 2) 自动收录已有配置里用过的地址
    if ($store) {
        foreach ($prov in $store.providers) {
            $u = (Get-ProviderEnvMap $prov)['ANTHROPIC_BASE_URL']
            if (-not [string]::IsNullOrWhiteSpace($u) -and -not $seen.Contains($u)) {
                [void]$seen.Add($u)
                $entries += @{ label = ('{0,-20} {1}' -f "(已有:$($prov.name))", $u); url = $u }
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

# 选供应商：从供应商目录里选一个（或“自定义”手填名字）。
# 返回供应商对象 / @{custom=$true} / $null（不改）。
function Pick-Provider($current) {
    $names = @($script:ProviderCatalog.name)
    $items = @($names) + '自定义（手动填名字）' + '不修改'
    $sel = Select-Menu -Title "供应商（当前：$(if($current){$current}else{'(未选)'})）" -Items $items -Hint '↑↓ 选择 · Enter 确认 · q 不改'
    if ($sel -lt 0 -or $sel -eq $items.Count - 1) { return $null }
    if ($sel -eq $names.Count) { return [pscustomobject]@{ custom = $true } }
    return $script:ProviderCatalog[$sel]
}

# 供应商有多个 API 地址时让用户选一个；只有一个则直接用，无地址则保持原值。
function Pick-ProviderUrl($pp, $current) {
    $urls = @($pp.urls)
    if ($urls.Count -eq 0) { return $current }
    if ($urls.Count -eq 1) { return [string]$urls[0].url }
    $labels = @($urls | ForEach-Object { '{0,-12} {1}' -f $_.label, $(if ($_.url) { $_.url } else { '(空)' }) })
    $items = @($labels) + '不修改'
    $sel = Select-Menu -Title "$($pp.name) 有多个 API 地址，选一个" -Items $items -Hint '↑↓ 选择 · Enter 确认 · q 不改'
    if ($sel -lt 0 -or $sel -eq $items.Count - 1) { return $current }
    return [string]$urls[$sel].url
}

# 名称去重：同名已被【其它】配置占用时自动追加 “ 2/3/…”。$exclude 为正在编辑的本条（排除自身）。
function Resolve-UniqueName($store, $name, $exclude) {
    $existing = @($store.providers | Where-Object { -not [object]::ReferenceEquals($_, $exclude) } | ForEach-Object { [string]$_.name })
    if ($existing -notcontains $name) { return $name }
    $i = 2
    while ($existing -contains "$name $i") { $i++ }
    return "$name $i"
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
    $sel = 0   # 记住上次选中项：改完一项 / 保存取消返回后，光标停在原处（不再跳回第一项）
    while ($true) {
        $rows = @(
            ('供应商        : {0}' -f (_v $W.name)),
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
        $sel = Select-Menu -Title '编辑配置  （↑↓ 选要改的项，Enter 进入；↓到底可选保存/放弃）' -Items $items -Start $sel -Hint '供应商：选后自动填地址/模型 · 备注随便写 · 项内 Esc 取消 · 回车不改 · - 清空'
        switch ($sel) {
            0 {
                $pp = Pick-Provider $W.name
                if ($pp -and $pp.custom) {
                    $v = Read-Host '  自定义供应商名称（回车=不改）'
                    if (-not [string]::IsNullOrWhiteSpace($v)) { $W.name = $v.Trim() }
                }
                elseif ($pp) {
                    $W.name = [string]$pp.name
                    if ($pp.auth) { $W.auth = [string]$pp.auth }
                    $W.base = Pick-ProviderUrl $pp $W.base
                    if ($pp.models) {
                        if ($pp.models.opus)   { $W.opus   = [string]$pp.models.opus }
                        if ($pp.models.sonnet) { $W.sonnet = [string]$pp.models.sonnet }
                        if ($pp.models.haiku)  { $W.haiku  = [string]$pp.models.haiku }
                    }
                    if (($pp.PSObject.Properties.Name -contains 'effort') -and $pp.effort) { $W.effort = [string]$pp.effort }
                }
            }
            1 { $v = Read-Host '  备注（回车=不改，- =清空）'; if ($v -eq '-') { $W.note = '' } elseif (-not [string]::IsNullOrWhiteSpace($v)) { $W.note = $v.Trim() } }
            2 { $W.base   = Pick-BaseUrl $W.base $store }
            3 { $W.auth   = Pick-Auth $W.auth }
            4 { $r = Read-Value -Label 'API 密钥' -Current $W.token -Secret;        if ($r.Changed) { $W.token  = $r.Value } }
            5 { $r = Read-Value -Label 'opus  映射模型' -Current $W.opus;            if ($r.Changed) { $W.opus   = $r.Value } }
            6 { $r = Read-Value -Label 'sonnet 映射模型' -Current $W.sonnet;          if ($r.Changed) { $W.sonnet = $r.Value } }
            7 { $r = Read-Value -Label 'haiku 映射模型（含后台任务）' -Current $W.haiku; if ($r.Changed) { $W.haiku  = $r.Value } }
            8 { $W.effort = Pick-Effort $W.effort }
            10 {
                if ([string]::IsNullOrWhiteSpace($W.name)) {
                    Write-Host "  还没选供应商（或自定义名称），未保存。" -ForegroundColor Yellow; Start-Sleep 1; continue
                }
                $fields = @{ 'ANTHROPIC_BASE_URL' = $W.base
                             'ANTHROPIC_DEFAULT_OPUS_MODEL' = $W.opus
                             'ANTHROPIC_DEFAULT_SONNET_MODEL' = $W.sonnet
                             'ANTHROPIC_DEFAULT_HAIKU_MODEL' = $W.haiku
                             'CLAUDE_CODE_EFFORT_LEVEL' = $W.effort }
                if ($W.auth -eq 'API_KEY') { $fields['ANTHROPIC_API_KEY'] = $W.token } else { $fields['ANTHROPIC_AUTH_TOKEN'] = $W.token }
                $prov.name = Resolve-UniqueName $store $W.name $prov   # 同供应商可多条，自动 “名 2/3…” 去重
                $prov.env  = Build-ProviderEnv $fields
                Set-Note $prov ($W.note)
                return $true
            }
            default { return $false }
        }
    }
}

function New-Provider($store) {
    $prov = [PSCustomObject]@{ name = ''; note = ''; env = [PSCustomObject]@{} }
    if (Edit-Form $prov $store) {
        $store.providers += $prov
        Save-Store $store
    }
}

# ============================================================
#  动作菜单（选中某配置后）
# ============================================================
function Action-Menu($store, $prov) {
    $opts = @(
        '本次启用    — 仅当前终端，立即启动 Claude（并行多终端推荐）',
        '设为默认    — 新终端裸敲 claude 默认用它（不影响运行中会话）',
        '编辑',
        '删除',
        '返回'
    )
    $note = $(if (Get-Note $prov) { "  — $(Get-Note $prov)" } else { '' })
    $a = Select-Menu -Title "配置：$($prov.name)$note    [$(Show-State $prov)]" -Items $opts -Hint '↑↓ 选择 · Enter 确认 · q 返回'
    switch ($a) {
        0 { Session-Launch $store $prov }
        1 { Set-Default $store $prov; Read-Host '  回车继续' | Out-Null }
        2 {
            $old = $prov.name
            if (Edit-Form $prov $store) {
                if ($store.current -eq $old) { $store.current = $prov.name }   # 改了供应商/名称时同步默认指向
                Save-Store $store
            }
        }
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
#  主菜单（配置列表可直接用 Shift+↑↓ / PgUp·PgDn 就地排序）
# ============================================================
function Main-Menu($store) {
    # 生成主菜单全部条目（配置列表 + 分隔 + 新增 + 退出）；排序后回调用它重建。
    $buildItems = {
        $labels = @()
        foreach ($p in $store.providers) {
            $cur  = if ($p.name -eq $store.current) { '（默认）' } else { '' }
            $note = $(if (Get-Note $p) { "  — $(Get-Note $p)" } else { '' })
            $labels += ('{0}{1}[{2}]{3}' -f (Pad-Display $p.name 16), (Pad-Display $cur 8), (Show-State $p), $note)
        }
        @($labels) + '' + '＋ 新增配置' + '' + '退出'
    }
    # 就地交换两个配置的顺序并持久化，返回重建后的条目。
    $onMove = {
        param($from, $to)
        $t = $store.providers[$from]; $store.providers[$from] = $store.providers[$to]; $store.providers[$to] = $t
        Save-Store $store
        & $buildItems
    }
    while ($true) {
        $n = $store.providers.Count
        $items  = & $buildItems
        $colors = @{ ($n + 1) = 'Yellow' }   # 「＋ 新增配置」用亮黄色突出
        $sel = Select-Menu -Title "ccx v$($script:Version) · Claude Code API 切换器     （默认 = 新终端裸敲 claude 用的）" `
            -Items $items -Colors $colors -OnMove $onMove -MovableCount $n `
            -Hint '↑↓ 选择 · Enter 进入 · Shift+↑↓（或 PgUp/PgDn）排序 · q 退出'
        if ($sel -lt 0 -or $sel -eq $n + 3) { break }        # 退出 / Esc
        elseif ($sel -eq $n + 1) { New-Provider $store }     # 新增
        else { Action-Menu $store $store.providers[$sel] }   # 选中某配置
    }
}

# ============================================================
#  入口
# ============================================================
$store = Get-Store

if ($List) {
    Write-Host ''
    Write-Host "  默认配置：$($store.current)" -ForegroundColor White
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
        Write-Host "  找不到配置：$Switch" -ForegroundColor Red
        Write-Host "  现有：$($store.providers.name -join ', ')" -ForegroundColor DarkGray
        exit 1
    }
    if ($Session) { Session-Launch $store $target } else { Set-Default $store $target }
    return
}

Main-Menu $store
