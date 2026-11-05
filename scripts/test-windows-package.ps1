param([string]$Zip = 'cool-retro-term-win64.zip', [switch]$KeepExtracted)
$ErrorActionPreference = 'Stop'
$zipPath = (Resolve-Path -LiteralPath $Zip).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path $tempRoot ('hrt-windows-zip-' + [guid]::NewGuid().ToString('N'))
$extract = Join-Path $testRoot 'package with spaces'
New-Item -ItemType Directory -Path $extract -Force | Out-Null
function Run-App([string[]]$AppArguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $extract 'cool-retro-term.exe'
    $info.WorkingDirectory = $extract
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($arg in $AppArguments) { $info.ArgumentList.Add($arg) }
    foreach ($key in @($info.Environment.Keys)) {
        if ($key -match '^(QT|QML)[_A-Z0-9]*$|^CMAKE_PREFIX_PATH$') { $info.Environment.Remove($key) | Out-Null }
    }
    $info.Environment['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $info.Environment['APPDATA'] = Join-Path $testRoot 'settings'
    $info.Environment['LOCALAPPDATA'] = Join-Path $testRoot 'local-settings'
    # Exercise the platform plugin actually shipped to desktop users.
    $info.Environment['QT_QPA_PLATFORM'] = 'windows'
    $info.Environment['QT_QUICK_BACKEND'] = 'software'
    $info.Environment['QML_DISABLE_DISK_CACHE'] = '1'
    $info.Environment['QT_FORCE_STDERR_LOGGING'] = '1'
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(30000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Packaged application timed out ($($AppArguments -join ' ')): $($stderrTask.GetAwaiter().GetResult())"
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Packaged application failed ($($process.ExitCode)): $stderr" }
        if ($stderr -match 'is not installed|failed to load|ReferenceError|TypeError|Cannot assign|QProcess: Destroyed') {
            throw "Packaged startup diagnostics: $stderr"
        }
        return $stdout
    } finally { $process.Dispose() }
}
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract
    foreach ($required in @('Qt6Core.dll', 'platforms/qwindows.dll', 'sqldrivers/qsqlite.dll',
            'qml/QtQuick/Controls/qmldir', 'qml/Qt5Compat/GraphicalEffects/qmldir',
            'qmltermwidget/QMLTermWidget/qmltermwidget.dll', 'licenses/gpl-2.0.txt')) {
        if (!(Test-Path -LiteralPath (Join-Path $extract $required))) { throw "ZIP missing $required" }
    }
    $junk = Get-ChildItem -LiteralPath $extract -Recurse -Force |
        Where-Object { $_.Name -match '^(CMakeFiles|CMakeCache.txt|build.ninja|tests)$|\.(obj|lib|pdb)$|^hrt_.*\.exe$' }
    if ($junk) { throw "Build artifacts in ZIP: $($junk.FullName -join ', ')" }
    Write-Host 'ZIP: checking help/version and controlled shell startup'
    if ((Run-App -AppArguments @('--help')) -notmatch 'Usage: cool-retro-term') { throw 'Missing packaged help output' }
    if ((Run-App -AppArguments @('--version')) -notmatch 'cool-retro-term') { throw 'Missing packaged version output' }
    $marker = Join-Path $testRoot 'shell-ready.txt'
    $batch = Join-Path $testRoot 'startup.cmd'
    Set-Content -LiteralPath $batch -Encoding ascii -Value "@echo off`r`necho HRT_ZIP_READY>`"$marker`"`r`nexit /b 0"
    Run-App -AppArguments @('--verbose', '--default-settings', '-e', "$env:SystemRoot\System32\cmd.exe", '/D', '/C', 'call', $batch) | Out-Null
    if (!(Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'HRT_ZIP_READY') {
        throw 'Packaged application did not start its controlled shell'
    }
    Write-Host "Extracted ZIP startup passed without Qt SDK paths: $extract"
} finally {
    if (!$KeepExtracted) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if ([IO.Path]::GetDirectoryName($resolved) -ne $tempRoot.TrimEnd('\', '/') -or
            [IO.Path]::GetFileName($resolved) -notmatch '^hrt-windows-zip-[a-f0-9]{32}$') {
            throw "Unsafe test cleanup path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
