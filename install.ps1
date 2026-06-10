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

# 直读 HKCU\Environment 的 Path 原始值（不展开 %VAR%），避免回写时把别人的 REG_EXPAND_SZ 条目冻结成字面量。
function Get-RawUserPath {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $false)
  if (-not $key) { return "" }
  try {
    return [string]$key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  }
  finally {
    $key.Close()
  }
}

# 以 REG_EXPAND_SZ 回写 Path，保留 %VAR% 形式，并广播一次环境变更。
function Set-RawUserPath {
  param([string]$Value)
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
  try {
    $key.SetValue("Path", $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
  }
  finally {
    $key.Close()
  }
  Publish-EnvironmentChange
}

function Add-UserPath {
  param([string]$Dir)

  $full = Normalize-PathForCompare $Dir
  $current = Get-RawUserPath
  $parts = Split-PathList $current
  foreach ($part in $parts) {
    if ((Normalize-PathForCompare $part).Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
      return $false
    }
  }
  # 保留原始条目（含 %VAR%），仅追加安装目录（已是字面量全路径）。
  $next = if ($current) { "$current;$full" } else { $full }
  Set-RawUserPath $next
  if ($env:Path -notlike "*$full*") {
    $env:Path = "$env:Path;$full"
  }
  return $true
}

function Remove-UserPath {
  param([string]$Dir)

  $full = Normalize-PathForCompare $Dir
  $current = Get-RawUserPath
  $parts = Split-PathList $current
  $kept = @()
  $removed = $false
  foreach ($part in $parts) {
    if ((Normalize-PathForCompare $part).Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
      $removed = $true
    }
    else {
      $kept += $part  # 保留原始字符串，不动其 %VAR% 形式
    }
  }
  if ($removed) {
    Set-RawUserPath ($kept -join ";")
  }
  return $removed
}

function Resolve-FinalUri {
  param($Response)

  # 取重定向后的最终 URL。Windows PowerShell 5.1 的 BaseResponse 是 HttpWebResponse（有 ResponseUri）；
  # PowerShell 7 是 HttpResponseMessage（无 ResponseUri，有 RequestMessage.RequestUri）。
  # StrictMode 下访问不存在的属性会抛错，故逐个 try 包裹。
  try {
    if ($Response.BaseResponse.ResponseUri) { return [string]$Response.BaseResponse.ResponseUri.AbsoluteUri }
  }
  catch {}
  try {
    if ($Response.BaseResponse.RequestMessage.RequestUri) { return [string]$Response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
  }
  catch {}
  return ""
}

function Resolve-LatestTag {
  param([string]$RepoName)

  $url = "https://github.com/$RepoName/releases/latest"
  $response = Invoke-WebRequest -UseBasicParsing -Uri $url -MaximumRedirection 5
  $location = Resolve-FinalUri $response

  if (-not $location -or $location -notmatch "/releases/tag/([^/?#]+)") {
    throw "Could not resolve the latest release tag from $url."
  }
  return $Matches[1]
}

function Resolve-ReleaseAsset {
  param([string]$RepoName, [string]$RequestedVersion)

  if ($RequestedVersion -eq "latest") {
    $tag = Resolve-LatestTag $RepoName
  }
  else {
    $tag = if ($RequestedVersion.StartsWith("v")) { $RequestedVersion } else { "v$RequestedVersion" }
  }

  if ($tag -notmatch "^v?(.+)$") {
    throw "Invalid release tag: $tag"
  }
  $versionValue = $Matches[1]
  $assetName = "ccx_${versionValue}_windows_amd64.zip"
  return [pscustomobject]@{
    Tag = $tag
    Name = $assetName
    Url = "https://github.com/$RepoName/releases/download/$tag/$assetName"
  }
}

function Install-Ccx {
  $asset = Resolve-ReleaseAsset $Repo $Version
  $installFull = [IO.Path]::GetFullPath($InstallDir)
  $temp = Join-Path ([IO.Path]::GetTempPath()) ("ccx-install-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $temp | Out-Null

  try {
    $zip = Join-Path $temp $asset.Name
    Invoke-WebRequest -UseBasicParsing -Uri $asset.Url -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
    $exe = Get-ChildItem -LiteralPath $temp -Recurse -Filter "xx.exe" | Select-Object -First 1
    if (-not $exe) {
      throw "Downloaded asset did not contain xx.exe."
    }

    New-Item -ItemType Directory -Force -Path $installFull | Out-Null
    $dest   = Join-Path $installFull "xx.exe"
    $staged = Join-Path $installFull "xx.exe.new"
    $backup = Join-Path $installFull ("xx.exe." + [guid]::NewGuid().Guid + ".old")

    # 1. Stage the new binary (write is always safe; the running binary is at a different path)
    Copy-Item -LiteralPath $exe.FullName -Destination $staged -Force

    # 2. Clean up any unlocked backups left by previous upgrades (skip locked ones silently)
    Get-ChildItem -LiteralPath $installFull -Filter "xx.exe.*.old" -ErrorAction SilentlyContinue |
      ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

    # 3. Promote staged → dest.  Fast path: direct overwrite (works when xx is not running).
    #    Locked path: rename the running binary to a unique .old (Windows allows renaming open
    #    files), then rename staged into place.  On any failure, roll back and clean up.
    try {
      Move-Item -LiteralPath $staged -Destination $dest -Force
    } catch {
      try {
        if (Test-Path $dest) { Move-Item -LiteralPath $dest -Destination $backup }
        Move-Item -LiteralPath $staged -Destination $dest
      } catch {
        # Roll back: restore the old binary if the slot is now empty
        if ((Test-Path $backup) -and -not (Test-Path $dest)) {
          Move-Item -LiteralPath $backup -Destination $dest -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
        throw
      }
    }
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
  foreach ($name in @("xx.exe", "xx.exe.new", "presets.json", "LICENSE", "README.md", "README.en.md")) {
    $file = Join-Path $installFull $name
    if (Test-Path -LiteralPath $file) {
      Remove-Item -LiteralPath $file -Force
    }
  }
  # Remove any upgrade backup files (xx.exe.<guid>.old); skip locked ones
  $lockedOld = @()
  Get-ChildItem -LiteralPath $installFull -Filter "xx.exe.*.old" -ErrorAction SilentlyContinue |
    ForEach-Object {
      $oldPath = $_.FullName
      try   { Remove-Item -LiteralPath $oldPath -Force -ErrorAction Stop }
      catch { $lockedOld += $oldPath }
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
  if ($lockedOld.Count -gt 0) {
    Write-Warning "$($lockedOld.Count) backup file(s) are still in use by running xx sessions and could not be removed. They will be cleaned up automatically on the next upgrade, or you can delete them manually after all xx processes exit: $installFull"
  }
}

if ($Uninstall) {
  Uninstall-Ccx
}
else {
  Install-Ccx
}
