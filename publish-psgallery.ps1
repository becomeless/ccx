# 发布 ccx 到 PowerShell Gallery。
#
# 你需要先在 https://www.powershellgallery.com 用微软账号登录，
# 在 Account → API Keys 生成一个 API Key。
#
# 然后运行：
#   pwsh -File publish-psgallery.ps1 -ApiKey <你的APIKey>
#
# 发布后，任何人即可：
#   Install-Module ccx          # 安装
#   xx                          # 直接使用（模块会自动加载）

param(
    [Parameter(Mandatory)][string]$ApiKey
)

$root  = $PSScriptRoot
$stage = Join-Path $env:TEMP 'ccx-psgallery'
$mod   = Join-Path $stage 'ccx'

# 准备一个干净的发布目录（只放模块需要的文件，不含 .git / 文档以外的杂项）
if (Test-Path $stage) { [System.IO.Directory]::Delete($stage, $true) }
New-Item -ItemType Directory -Path $mod -Force | Out-Null
foreach ($f in 'ccx.psd1','ccx.psm1','xx.ps1','presets.json','LICENSE','README.md') {
    Copy-Item (Join-Path $root $f) (Join-Path $mod $f) -Force
}

# 发布前自检
Test-ModuleManifest (Join-Path $mod 'ccx.psd1') | Out-Null
Write-Host "清单校验通过，开始发布…" -ForegroundColor Cyan

# 用新一代 PSResourceGet 发布：它内置 NuGet 客户端，不解析 NuGet.exe 文字输出，
# 因此能避开 PowerShellGet 2.x 在中文/本地化环境下 “Cannot index into a null array” 的老 bug。
if (Get-Command Publish-PSResource -ErrorAction SilentlyContinue) {
    Publish-PSResource -Path $mod -Repository PSGallery -ApiKey $ApiKey -Verbose
} else {
    # 兜底：老命令（英文环境下才稳）
    Publish-Module -Path $mod -NuGetApiKey $ApiKey -Repository PSGallery -Verbose
}
Write-Host "✓ 已发布。几分钟后可：Install-Module ccx  或  Install-PSResource ccx（命令仍是 xx）。" -ForegroundColor Green
