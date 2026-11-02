# Shared Windows SDK discovery and packaged-app activation for Store build checks.
function Get-RipotSdkTool([string]$Name) {
    $bin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $versions = @(Get-ChildItem $bin -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending)
    foreach ($version in $versions) {
        $tool = Join-Path $version.FullName "x64/$Name"
        if (Test-Path $tool) { return $tool }
    }
    throw "Install the Windows SDK; $Name was not found."
}

function Start-RipotStoreApp([string]$PackageFamilyName) {
    if (-not ('RipotStoreActivation' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IRipotApplicationActivationManager {
    [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appId,
        [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint processId);
    [PreserveSig] int ActivateForFile(IntPtr appId, IntPtr itemArray, IntPtr verb, out uint processId);
    [PreserveSig] int ActivateForProtocol(IntPtr appId, IntPtr itemArray, out uint processId);
}
[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
class RipotApplicationActivationManager { }
public static class RipotStoreActivation {
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern int GetPackageFullName(IntPtr process, ref uint length, StringBuilder name);
    [DllImport("shcore.dll")] static extern int GetProcessDpiAwareness(IntPtr process, out int awareness);
    [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr window);
    [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr context);
    public static uint Launch(string appId) {
        var manager = (IRipotApplicationActivationManager)new RipotApplicationActivationManager();
        try {
            uint id;
            Marshal.ThrowExceptionForHR(manager.ActivateApplication(appId, null, 0, out id));
            return id;
        } finally { Marshal.ReleaseComObject(manager); }
    }
    public static string PackageName(uint id) {
        IntPtr handle = OpenProcess(0x1000, false, id);
        if (handle == IntPtr.Zero) throw new InvalidOperationException("Cannot inspect the activated process.");
        try {
            uint length = 0;
            int result = GetPackageFullName(handle, ref length, null);
            if (result != 122) throw new InvalidOperationException("Process has no package identity: " + result);
            var name = new StringBuilder((int)length);
            result = GetPackageFullName(handle, ref length, name);
            if (result != 0) throw new InvalidOperationException("Cannot read package identity: " + result);
            return name.ToString();
        } finally { CloseHandle(handle); }
    }
    public static int DpiAwareness(uint id) {
        IntPtr handle = OpenProcess(0x0400, false, id);
        if (handle == IntPtr.Zero) throw new InvalidOperationException("Cannot inspect process DPI awareness.");
        try {
            int awareness;
            Marshal.ThrowExceptionForHR(GetProcessDpiAwareness(handle, out awareness));
            return awareness;
        } finally { CloseHandle(handle); }
    }
    public static int WindowDpiAwareness(IntPtr window) {
        return GetAwarenessFromDpiAwarenessContext(GetWindowDpiAwarenessContext(window));
    }
}
'@
    }
    $processId = [RipotStoreActivation]::Launch("${PackageFamilyName}!Ripot")
    $process = Get-Process -Id $processId
    $actualPackage = [RipotStoreActivation]::PackageName($processId)
    $registered = @(Get-AppxPackage | Where-Object { $_.PackageFamilyName -eq $PackageFamilyName })
    if ($registered.Count -ne 1 -or $registered[0].PackageFullName -ne $actualPackage) {
        throw 'Activated process did not have the installed MSIX package identity.'
    }
    return $process
}

function Get-RipotStoreDpiState($Process) {
    # Activation can return before User32 initializes the process. Call this
    # only after the native workflow has waited for the visible main window.
    $Process.Refresh()
    if ($Process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'DPI inspection requires the initialized main window.' }
    $processAwareness = [RipotStoreActivation]::DpiAwareness($Process.Id)
    $windowAwareness = [RipotStoreActivation]::WindowDpiAwareness($Process.MainWindowHandle)
    if ($windowAwareness -ne 2) {
        throw "Ripot window is not per-monitor DPI aware: process=$processAwareness, window=$windowAwareness."
    }
    return "Runtime DPI awareness after window initialization: process=$processAwareness, window=$windowAwareness (per-monitor)."
}
