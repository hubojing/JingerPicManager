# One-shot GitHub publisher for JingerPicManager.
#
# What it does:
#   1. Creates the GitHub repo (if it does not exist yet)
#   2. Pushes the current branch and the version tag
#   3. Packages output\ into dist\<name>-v<version>-windows-x64.zip
#   4. Creates the GitHub Release and uploads that zip
#
# Prereqs:
#   - A GitHub Personal Access Token with "repo" scope
#     https://github.com/settings/tokens  ->  Generate new token (classic)
#   - Run build_windows.bat first so output\ is up to date
#
# Usage:
#   .\scripts\publish_release.ps1 -Token ghp_xxxxxxxxxxxxxxxxxxxx
#   .\scripts\publish_release.ps1 -Token $env:GITHUB_TOKEN -Version 0.0.1
#
param(
    [Parameter(Mandatory = $true)]
    [string]$Token,
    [string]$Version = "0.0.1",
    [string]$Owner = "hubojing",
    [string]$Repo = "JingerPicManager",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$headers = @{
    Authorization = "Bearer $Token"
    Accept        = "application/vnd.github+json"
}
$apiBase = "https://api.github.com/repos/$Owner/$Repo"

Write-Host "[1/6] Checking GitHub credentials..."
$user = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/user"
Write-Host ("      Authenticated as: " + $user.login)

Write-Host "[2/6] Ensuring repo $Owner/$Repo exists..."
$repoInfo = $null
try {
    $repoInfo = Invoke-RestMethod -Headers $headers -Uri $apiBase
    Write-Host "      Repo already exists."
} catch {
    $body = @{ name = $Repo; private = $false; description = "Local-first Windows desktop photo album manager." } | ConvertTo-Json
    $repoInfo = Invoke-RestMethod -Headers $headers -Method Post -Uri "https://api.github.com/user/repos" -Body $body -ContentType "application/json"
    Write-Host ("      Created repo: " + $repoInfo.html_url)
}

Write-Host "[3/6] Pushing code and tag..."
$remote = "https://$Owner`:$Token@github.com/$Owner/$Repo.git"
git branch -M $Branch
git remote remove origin 2>$null | Out-Null
git remote add origin $remote
git push -u origin $Branch
$tag = "v$Version"
if (-not (git tag -l $tag)) {
    git tag -a $tag -m "$Repo $tag"
}
git push origin $tag
Write-Host "      Pushed $Branch and tag $tag."

Write-Host "[4/6] Packaging release zip..."
& (Join-Path $PSScriptRoot "package_release.ps1") -Version $Version | Out-Null
$zipPath = Join-Path -Path $root -ChildPath ("dist/JingerPicManager-v" + $Version + "-windows-x64.zip")
if (-not (Test-Path -LiteralPath $zipPath)) { throw "Zip not found: $zipPath" }
Write-Host ("      Zip: " + $zipPath)

Write-Host "[5/6] Creating release $tag..."
$notes = @"
JingerPicManager $tag - first public release.

Local-first Windows desktop photo album manager: photo library, albums,
date grouping and fully offline face recognition. Everything runs on your
own machine - no account, no upload.

Highlights
- Photo library with thumbnail grid and date grouping
- Albums as tags (a photo can live in many albums; removing it never
  touches the original file)
- Offline face detection and clustering (YuNet + SFace, all local)
- Configurable thumbnail cache location
- GPL-3.0 licensed

Requirements
- Windows 10/11 (64-bit)

Download JingerPicManager-v$Version-windows-x64.zip below, unzip it, and run
JingerPicManager.exe. The build is not code-signed yet, so Windows may show
an "unknown publisher" prompt - choose "Run anyway".
"@
$releaseBody = @{
    tag_name         = $tag
    name             = "$tag"
    body             = $notes
    draft            = $false
    prerelease       = $false
    make_latest      = "true"
} | ConvertTo-Json -Depth 5

$release = $null
try {
    $release = Invoke-RestMethod -Headers $headers -Method Post -Uri "$apiBase/releases" -Body $releaseBody -ContentType "application/json"
} catch {
    # Already released for this tag: reuse it and append the asset.
    $release = Invoke-RestMethod -Headers $headers -Uri "$apiBase/releases/tags/$tag"
    Write-Host "      Release for $tag already exists, reusing it."
}
Write-Host ("      Release: " + $release.html_url)

Write-Host "[6/6] Uploading asset..."
$assetName = [System.IO.Path]::GetFileName($zipPath)
$uploadUri = "https://uploads.github.com/repos/$Owner/$Repo/releases/" + $release.id + "/assets?name=" + [System.Uri]::EscapeDataString($assetName)
$uploadHeaders = @{
    Authorization = "Bearer $Token"
    Accept        = "application/vnd.github+json"
}
Invoke-RestMethod -Headers $uploadHeaders -Method Post -Uri $uploadUri -InFile $zipPath -ContentType "application/zip" | Out-Null

Write-Host ""
Write-Host ("DONE: " + $release.html_url)
