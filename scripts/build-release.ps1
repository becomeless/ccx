param(
  [string]$Version = "",
  [string]$OutDir = "dist\release",
  [string]$GoExe = "",
  [string[]]$Platforms = @("windows/amd64", "darwin/amd64", "darwin/arm64", "linux/amd64", "linux/arm64")
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

function Assert-ChildPath {
  param([string]$Parent, [string]$Child)

  $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $childFull = [IO.Path]::GetFullPath($Child)
  $prefix = $parentFull + [IO.Path]::DirectorySeparatorChar
  if (-not $childFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write outside output directory: $childFull"
  }
}

function Copy-ReleaseFiles {
  param([string]$StageDir)

  foreach ($name in @("presets.json", "LICENSE", "README.md", "README.en.md")) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $name) -Destination $StageDir -Force
  }
}

function New-TarGz {
  param([string]$SourceDir, [string]$Destination)

  $tar = Get-Command tar -ErrorAction SilentlyContinue
  if (-not $tar) {
    throw "tar was not found. It is required to create .tar.gz assets."
  }
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Force
  }
  $parent = Split-Path -Parent $SourceDir
  $leaf = Split-Path -Leaf $SourceDir
  & $tar.Source -czf $Destination -C $parent $leaf
}

function Test-CanRunBinary {
  param([string]$Goos, [string]$Goarch)

  $os = ""
  if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    $os = "windows"
  }
  elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
    $os = "darwin"
  }
  elseif ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
    $os = "linux"
  }

  $archName = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
  $arch = switch ($archName) {
    "x64" { "amd64" }
    "arm64" { "arm64" }
    default { $archName }
  }

  return $Goos -eq $os -and $Goarch -eq $arch
}

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$go = Resolve-GoExe $GoExe
$versionValue = Resolve-Version $Version

$outFull = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutDir))
New-Item -ItemType Directory -Force -Path $outFull | Out-Null

$assets = @()
$oldGoos = $env:GOOS
$oldGoarch = $env:GOARCH
$oldCgo = $env:CGO_ENABLED
try {
  foreach ($platform in $Platforms) {
    if ($platform -notmatch "^([^/]+)/([^/]+)$") {
      throw "Invalid platform '$platform'. Expected GOOS/GOARCH, for example darwin/arm64."
    }
    $goos = $Matches[1]
    $goarch = $Matches[2]
    $assetName = "ccx_${versionValue}_${goos}_${goarch}"
    $stageFull = [IO.Path]::GetFullPath((Join-Path $outFull $assetName))
    Assert-ChildPath $outFull $stageFull

    if (Test-Path -LiteralPath $stageFull) {
      Remove-Item -LiteralPath $stageFull -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $stageFull | Out-Null

    $binName = if ($goos -eq "windows") { "xx.exe" } else { "xx" }
    $binFull = Join-Path $stageFull $binName
    $env:GOOS = $goos
    $env:GOARCH = $goarch
    $env:CGO_ENABLED = "0"
    & $go build -trimpath -ldflags "-s -w -X main.version=$versionValue" -o $binFull ".\cmd\xx"
    Copy-ReleaseFiles $stageFull

    if ($goos -eq "windows") {
      $archiveFull = Join-Path $outFull "$assetName.zip"
      if (Test-Path -LiteralPath $archiveFull) {
        Remove-Item -LiteralPath $archiveFull -Force
      }
      Compress-Archive -LiteralPath $stageFull -DestinationPath $archiveFull -Force
    }
    else {
      $archiveFull = Join-Path $outFull "$assetName.tar.gz"
      New-TarGz $stageFull $archiveFull
    }
    $assets += $archiveFull

    if (Test-CanRunBinary $goos $goarch) {
      $reportedVersion = & $binFull --version
      if ($reportedVersion.Trim() -ne $versionValue) {
        throw "Built binary reports version '$reportedVersion', expected '$versionValue'."
      }
    }
  }
}
finally {
  $env:GOOS = $oldGoos
  $env:GOARCH = $oldGoarch
  $env:CGO_ENABLED = $oldCgo
}

foreach ($installer in @("install.ps1", "install.sh")) {
  $src = Join-Path $RepoRoot $installer
  if (Test-Path -LiteralPath $src) {
    $dest = Join-Path $outFull $installer
    Copy-Item -LiteralPath $src -Destination $dest -Force
    $assets += $dest
  }
}

$checksumFull = Join-Path $outFull "checksums.txt"
$checksumLines = foreach ($asset in $assets) {
  $hash = Get-FileHash -LiteralPath $asset -Algorithm SHA256
  "$($hash.Hash.ToLowerInvariant())  $(Split-Path -Leaf $asset)"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllLines($checksumFull, $checksumLines, $utf8NoBom)

foreach ($asset in $assets) {
  Write-Host "Built $(Split-Path -Leaf $asset)"
}
Write-Host "Wrote $checksumFull"
