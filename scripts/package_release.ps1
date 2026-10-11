# Package the runnable bundle in output\ into a zip for GitHub Release.
# Usage (PowerShell):
#   .\scripts\package_release.ps1 -Version 0.0.1
param(
    [string]$Version = "0.0.1"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path -Path $root -ChildPath "output"
$distDir = Join-Path -Path $root -ChildPath "dist"

if (-not (Test-Path -LiteralPath $outDir)) {
    throw "output\ not found. Run build_windows.bat first."
}

New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$zipName = "JingerPicManager-v" + $Version + "-windows-x64.zip"
$zipPath = Join-Path -Path $distDir -ChildPath $zipName

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path -Path $outDir -ChildPath "*") -DestinationPath $zipPath -CompressionLevel Optimal

$sizeMb = [math]::Round(((Get-Item -LiteralPath $zipPath).Length / 1MB), 1)
Write-Host ("Created: " + $zipPath + " (" + $sizeMb + " MB)")
