param(
  [string]$Version = "",
  [string]$OutDir = "dist\release",
  [string]$GoExe = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-GoExe {
  param([string]$Requested)

  if ($Requested) {
    $resolved = Resolve-Path -LiteralPath $Requested -ErrorAction Stop
    return $resolved.Path
  }

  $cmd = Get-Command go -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $localGo = Join-Path $HOME "go-sdk\go\bin\go.exe"
  if (Test-Path -LiteralPath $localGo) {
    return $localGo
  }

  throw "Go executable was not found. Pass -GoExe or add go.exe to PATH."
}

function Resolve-Version {
  param([string]$Requested)

  $v = $Requested.Trim()
  if (-not $v -and $env:CCX_VERSION) {
    $v = $env:CCX_VERSION.Trim()
  }
  if (-not $v) {
    $packageFile = Join-Path $RepoRoot "package.json"
    if (Test-Path -LiteralPath $packageFile) {
      $pkg = Get-Content -LiteralPath $packageFile -Raw | ConvertFrom-Json
      $v = [string]$pkg.version
    }
  }

  $v = $v.Trim()
  if ($v.StartsWith("v")) {
    $v = $v.Substring(1)
  }
  if (-not $v) {
    throw "Version is required."
  }
  if ($v -match "\s") {
    throw "Version must not contain whitespace: '$v'"
  }
  return $v
}

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$go = Resolve-GoExe $GoExe
$versionValue = Resolve-Version $Version

$outFull = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutDir))
$assetName = "ccx_${versionValue}_windows_amd64"
$stageFull = [IO.Path]::GetFullPath((Join-Path $outFull $assetName))
$zipFull = Join-Path $outFull "$assetName.zip"
$checksumFull = Join-Path $outFull "checksums_windows_amd64.txt"
$installAssetFull = Join-Path $outFull "install.ps1"

if (-not $stageFull.StartsWith($outFull, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to stage outside output directory: $stageFull"
}

New-Item -ItemType Directory -Force -Path $outFull | Out-Null
if (Test-Path -LiteralPath $stageFull) {
  Remove-Item -LiteralPath $stageFull -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stageFull | Out-Null

$exeFull = Join-Path $stageFull "xx.exe"
$oldGoos = $env:GOOS
$oldGoarch = $env:GOARCH
try {
  $env:GOOS = "windows"
  $env:GOARCH = "amd64"
  & $go build -trimpath -ldflags "-s -w -X main.version=$versionValue" -o $exeFull ".\cmd\xx"
}
finally {
  $env:GOOS = $oldGoos
  $env:GOARCH = $oldGoarch
}

Copy-Item -LiteralPath (Join-Path $RepoRoot "presets.json") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "LICENSE") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "README.md") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "README.en.md") -Destination $stageFull -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "install.ps1") -Destination $installAssetFull -Force

if (Test-Path -LiteralPath $zipFull) {
  Remove-Item -LiteralPath $zipFull -Force
}
Compress-Archive -LiteralPath $stageFull -DestinationPath $zipFull -Force

$zipHash = Get-FileHash -LiteralPath $zipFull -Algorithm SHA256
$installerHash = Get-FileHash -LiteralPath $installAssetFull -Algorithm SHA256
$checksumLines = @(
  "$($zipHash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $zipFull)"
  "$($installerHash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $installAssetFull)"
)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($checksumFull, $checksumLines, $utf8NoBom)

$reportedVersion = & $exeFull --version
if ($reportedVersion.Trim() -ne $versionValue) {
  throw "Built binary reports version '$reportedVersion', expected '$versionValue'."
}

Write-Host "Built $zipFull"
Write-Host "Copied $installAssetFull"
Write-Host "Wrote $checksumFull"
