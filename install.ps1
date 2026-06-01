# 安装 xx：在 PowerShell $PROFILE 注册 `xx` 命令（任意终端可用）。
# 可重复运行，幂等。卸载见 README。

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1  = Join-Path $here 'xx.ps1'

$marker = '# >>> xx >>>'
$endmk  = '# <<< xx <<<'
$func = "$marker`r`nfunction xx { pwsh -NoProfile -ExecutionPolicy Bypass -File `"$ps1`" @args }`r`n$endmk"

if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
$content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = '' }

# 清理旧的 ccswitch 残留块（若曾安装过旧版）
$legacy = '# >>> ccswitch >>>' + '[\s\S]*?' + '# <<< ccswitch <<<'
$content = [regex]::Replace($content, $legacy, '').Trim()

if ($content -match [regex]::Escape($marker)) {
    $pattern = [regex]::Escape($marker) + '[\s\S]*?' + [regex]::Escape($endmk)
    $content = [regex]::Replace($content, $pattern, $func)
} else {
    $content = ($content.TrimEnd() + "`r`n`r`n" + $func + "`r`n").TrimStart()
}
[System.IO.File]::WriteAllText($PROFILE, $content, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  ✓ 已在 $PROFILE 注册 xx 命令" -ForegroundColor Green

Write-Host ''
Write-Host '  完成！重开一个终端后输入  xx  打开菜单，或  xx DeepSeek  直接切换。' -ForegroundColor White
