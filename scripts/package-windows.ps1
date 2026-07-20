param(
    [string]$BuildDir = "build",
    [string]$OutZip   = "cool-retro-term-win64.zip"
)

$ErrorActionPreference = "Stop"

$stage = Join-Path $BuildDir "stage"
$denylist = @(
    "CMakeFiles",
    ".qt",
    "app",
    "KDSingleApplication",
    ".cmake",
    "cmake_install.cmake",
    "build.ninja",
    ".ninja_log",
    ".ninja_deps",
    "CMakeCache.txt",
    "stage"
)

if (!(Test-Path -LiteralPath $BuildDir -PathType Container)) {
    throw "Build directory not found: $BuildDir"
}

$executable = Join-Path $BuildDir "cool-retro-term.exe"
if (!(Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Executable not found: $executable"
}

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Get-ChildItem -LiteralPath $BuildDir -Force | ForEach-Object {
    if ($denylist -notcontains $_.Name) {
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stage $_.Name) -Recurse
        } elseif ($_.Name -ieq "cool-retro-term.exe" -or $_.Extension -ieq ".dll") {
            Copy-Item -LiteralPath $_.FullName -Destination $stage
        }
    }
}

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $OutZip -Force
Write-Host "Packaged -> $OutZip"
