[CmdletBinding()]
param(
    [string]$Flutter = 'flutter',
    [string]$Iscc = '',
    [string]$RuntimeDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') {
    throw 'Build on Windows, or run the Build Windows installer workflow on GitHub.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $repo
try {
    $versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
    if (-not $versionMatch.Success) { throw 'pubspec.yaml needs version: major.minor.patch+build.' }
    $version = $versionMatch.Groups[1].Value
    $build = $versionMatch.Groups[2].Value
    $fileVersion = "$version.$build"
    $releaseId = "$version-$build"
    $installerName = "Ripot-Setup-$releaseId-windows-x64"
    $portableName = "Ripot-$releaseId-windows-x64.zip"

    function Invoke-Flutter {
        param([string[]]$Arguments)
        & $Flutter @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter failed: $($Arguments -join ' ')" }
    }

    Invoke-Flutter -Arguments @('config', '--enable-windows-desktop')
    Invoke-Flutter -Arguments @('pub', 'get', '--enforce-lockfile')
    Invoke-Flutter -Arguments @('test')
    Invoke-Flutter -Arguments @('build', 'windows', '--release')

    $bundle = Join-Path $repo 'build/windows/x64/runner/Release'
    foreach ($relative in @('ripot.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets')) {
        if (-not (Test-Path (Join-Path $bundle $relative))) { throw "Incomplete release bundle: $relative" }
    }

    # Include the MSVC runtime for PCs without Visual Studio installed.
    if (-not $RuntimeDirectory) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if (-not (Test-Path $vswhere)) { throw 'Install Visual Studio with the Desktop development with C++ workload.' }
        $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (-not $vs) { throw 'Visual Studio C++ tools not found.' }
        $redistRoot = Join-Path ($vs | Select-Object -First 1) 'VC/Redist/MSVC'
        $redistVersion = Get-ChildItem $redistRoot -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+' } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if (-not $redistVersion) { throw 'MSVC redistributable folder not found.' }
        $crt = Get-ChildItem (Join-Path $redistVersion.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' |
            Select-Object -First 1
        if (-not $crt) { throw 'MSVC x64 runtime DLLs not found.' }
        $RuntimeDirectory = $crt.FullName
    }
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path (Join-Path $RuntimeDirectory $dll))) { throw "Missing MSVC runtime: $dll" }
    }
    Copy-Item (Join-Path $RuntimeDirectory '*.dll') $bundle -Force

    if (-not $Iscc) {
        $candidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 6/ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 7/ISCC.exe')
        )
        $Iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Iscc -or -not (Test-Path $Iscc)) {
        throw 'Install Inno Setup from jrsoftware.org, then rerun with -Iscc <path-to-ISCC.exe>.'
    }
    $output = Join-Path $repo "build/windows-distribution/$releaseId"
    New-Item $output -ItemType Directory -Force | Out-Null
    & $Iscc "/DAppVersion=$version" "/DAppFileVersion=$fileVersion" "/DBundleDir=$bundle" "/DOutputDir=$output" "/DOutputName=$installerName" (Join-Path $PSScriptRoot 'ripot.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
    $installer = Join-Path $output "$installerName.exe"
    if (-not (Test-Path $installer)) { throw 'The installer was not created.' }
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath (Join-Path $output $portableName) -Force

    $commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record the source commit.' }
    # Flutter rewrites generated registrants with LF on Windows. With autocrlf,
    # status can report those files as modified even when their Git blobs match.
    # Compare actual content with HEAD, including staged edits, and check new files.
    & git diff --quiet --no-ext-diff HEAD --
    $trackedChanges = $LASTEXITCODE
    if ($trackedChanges -notin @(0, 1)) { throw 'Cannot verify tracked source contents.' }
    $untrackedFiles = @(& git ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot verify untracked source files.' }
    $dirty = ($trackedChanges -eq 1) -or ($untrackedFiles.Count -gt 0)
    $sha = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        product = 'Ripot'; version = $version; build = [int]$build
        releaseStage = 'internal-test'
        releaseNote = 'Windows REST account integration is implemented. Complete live account, encrypted credential storage and native Windows installer validation before public release.'
        platform = 'windows'; architecture = 'x64'; minimumWindows = '10'
        filename = "$installerName.exe"; sha256 = $sha
        sizeBytes = (Get-Item $installer).Length
        sourceCommit = $commit; sourceDirty = $dirty
        builtAt = (Get-Date).ToUniversalTime().ToString('o')
        signatureStatus = (Get-AuthenticodeSignature $installer).Status.ToString()
    }
    $manifest | ConvertTo-Json | Set-Content (Join-Path $output 'windows-release.json') -Encoding utf8
    $checksums = foreach ($file in @($installer, (Join-Path $output $portableName))) {
        "$((Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($file))"
    }
    $checksums | Set-Content (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
    Write-Host "Installer and portable bundle: $output"
    Write-Host 'Test installation, PDF/printing, account access and registry edits on a Windows PC before publishing.'
}
finally { Pop-Location }
