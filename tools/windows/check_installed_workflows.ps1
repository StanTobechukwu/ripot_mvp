[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT' -or $env:GITHUB_ACTIONS -ne 'true') {
    throw 'Run this fictional-data check only on a disposable GitHub Windows runner.'
}
$package = (Resolve-Path $ArtifactDirectory).Path
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$output = (Resolve-Path $OutputDirectory).Path
$install = Join-Path $env:RUNNER_TEMP ('ripot-ui-' + [guid]::NewGuid())
$report = [ordered]@{ result = 'incomplete'; checks = @(); screenshots = @() }
$app = $null
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RipotDesktop {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int height, bool repaint);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint action, uint param, IntPtr value, uint flags);
}
'@

function Get-AppElements {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    return $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
}

function Save-State([string]$Name) {
    Start-Sleep -Seconds 2
    $rows = @()
    foreach ($el in (Get-AppElements)) {
        $c = $el.Current
        $r = $c.BoundingRectangle
        $rows += [ordered]@{
            name = $c.Name; type = $c.ControlType.ProgrammaticName
            id = $c.AutomationId; enabled = $c.IsEnabled; offscreen = $c.IsOffscreen
            rect = @($r.Left, $r.Top, $r.Width, $r.Height)
            patterns = @($el.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
        }
    }
    $rows | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output "$Name-ui.json") -Encoding utf8
    $rect = [RipotDesktop+Rect]::new()
    if (-not [RipotDesktop]::GetWindowRect($app.MainWindowHandle, [ref]$rect)) { throw 'Cannot capture app window.' }
    $bitmap = [Drawing.Bitmap]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save((Join-Path $output "$Name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $report.screenshots += "$Name.png"
    Write-Host "Captured $Name with $($rows.Count) accessibility elements."
}

function Click-Label([string]$Name) {
    $matches = @((Get-AppElements) | Where-Object { $_.Current.Name -eq $Name -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen })
    if ($matches.Count -ne 1) { throw "Expected one visible '$Name' control, found $($matches.Count)." }
    $el = $matches[0]
    $pattern = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
    } else {
        $r = $el.Current.BoundingRectangle
        if ($r.Width -le 0 -or $r.Height -le 0) { throw "'$Name' has no clickable bounds." }
        $null = [RipotDesktop]::SetCursorPos([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2))
        [RipotDesktop]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        [RipotDesktop]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    }
    Start-Sleep -Seconds 2
}

try {
    $manifest = Get-Content (Join-Path $package 'windows-release.json') -Raw | ConvertFrom-Json
    if ($manifest.sourceCommit -ne 'ed7bf8b46f7e3599c0bf872fc4696532b15e7e02' -or $manifest.sourceDirty) { throw 'Unexpected installer source.' }
    $installer = Join-Path $package $manifest.filename
    if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne $manifest.sha256) { throw 'Installer checksum mismatch.' }
    $report.sourceCommit = $manifest.sourceCommit
    $report.installerSha256 = $manifest.sha256
    $setup = Start-Process $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$install`"") -PassThru
    if (-not $setup.WaitForExit(60000)) { Stop-Process -Id $setup.Id -Force; throw 'Installer timed out.' }
    if ($setup.ExitCode -ne 0) { throw 'Installer failed.' }
    # Enables Flutter's normal Windows accessibility support on this disposable desktop.
    $null = [RipotDesktop]::SystemParametersInfo(0x0047, 1, [IntPtr]::Zero, 2)
    $app = Start-Process (Join-Path $install 'ripot.exe') -WorkingDirectory $install -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 500
        $app.Refresh()
        if ($app.HasExited) { throw 'Ripot exited at startup.' }
    } while ($app.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
    if ($app.MainWindowHandle -eq 0) { throw 'Ripot window unavailable.' }
    $null = [RipotDesktop]::MoveWindow($app.MainWindowHandle, 20, 20, 960, 700, $true)
    $null = [RipotDesktop]::SetForegroundWindow($app.MainWindowHandle)
    Start-Sleep -Seconds 8
    Save-State '01-home'
    Click-Label 'New Report'
    Save-State '02-new-report'
    Click-Label 'Use a template'
    Save-State '03-templates'
    $report.checks += 'Installed release opened the new-report menu and template selector through native accessibility controls.'
    $report.result = 'passed'
} catch {
    $report.result = 'failed'
    $report.error = $_.Exception.Message
    throw
} finally {
    if ($null -ne $app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force }
    $null = [RipotDesktop]::SystemParametersInfo(0x0047, 0, [IntPtr]::Zero, 2)
    $uninstaller = Join-Path $install 'unins000.exe'
    if (Test-Path $uninstaller) {
        $remove = Start-Process $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru
        if (-not $remove.WaitForExit(60000)) { Stop-Process -Id $remove.Id -Force }
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $output 'workflow-result.json') -Encoding utf8
    $report | ConvertTo-Json -Depth 6 | Write-Host
}
