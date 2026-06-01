# ccx — Claude Code API switcher (PowerShell Gallery module)
#
# 这是一层很薄的包装：把随模块发布的 xx.ps1 作为命令 `xx` 暴露出来。
# 用独立子进程运行，保证「本次启用」的环境变量只作用于该进程，不污染当前 shell。

function xx {
    pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'xx.ps1') @args
}

Export-ModuleMember -Function xx
