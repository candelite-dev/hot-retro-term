param(
    [string]$BuildDir = 'build/windows-msvc',
    [string]$OutZip = 'cool-retro-term-win64.zip'
)
$ErrorActionPreference = 'Stop'
$buildRoot = (Resolve-Path -LiteralPath $BuildDir).Path
$stage = Join-Path $buildRoot 'windows-stage'
foreach ($relative in @('.hrt-windows-stage', 'cool-retro-term.exe', 'Qt6Core.dll',
        'platforms/qwindows.dll', 'qmltermwidget/QMLTermWidget/qmltermwidget.dll',
        'qmltermwidget/QMLTermWidget/qmldir', 'qml/QtQuick/Controls/qmldir')) {
    if (!(Test-Path -LiteralPath (Join-Path $stage $relative) -PathType Leaf)) {
        throw "Incomplete deployment: $relative. Build the deploy_windows target first."
    }
}
if ((Get-Item -LiteralPath $stage).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw "Refusing to package a redirected staging directory: $stage"
}
$zipPath = [IO.Path]::GetFullPath($OutZip)
if ($zipPath.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The ZIP must be outside the staging directory.'
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force
Write-Host "Packaged -> $zipPath"
