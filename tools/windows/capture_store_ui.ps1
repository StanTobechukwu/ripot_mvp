[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ExpectedCommit = '1dc88973b206c03c9888de0a08ee629204228787',
    [string]$UpgradeDirectory = '',
    [string]$ExpectedUpgradeCommit = '',
    [string]$AppxPackageFamilyName = ''
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
if ($AppxPackageFamilyName) {
    if ($UpgradeDirectory) { throw 'The EXE upgrade check cannot be used for MSIX.' }
    . (Join-Path $PSScriptRoot 'store_package_tools.ps1')
}
function Start-WorkflowApp {
    if ($AppxPackageFamilyName) { return Start-RipotStoreApp $AppxPackageFamilyName }
    return Start-Process (Join-Path $install 'ripot.exe') -WorkingDirectory $install -PassThru
}
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms, Accessibility
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

Add-Type -ReferencedAssemblies ([Accessibility.IAccessible].Assembly.Location) @'
using System;
using System.Runtime.InteropServices;
using Accessibility;
public sealed class RipotAccessibleNode {
    private readonly IAccessible accessible;
    private readonly int child;
    public string Name { get; private set; }
    public string Value { get; private set; }
    public object Role { get; private set; }
    public string DefaultAction { get; private set; }
    public bool Enabled { get; private set; }
    public bool Offscreen { get; private set; }
    public int Left, Top, Width, Height;
    public RipotAccessibleNode(IAccessible acc, int id) {
        accessible = acc; child = id;
        Name = acc.get_accName(id); Role = acc.get_accRole(id);
        Value = acc.get_accValue(id);
        DefaultAction = acc.get_accDefaultAction(id);
        int state = Convert.ToInt32(acc.get_accState(id));
        Enabled = (state & 1) == 0; Offscreen = (state & 0x18000) != 0;
        acc.accLocation(out Left, out Top, out Width, out Height, id);
    }
    public void Invoke() { accessible.accDoDefaultAction(child); }
    public void SetValue(string value) { accessible.set_accValue(child, value); }
}
public static class RipotMsaa {
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint command);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IAccessible result);
    [DllImport("oleacc.dll")] public static extern int AccessibleChildren(IAccessible parent, int start, int count, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex=2)] object[] children, out int obtained);
    public static RipotAccessibleNode Read(object raw, int id) {
        return new RipotAccessibleNode((IAccessible)raw, id);
    }
    public static object[] Children(object raw) {
        IAccessible acc = (IAccessible)raw;
        int count = acc.accChildCount;
        if (count < 0 || count > 1000) throw new InvalidOperationException("Invalid child count.");
        object[] children = new object[count];
        int obtained;
        AccessibleChildren(acc, 0, count, children, out obtained);
        if (obtained < count) Array.Resize(ref children, obtained);
        return children;
    }
    public static IAccessible Root(IntPtr window) {
        var child = GetWindow(window, 5);
        if (child == IntPtr.Zero) throw new InvalidOperationException("Flutter child window missing.");
        var iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
        IAccessible root;
        AccessibleObjectFromWindow(child, 0xFFFFFFFC, ref iid, out root);
        return root;
    }
}
'@

function Read-Accessible($Container, [int]$ChildId, [int]$Depth = 0) {
    if ($Depth -gt 30) { return }
    try {
        [RipotMsaa]::Read($Container, $ChildId)
        if ($ChildId -ne 0) { return }
        foreach ($child in [RipotMsaa]::Children($Container)) {
            if ($child -is [int]) {
                Read-Accessible $Container ([int]$child) ($Depth + 1)
            } elseif ($null -ne $child) {
                Read-Accessible $child 0 ($Depth + 1)
            }
        }
    } catch { Write-Warning ('Accessibility node: ' + $_.Exception.Message) }
}

function Get-AppElements {
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $root = [RipotMsaa]::Root($app.MainWindowHandle)
        if ($null -ne $root) {
            $nodes = @(Read-Accessible $root 0)
            if ($nodes.Count -gt 1) { return $nodes }
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Flutter accessibility tree is not ready.'
}

function Save-State([string]$Name) {
    Start-Sleep -Seconds 6
    [RipotDesktop]::SetCursorPos(1900, 1060) | Out-Null
    $rows = @()
    foreach ($el in (Get-AppElements)) {
        $rows += [ordered]@{
            name = $el.Name; value = $el.Value; role = $el.Role
            enabled = $el.Enabled; offscreen = $el.Offscreen
            rect = @($el.Left, $el.Top, $el.Width, $el.Height)
            action = $el.DefaultAction
        }
    }
    $rows | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $output "$Name-ui.json") -Encoding utf8
    $rect = [RipotCaptureDisplay+Rect]::new()
    if (-not [RipotCaptureDisplay]::GetClientRect($app.MainWindowHandle, [ref]$rect)) { throw 'Cannot read app client area.' }
    $point = [RipotCaptureDisplay+Point]::new()
    if (-not [RipotCaptureDisplay]::ClientToScreen($app.MainWindowHandle, [ref]$point)) { throw 'Cannot locate app client area.' }
    $rect.Left = $point.X; $rect.Top = $point.Y
    $rect.Right += $point.X; $rect.Bottom += $point.Y
    if ($rect.Right - $rect.Left -lt 1366 -or $rect.Bottom - $rect.Top -lt 768 -or
        $rect.Left -lt 0 -or $rect.Top -lt 0 -or
        $rect.Right -gt [RipotCaptureDisplay]::GetSystemMetrics(0) -or
        $rect.Bottom -gt [RipotCaptureDisplay]::GetSystemMetrics(1)) { throw 'Screenshot is too small or outside the desktop.' }
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
    $matches = @((Get-AppElements) | Where-Object { ($_.Name -eq $Name -or ($_.Name -split '\r?\n')[0] -eq $Name) -and $_.Enabled -and -not $_.Offscreen })
    if ($matches.Count -ne 1) { throw "Expected one visible '$Name' control, found $($matches.Count)." }
    $el = $matches[0]
    if ($el.DefaultAction) {
        $el.Invoke()
    } else {
        $r = $el
        if ($r.Width -le 0 -or $r.Height -le 0) { throw "'$Name' has no clickable bounds." }
        $null = [RipotDesktop]::SetCursorPos([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2))
        [RipotDesktop]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        [RipotDesktop]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    }
    Start-Sleep -Seconds 2
}

function Fill-Field([string]$Name, [string]$Value) {
    $matches = @((Get-AppElements) | Where-Object { $_.Name -eq $Name -and $_.Role -eq 42 -and $_.Enabled })
    if ($matches.Count -ne 1) { throw "Expected one '$Name' input, found $($matches.Count)." }
    if ($Value -notmatch '^[A-Za-z0-9 -]+$') { throw 'Only fixed fictional ASCII fixture values are allowed.' }
    Click-Label $Name
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    [System.Windows.Forms.SendKeys]::SendWait($Value)
    Start-Sleep -Milliseconds 500
    $field = @((Get-AppElements) | Where-Object { $_.Name -eq $Name -and $_.Role -eq 42 })
    if ($field.Count -ne 1 -or $field[0].Value -ne $Value) { throw "'$Name' did not retain the fictional test value." }
}

function Click-WindowPoint([int]$X, [int]$Y) {
    $rect = [RipotDesktop+Rect]::new()
    if (-not [RipotDesktop]::GetWindowRect($app.MainWindowHandle, [ref]$rect)) { throw 'App window unavailable.' }
    $null = [RipotDesktop]::SetCursorPos($rect.Left + $X, $rect.Top + $Y)
    [RipotDesktop]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    [RipotDesktop]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Seconds 2
}

# Display-mode API affects only this disposable runner, never the app binary.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class RipotCaptureDisplay {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DevMode {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
        public ushort SpecVersion, DriverVersion, Size, DriverExtra;
        public uint Fields;
        public int PositionX, PositionY;
        public uint Orientation, FixedOutput;
        public short Color, Duplex, YResolution, TTOption, Collate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string FormName;
        public ushort LogPixels;
        public uint BitsPerPel, PelsWidth, PelsHeight, DisplayFlags, DisplayFrequency;
        public uint ICMMethod, ICMIntent, MediaType, DitherType, Reserved1, Reserved2, PanningWidth, PanningHeight;
    }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out Rect rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref Point point);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string device, int mode, ref DevMode value);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettings(ref DevMode value, uint flags);
    public static int SetResolution() {
        DevMode mode = new DevMode();
        mode.Size = (ushort)Marshal.SizeOf(typeof(DevMode));
        // Pass a real native NULL device name; PowerShell coerces a string null to empty.
        if (!EnumDisplaySettings(null, -1, ref mode)) return -100;
        mode.PelsWidth = 1920; mode.PelsHeight = 1080; mode.Fields = 0x180000;
        return ChangeDisplaySettings(ref mode, 0);
    }
}
'@

function Set-CaptureWindow {
    $app.Refresh()
    if ($app.MainWindowHandle -eq 0) { throw 'App window not ready.' }
    # 1600x900 client area at the runner's 100% scale; validated before every capture.
    [RipotDesktop]::MoveWindow($app.MainWindowHandle, 40, 40, 1616, 939, $true) | Out-Null
    [RipotDesktop]::SetForegroundWindow($app.MainWindowHandle) | Out-Null
    Start-Sleep -Seconds 3
}

function Populate-FictionalSections($Nodes) {
    $numbers = @{
        'End Diastolic Volume'='120'; 'LV internal diameter in diastole (LVIDd)'='4.8'
        'Septal Wall (IVSd)'='0.9'; 'Posterior Wall (PWDd)'='0.9'; 'Ejection Fraction (EF)'='62'
        'E/A'='1.2'; 'LA Diameter'='3.4'; 'LA Area'='16'; 'Aortic Root Diameter'='3.0'
        'AV Vmax'='1.2'; 'Peak Gradient'='5.8'; 'Cavity Dimension'='3.2'; 'RV Basal Diameter'='3.2'
        'TAPSE'='2.2'; 'TR Vmax'='2.2'; 'Area'='14'; 'IVC Dimension'='1.6'; 'Estimated PAP'='24'
    }
    foreach ($node in $Nodes) {
        if ($node.type -ne 'section') { continue }
        $value = $null
        if ($numbers.ContainsKey([string]$node.title)) { $value = $numbers[[string]$node.title] }
        elseif ($node.inputType -eq 'singleSelect' -and $node.options.Count -gt 0) { $value = [string]$node.options[0] }
        elseif ($node.title -eq 'Conclusion') { $value = 'Fictional sample for demonstrating report layout. This is not a patient record.' }
        if ($null -ne $value) {
            $node.children = @([pscustomobject]@{type='content'; id=([guid]::NewGuid().ToString()); text=$value; indent=0})
        } else { Populate-FictionalSections $node.children }
    }
}

function Complete-FictionalDraft {
    # Seed only the report created above on an otherwise empty disposable runner.
    # No entitlement, user account, template, or application-code changes are made.
    $locations = @($env:APPDATA, (Join-Path $env:LOCALAPPDATA "Packages/$AppxPackageFamilyName/LocalCache"))
    $candidates = @(foreach ($location in $locations) {
        if (Test-Path $location) { Get-ChildItem $location -Filter shared_preferences.json -Recurse -File -ErrorAction SilentlyContinue }
    }) | Sort-Object FullName -Unique
    $matches = @()
    foreach ($file in $candidates) {
        $prefs = Get-Content $file.FullName -Raw | ConvertFrom-Json
        foreach ($property in $prefs.PSObject.Properties) {
            if ($property.Name -notmatch '(^|\.)reports\.doc\.') { continue }
            $doc = $property.Value | ConvertFrom-Json
            if ($doc.reportTitle -eq 'Echocardiography - fictional sample') {
                $matches += [pscustomobject]@{File=$file; Prefs=$prefs; Property=$property; Doc=$doc}
            }
        }
    }
    if ($matches.Count -ne 1) { throw "Expected one fictional draft preference, found $($matches.Count)." }
    $fixture = $matches[0]
    Populate-FictionalSections $fixture.Doc.roots
    $fixture.Property.Value = $fixture.Doc | ConvertTo-Json -Depth 80 -Compress
    $json = $fixture.Prefs | ConvertTo-Json -Depth 80 -Compress
    [IO.File]::WriteAllText($fixture.File.FullName, $json, [Text.UTF8Encoding]::new($false))
    $report.checks += 'Populated only the local fictional draft using its normal document schema; no Premium bypass.'
}

try {
    if (-not $AppxPackageFamilyName) { throw 'Screenshots require the installed Store package.' }
    $manifest = Get-Content (Join-Path $package 'windows-store-release.json') -Raw | ConvertFrom-Json
    if ($manifest.sourceCommit -ne $ExpectedCommit -or $manifest.sourceDirty) { throw 'Unexpected package source.' }
    if ((Get-FileHash (Join-Path $package $manifest.filename) -Algorithm SHA256).Hash -ne $manifest.sha256) { throw 'Package checksum mismatch.' }
    $report.sourceCommit = $manifest.sourceCommit
    $report.installerSha256 = $manifest.sha256
    $report.packageType = 'MSIX'
    [RipotCaptureDisplay]::SetProcessDPIAware() | Out-Null
    Write-Host "Initial desktop: $([RipotCaptureDisplay]::GetSystemMetrics(0)) x $([RipotCaptureDisplay]::GetSystemMetrics(1))"
    $result = [RipotCaptureDisplay]::SetResolution()
    if ($result -ne 0 -and (Get-Command Set-DisplayResolution -ErrorAction SilentlyContinue)) {
        Set-DisplayResolution -Width 1920 -Height 1080 -Force
    }
    Write-Host "Display mode result: $result"
    Start-Sleep -Seconds 3
    $report.display = @([RipotCaptureDisplay]::GetSystemMetrics(0), [RipotCaptureDisplay]::GetSystemMetrics(1))
    if ($report.display[0] -lt 1700 -or $report.display[1] -lt 1020) { throw 'Runner display cannot fit a Store-sized screenshot.' }
    $app = Start-WorkflowApp
    Start-Sleep -Seconds 10
    Set-CaptureWindow
    $report.checks += Get-RipotStoreDpiState $app
    if (@((Get-AppElements) | Where-Object { $_.Name -eq 'Continue without an account' }).Count -gt 0) { Click-Label 'Continue without an account' }
    Click-Label 'New Report'
    Click-Label 'Use a template'
    Save-State '01-report-templates'
    Click-Label "2D Echocardiography`nUpdated 5 Sep 2026"
    Fill-Field 'Report Title / Topic' 'Echocardiography - fictional sample'
    Fill-Field 'Subject Name *' 'FICTIONAL DEMO PATIENT'
    Fill-Field 'Subject ID' 'DEMO-001'
    Click-Label 'Save progress'
    Stop-Process -Id $app.Id -Force
    Start-Sleep -Seconds 2
    Complete-FictionalDraft
    $app = Start-WorkflowApp
    Start-Sleep -Seconds 8
    Set-CaptureWindow
    Save-State '04-saved-reports'
    Click-Label 'Echocardiography - fictional sample'
    Save-State '02-report-form'
    Click-Label 'Preview'
    Save-State '03-report-preview'
    $report.checks += 'Actual installed Windows UI captured at native resolution; no image resizing or marketing overlays.'
    $report.result = 'passed'
} catch {
    $report.result = 'failed'; $report.error = $_.Exception.Message
    if ($null -ne $app -and -not $app.HasExited) { try { Save-State 'failure-state' } catch { Write-Warning $_ } }
    throw
} finally {
    if ($null -ne $app -and -not $app.HasExited) { Stop-Process -Id $app.Id -Force }
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'workflow-result.json') -Encoding utf8
    $report | ConvertTo-Json -Depth 8 | Write-Host
}
