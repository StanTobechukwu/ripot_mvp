[CmdletBinding()]
param([string]$Flutter = 'flutter')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Run the Build Microsoft Store MSIX workflow on GitHub, or build on Windows.' }
. (Join-Path $PSScriptRoot 'store_package_tools.ps1')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $repo
try {
    $match = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
    if (-not $match.Success) { throw 'Expected version: major.minor.patch+build in pubspec.yaml.' }
    $version = $match.Groups[1].Value
    $build = [int]$match.Groups[2].Value
    # The fourth component is reserved for Microsoft Store.
    $storeVersion = "$version.0"
    $parsed = [version]$storeVersion
    if ($parsed.Major -lt 1 -or $parsed.Major -gt 65535 -or $parsed.Minor -gt 65535 -or $parsed.Build -gt 65535) {
        throw 'The version cannot be represented as a Store package version.'
    }
    function Invoke-Flutter([string[]]$Arguments) {
        & $Flutter @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter failed: $($Arguments -join ' ')" }
    }
    Invoke-Flutter -Arguments @('config', '--enable-windows-desktop')
    Invoke-Flutter -Arguments @('pub', 'get', '--enforce-lockfile')
    Invoke-Flutter -Arguments @('test')
    Invoke-Flutter -Arguments @('test', '--dart-define=RIPOT_MICROSOFT_STORE=true', 'test/features/windows_store_update_test.dart')
    Invoke-Flutter -Arguments @('build', 'windows', '--release', '--dart-define=RIPOT_MICROSOFT_STORE=true')

    $bundle = Join-Path $repo 'build/windows/x64/runner/Release'
    foreach ($relative in @('ripot.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so', 'data/flutter_assets')) {
        if (-not (Test-Path (Join-Path $bundle $relative))) { throw "Incomplete release bundle: $relative" }
    }
    $staging = Join-Path $repo 'build/windows-store-staging'
    $output = Join-Path $repo 'build/windows-store'
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    if (Test-Path $output) { Remove-Item $output -Recurse -Force }
    New-Item $staging, $output -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $bundle '*') $staging -Recurse -Force
    Get-ChildItem $staging -Recurse -File | Where-Object { $_.Extension -in @('.pdb', '.lib', '.exp') } | Remove-Item -Force

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Visual Studio C++ tools are required.' }
    $redistRoot = Join-Path ($vs | Select-Object -First 1) 'VC/Redist/MSVC'
    $redistVersion = Get-ChildItem $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $redistVersion) { throw 'MSVC redistributable folder not found.' }
    $crt = Get-ChildItem (Join-Path $redistVersion.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
    if (-not $crt) { throw 'MSVC x64 runtime not found.' }
    Copy-Item (Join-Path $crt.FullName '*.dll') $staging -Force
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path (Join-Path $staging $dll))) { throw "Missing runtime: $dll" }
    }

    Add-Type -AssemblyName System.Drawing
    $assets = New-Item (Join-Path $staging 'Assets') -ItemType Directory -Force
    $logo = [Drawing.Image]::FromFile((Join-Path $repo 'assets/ripot_icon.png'))
    try {
        foreach ($item in @(@('StoreLogo', 50), @('Square44x44Logo', 44), @('Square150x150Logo', 150))) {
            $size = [int]$item[1]
            $bitmap = [Drawing.Bitmap]::new($size, $size)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $ratio = [Math]::Min($size / $logo.Width, $size / $logo.Height)
                $width = [int][Math]::Round($logo.Width * $ratio)
                $height = [int][Math]::Round($logo.Height * $ratio)
                $graphics.DrawImage($logo, [int](($size - $width) / 2), [int](($size - $height) / 2), $width, $height)
                $bitmap.Save((Join-Path $assets.FullName ($item[0] + '.png')), [Drawing.Imaging.ImageFormat]::Png)
            } finally { $graphics.Dispose(); $bitmap.Dispose() }
        }
    } finally { $logo.Dispose() }

    [xml]$manifest = Get-Content 'windows/packaging/AppxManifest.xml' -Raw
    $manifest.Package.Identity.Version = $storeVersion
    $manifest.Save((Join-Path $staging 'AppxManifest.xml'))
    $filename = "Ripot-$storeVersion-windows-x64.msix"
    $package = Join-Path $output $filename
    $makeappx = Get-RipotSdkTool 'makeappx.exe'
    & $makeappx pack /o /d $staging /p $package /h SHA256
    if ($LASTEXITCODE -ne 0) { throw 'MakeAppx validation/packaging failed.' }
    $commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record source commit.' }
    & git diff --quiet --no-ext-diff HEAD --
    if ($LASTEXITCODE -ne 0) { throw 'The build changed tracked source files.' }
    $untracked = @(& git ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0 -or $untracked.Count -ne 0) { throw 'Untracked source files prevent release provenance verification.' }
    $hash = (Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
    $provenance = [ordered]@{
        product = 'Ripot'; channel = 'microsoft-store'; appVersion = $version; build = $build
        packageVersion = $storeVersion; architecture = 'x64'; filename = $filename
        identityName = [string]$manifest.Package.Identity.Name
        publisher = [string]$manifest.Package.Identity.Publisher
        publisherDisplayName = [string]$manifest.Package.Properties.PublisherDisplayName
        sourceCommit = $commit; sourceDirty = $false; sha256 = $hash
        sizeBytes = (Get-Item $package).Length; signedForSideloading = $false
        builtAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    $provenance | ConvertTo-Json | Set-Content (Join-Path $output 'windows-store-release.json') -Encoding utf8
    "$hash  $filename" | Set-Content (Join-Path $output 'SHA256SUMS.txt') -Encoding ascii
    Copy-Item (Join-Path $staging 'AppxManifest.xml') $output
    Write-Host "Unsigned Store submission package: $package"
    Write-Host 'Microsoft Store supplies the public signature. Use a separate copy for local test signing.'
} finally { Pop-Location }
