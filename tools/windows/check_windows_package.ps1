[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'This package check requires Windows.' }
$artifactRoot = (Resolve-Path $ArtifactDirectory).Path
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$output = (Resolve-Path $OutputDirectory).Path
$work = Join-Path $env:RUNNER_TEMP ('ripot-package-check-' + [guid]::NewGuid())
$bundle = Join-Path $work 'portable'
$installDirectory = Join-Path $work 'installed'
New-Item $work -ItemType Directory -Force | Out-Null
$report = [ordered]@{ result = 'incomplete'; expectedCommit = $ExpectedCommit; checks = @() }
$appProcess = $null

function Get-PeMachine([string]$Path) {
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw "Missing MZ header: $Path" }
        $reader.BaseStream.Position = 0x3c
        $peOffset = $reader.ReadUInt32()
        $reader.BaseStream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Missing PE signature: $Path" }
        return $reader.ReadUInt16()
    } finally { $reader.Dispose() }
}

function Start-RipotAndCheck([string]$Executable) {
    $process = Start-Process $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited) { throw "Ripot exited during startup: $($process.ExitCode)" }
    } while ($process.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
    if ($process.MainWindowHandle -eq 0) {
        Stop-Process -Id $process.Id -Force
        throw 'Ripot did not create its main window within 45 seconds.'
    }
    Start-Sleep -Seconds 8
    $process.Refresh()
    if ($process.HasExited) { throw "Ripot exited after opening its window: $($process.ExitCode)" }
    if ($process.MainWindowTitle -ne 'Ripot') {
        $unexpectedTitle = $process.MainWindowTitle
        Stop-Process -Id $process.Id -Force
        throw "Unexpected startup window: $unexpectedTitle"
    }
    return $process
}

function Close-Ripot($Process) {
    if ($null -ne $Process -and -not $Process.HasExited) {
        $null = $Process.CloseMainWindow()
        if (-not $Process.WaitForExit(5000)) { Stop-Process -Id $Process.Id -Force }
    }
}

try {
    $manifests = @(Get-ChildItem $artifactRoot -Recurse -Filter 'windows-release.json')
    if ($manifests.Count -ne 1) { throw 'Expected one Windows release manifest.' }
    $releaseDirectory = $manifests[0].DirectoryName
    $manifest = Get-Content ($manifests[0].FullName) -Raw | ConvertFrom-Json
    if ($manifest.sourceCommit -ne $ExpectedCommit -or $manifest.sourceDirty) {
        throw 'Package source differs from the expected committed Windows build.'
    }
    if ($manifest.releaseStage -ne 'internal-test') { throw 'Expected the internal Windows test package.' }
    if ([IO.Path]::GetFileName($manifest.filename) -ne $manifest.filename) { throw 'Invalid installer filename.' }
    $installer = Join-Path $releaseDirectory $manifest.filename
    if ((Get-Item $installer).Length -ne $manifest.sizeBytes) { throw 'Installer size mismatch.' }
    if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne $manifest.sha256) { throw 'Installer hash mismatch.' }
    $report.installer = $manifest
    $report.installerMachine = Get-PeMachine $installer
    foreach ($line in Get-Content (Join-Path $releaseDirectory 'SHA256SUMS.txt')) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw 'Invalid checksum entry.' }
        $expectedHash = $Matches[1]
        $filename = $Matches[2]
        if ([IO.Path]::GetFileName($filename) -ne $filename) { throw 'Invalid checksum filename.' }
        if ((Get-FileHash (Join-Path $releaseDirectory $filename) -Algorithm SHA256).Hash -ne $expectedHash) {
            throw "Checksum mismatch: $filename"
        }
    }
    $report.checks += 'Source commit, installer size and both SHA-256 checksums match.'
    $portable = @(Get-ChildItem $releaseDirectory -Filter 'Ripot-*-windows-x64.zip')
    if ($portable.Count -ne 1) { throw 'Expected one portable ZIP.' }
    Expand-Archive ($portable[0].FullName) -DestinationPath $bundle
    foreach ($relative in @('ripot.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets')) {
        if (-not (Test-Path (Join-Path $bundle $relative))) { throw "Portable package is missing $relative" }
    }
    if ((Get-PeMachine (Join-Path $bundle 'ripot.exe')) -ne 0x8664) { throw 'The app is not Windows x64.' }
    $report.checks += 'Portable package contains a Windows x64 app, Flutter assets and MSVC runtime DLLs.'

    $installLog = Join-Path $output 'installer-log.txt'
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$installDirectory`"", "/LOG=`"$installLog`"")
    $setup = Start-Process $installer -ArgumentList $arguments -PassThru
    if (-not $setup.WaitForExit(60000)) { Stop-Process -Id $setup.Id -Force; throw 'Installer timed out.' }
    if ($setup.ExitCode -ne 0) { throw "Installer exit code: $($setup.ExitCode)" }
    $installedExe = Join-Path $installDirectory 'ripot.exe'
    if (-not (Test-Path $installedExe)) { throw 'Installed executable was not found.' }
    $report.checks += 'Silent per-user installation succeeded.'

    $appProcess = Start-RipotAndCheck $installedExe
    $report.windowTitle = $appProcess.MainWindowTitle
    $report.checks += 'Installed app opened a native window and stayed running.'
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RipotWindowCapture {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr handle, out Rect rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
}
'@
        $rect = [RipotWindowCapture+Rect]::new()
        $null = [RipotWindowCapture]::SetForegroundWindow($appProcess.MainWindowHandle)
        Start-Sleep -Seconds 1
        if (-not [RipotWindowCapture]::GetWindowRect($appProcess.MainWindowHandle, [ref]$rect)) { throw 'Window rectangle unavailable.' }
        $bitmap = [Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
            $bitmap.Save((Join-Path $output 'ripot-windows-startup.png'), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
        $report.screenshot = 'ripot-windows-startup.png'
    } catch { $report.screenshot = 'Unavailable in runner desktop: ' + $_.Exception.Message }
    Close-Ripot $appProcess
    $appProcess = Start-RipotAndCheck $installedExe
    $report.checks += 'Installed app closed and reopened successfully.'
    Close-Ripot $appProcess
    $appProcess = $null

    $uninstaller = Join-Path $installDirectory 'unins000.exe'
    $remove = Start-Process $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru
    if (-not $remove.WaitForExit(60000)) { Stop-Process -Id $remove.Id -Force; throw 'Uninstaller timed out.' }
    if ($remove.ExitCode -ne 0 -or (Test-Path $installedExe)) { throw 'Uninstall did not remove the installed executable.' }
    $report.checks += 'Silent uninstall succeeded.'
    Copy-Item $installer $output
    Copy-Item ($portable[0].FullName) $output
    Copy-Item ($manifests[0].FullName) $output
    Copy-Item (Join-Path $releaseDirectory 'SHA256SUMS.txt') $output
    $report.result = 'passed'
    $report.remaining = 'Live sign-in/Premium, real workflow editing, PDF/printing and backup/restore still require end-to-end Windows validation before public release.'
} catch {
    $report.result = 'failed'
    $report.error = $_.Exception.Message
    throw
} finally {
    Close-Ripot $appProcess
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'windows-package-check.json') -Encoding utf8
    $report | ConvertTo-Json -Depth 8 | Write-Host
}
