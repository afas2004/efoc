param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"

# --- sanity ---
$required = @("pubspec.yaml", "web\update.json", "lib\version.dart")
foreach ($f in $required) {
    if (-not (Test-Path $f)) {
        Write-Host "Error: $f not found. Run this from the project root." -ForegroundColor Red
        exit 1
    }
}

# --- read current version from pubspec.yaml ---
$lines = Get-Content "pubspec.yaml"
$versionLine = $lines | Where-Object { $_ -match '^version:' } | Select-Object -First 1

if ($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)') {
    Write-Host "Error: could not parse version from pubspec.yaml." -ForegroundColor Red
    Write-Host "Expected: version: X.Y.Z+N" -ForegroundColor Red
    Write-Host "Got:      $versionLine" -ForegroundColor Red
    exit 1
}

$currentVersion = $Matches[1]
$currentBuild = [int]$Matches[2]
$newBuild = $currentBuild + 1

Write-Host "Current: $currentVersion+$currentBuild"
Write-Host "New:     $Version+$newBuild"
Write-Host ""

# UTF-8 without BOM, so assetlinks/json parsers don't choke
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- 1. pubspec.yaml ---
$newLines = $lines | ForEach-Object {
    if ($_ -match '^version:') {
        "version: $Version+$newBuild"
    } else {
        $_
    }
}
[System.IO.File]::WriteAllLines(
    (Resolve-Path "pubspec.yaml").Path,
    $newLines,
    $utf8
)

# --- 2. web/update.json ---
$manifest = [ordered]@{
    latest_version = $Version
    latest_build   = $newBuild
    release_notes  = $Notes
}
$json = $manifest | ConvertTo-Json
[System.IO.File]::WriteAllText(
    (Resolve-Path "web\update.json").Path,
    $json,
    $utf8
)

# --- 3. lib/version.dart ---
$dartLines = Get-Content "lib\version.dart"
$newDartLines = $dartLines | ForEach-Object {
    if ($_ -match '^const int kAppBuild = ') {
        "const int kAppBuild = $newBuild;"
    } elseif ($_ -match '^const String kAppVersion = ') {
        "const String kAppVersion = '$Version';"
    } else {
        $_
    }
}
[System.IO.File]::WriteAllLines(
    (Resolve-Path "lib\version.dart").Path,
    $newDartLines,
    $utf8
)

Write-Host "Bumped:" -ForegroundColor Green
Write-Host "  pubspec.yaml     -> version: $Version+$newBuild"
Write-Host "  web/update.json  -> $Version (build $newBuild)"
Write-Host "  lib/version.dart -> $Version (build $newBuild)"
Write-Host ""
Write-Host "Next: run build_web.bat to build and deploy."