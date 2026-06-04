param(
  [string]$Version = "latest",
  [string]$InstallDir = "$env:LOCALAPPDATA\Programs\ccx",
  [string]$Repo = "becomeless/cc-x",
  [switch]$NoPath,
  [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Publish-EnvironmentChange {
  $signature = @"
using System;
using System.Runtime.InteropServices;
public static class CcxNativeMethods {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
  try {
    Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null
    $result = [UIntPtr]::Zero
    [CcxNativeMethods]::SendMessageTimeout(
      [IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, "Environment", 0x2, 100, [ref]$result
    ) | Out-Null
  }
  catch {
    # Best effort only. A newly opened terminal will read the updated PATH anyway.
  }
}

function Split-PathList {
  param([string]$Value)
  if (-not $Value) {
    return @()
  }
  return @($Value -split ";" | Where-Object { $_.Trim() })
}

function Normalize-PathForCompare {
  param([string]$Value)

  $expanded = [Environment]::ExpandEnvironmentVariables($Value)
  try {
    return [IO.Path]::GetFullPath($expanded).TrimEnd("\")
  }
  catch {
    return $expanded.Trim().TrimEnd("\")
  }
}

function Add-UserPath {
  param([string]$Dir)

  $full = Normalize-PathForCompare $Dir
  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = Split-PathList $current
  foreach ($part in $parts) {
    if ((Normalize-PathForCompare $part).Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }
  }
  $next = if ($current) { "$current;$full" } else { $full }
  [Environment]::SetEnvironmentVariable("Path", $next, "User")
  if ($env:Path -notlike "*$full*") {
    $env:Path = "$env:Path;$full"
  }
  Publish-EnvironmentChange
  return $true
}

function Remove-UserPath {
  param([string]$Dir)

  $full = Normalize-PathForCompare $Dir
  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  $parts = Split-PathList $current
  $kept = @()
  $removed = $false
  foreach ($part in $parts) {
    $partFull = Normalize-PathForCompare $part
    if ($partFull.Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
      $removed = $true
    }
    else {
      $kept += $part
    }
  }
  if ($removed) {
    [Environment]::SetEnvironmentVariable("Path", ($kept -join ";"), "User")
    Publish-EnvironmentChange
  }
  return $removed
}

function Get-Release {
  param([string]$RepoName, [string]$RequestedVersion)

  $headers = @{ "User-Agent" = "ccx-install.ps1" }
  if ($RequestedVersion -eq "latest") {
    $url = "https://api.github.com/repos/$RepoName/releases/latest"
  }
  else {
    $tag = if ($RequestedVersion.StartsWith("v")) { $RequestedVersion } else { "v$RequestedVersion" }
    $url = "https://api.github.com/repos/$RepoName/releases/tags/$tag"
  }
  return Invoke-RestMethod -Headers $headers -Uri $url
}

function Select-WindowsAsset {
  param($Release)

  $assets = @($Release.assets)
  $asset = $assets | Where-Object { $_.name -match "^ccx_.+_windows_amd64\.zip$" } | Select-Object -First 1
  if (-not $asset) {
    $asset = $assets | Where-Object { $_.name -match "windows.*amd64.*\.zip$" } | Select-Object -First 1
  }
  if (-not $asset) {
    throw "No Windows amd64 zip asset was found on release $($Release.tag_name)."
  }
  return $asset
}

function Install-Ccx {
  $release = Get-Release $Repo $Version
  $asset = Select-WindowsAsset $release
  $installFull = [IO.Path]::GetFullPath($InstallDir)
  $temp = Join-Path ([IO.Path]::GetTempPath()) ("ccx-install-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $temp | Out-Null

  try {
    $zip = Join-Path $temp $asset.name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
    $exe = Get-ChildItem -LiteralPath $temp -Recurse -Filter "xx.exe" | Select-Object -First 1
    if (-not $exe) {
      throw "Downloaded asset did not contain xx.exe."
    }

    New-Item -ItemType Directory -Force -Path $installFull | Out-Null
    Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $installFull "xx.exe") -Force
    foreach ($name in @("presets.json", "LICENSE", "README.md", "README.en.md")) {
      $file = Get-ChildItem -LiteralPath $temp -Recurse -Filter $name | Select-Object -First 1
      if ($file) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $installFull $name) -Force
      }
    }

    $pathChanged = $false
    if (-not $NoPath) {
      $pathChanged = Add-UserPath $installFull
    }

    $installed = Join-Path $installFull "xx.exe"
    $reported = (& $installed --version).Trim()
    Write-Host "ccx $reported installed to $installFull"
    if ($pathChanged) {
      Write-Host "Added install directory to the user PATH. Open a new terminal, then run: xx --version"
    }
    elseif (-not $NoPath) {
      Write-Host "Install directory is already on the user PATH."
    }
  }
  finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Uninstall-Ccx {
  $installFull = [IO.Path]::GetFullPath($InstallDir)
  foreach ($name in @("xx.exe", "presets.json", "LICENSE", "README.md", "README.en.md")) {
    $file = Join-Path $installFull $name
    if (Test-Path -LiteralPath $file) {
      Remove-Item -LiteralPath $file -Force
    }
  }
  Remove-UserPath $installFull | Out-Null
  $remaining = @()
  if (Test-Path -LiteralPath $installFull) {
    $remaining = @(Get-ChildItem -LiteralPath $installFull -Force)
  }
  if ($remaining.Count -eq 0 -and (Test-Path -LiteralPath $installFull)) {
    Remove-Item -LiteralPath $installFull -Force
  }
  Write-Host "ccx native Windows install removed from $installFull"
}

if ($Uninstall) {
  Uninstall-Ccx
}
else {
  Install-Ccx
}
