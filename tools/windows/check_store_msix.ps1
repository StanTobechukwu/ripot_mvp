[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactDirectory,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT' -or $env:GITHUB_ACTIONS -ne 'true') {
    throw 'Run the test certificate/install check only on a disposable GitHub Windows runner.'
}
. (Join-Path $PSScriptRoot 'store_package_tools.ps1')
$artifact = (Resolve-Path $ArtifactDirectory).Path
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$output = (Resolve-Path $OutputDirectory).Path
$work = Join-Path $env:RUNNER_TEMP ('ripot-msix-' + [guid]::NewGuid())
New-Item $work -ItemType Directory -Force | Out-Null
$identity = 'RipotTechnologiesLtd.RipotClinicalReportsPDF'
$publisher = 'CN=3847E5A6-6457-4608-A67B-00E03F0C03C2'
$displayPublisher = 'Ripot Technologies Ltd'
$report = [ordered]@{ result = 'incomplete'; checks = @(); certificationKit = 'not run' }
$certificate = $null
$installed = $null
try {
    if (@(Get-AppxPackage -Name $identity).Count -ne 0) { throw 'Refusing to replace an existing Ripot package.' }
    $release = Get-Content (Join-Path $artifact 'windows-store-release.json') -Raw | ConvertFrom-Json
    if ($release.sourceCommit -ne $ExpectedCommit -or $release.sourceDirty) { throw 'Store package source verification failed.' }
    if ([IO.Path]::GetFileName($release.filename) -ne $release.filename) { throw 'Invalid MSIX filename.' }
    $package = Join-Path $artifact $release.filename
    if ((Get-FileHash $package -Algorithm SHA256).Hash -ne $release.sha256 -or (Get-Item $package).Length -ne $release.sizeBytes) {
        throw 'MSIX hash or size mismatch.'
    }
    $report.sourceCommit = $release.sourceCommit
    $report.uploadSha256 = $release.sha256
    $unpacked = Join-Path $work 'unpacked'
    $makeappx = Get-RipotSdkTool 'makeappx.exe'
    & $makeappx unpack /p $package /d $unpacked /o
    if ($LASTEXITCODE -ne 0) { throw 'Cannot unpack and validate the MSIX.' }
    [xml]$manifest = Get-Content (Join-Path $unpacked 'AppxManifest.xml') -Raw
    if ($manifest.Package.Identity.Name -cne $identity -or $manifest.Package.Identity.Publisher -cne $publisher -or
        $manifest.Package.Properties.PublisherDisplayName -cne $displayPublisher) {
        throw 'Manifest identity does not exactly match Partner Center.'
    }
    if ($manifest.Package.Identity.ProcessorArchitecture -ne 'x64' -or
        $manifest.Package.Identity.Version -ne $release.packageVersion -or
        ([version]$manifest.Package.Identity.Version).Revision -ne 0) { throw 'Invalid Store architecture or version.' }
    foreach ($relative in @('ripot.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets')) {
        if (-not (Test-Path (Join-Path $unpacked $relative))) { throw "Incomplete MSIX: $relative" }
    }
    if (Test-Path (Join-Path $unpacked 'AppxSignature.p7x')) { throw 'The Store upload file must remain unsigned in this workflow.' }
    $report.checks += 'Upload checksum, source commit, exact Partner Center identity, x64 payload and Store version verified.'

    # Only a disposable copy is signed. No private key or test signature enters the upload artifact.
    $certificate = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature `
        -FriendlyName 'Ripot disposable CI MSIX check' -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyExportPolicy NonExportable -HashAlgorithm SHA256 `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
        -NotAfter (Get-Date).AddDays(2)
    $publicCertificate = Join-Path $work 'ci-test.cer'
    Export-Certificate -Cert $certificate -FilePath $publicCertificate | Out-Null
    Import-Certificate -FilePath $publicCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    $signedCopy = Join-Path $work $release.filename
    Copy-Item $package $signedCopy
    $signtool = Get-RipotSdkTool 'signtool.exe'
    & $signtool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $signedCopy
    if ($LASTEXITCODE -ne 0) { throw 'Temporary CI signing failed.' }
    & $signtool verify /pa /v $signedCopy
    if ($LASTEXITCODE -ne 0) { throw 'Temporary CI signature validation failed.' }
    Add-AppxPackage -Path $signedCopy
    $installed = Get-AppxPackage -Name $identity
    if ($null -eq $installed -or $installed.Publisher -cne $publisher -or
        $installed.Version.ToString() -ne $release.packageVersion) { throw 'Installed MSIX identity/version mismatch.' }
    $report.packageFullName = $installed.PackageFullName
    $report.checks += 'A separately test-signed copy installed successfully.'
    & (Join-Path $PSScriptRoot 'check_installed_workflows.ps1') -ArtifactDirectory $artifact `
        -ExpectedCommit $ExpectedCommit -OutputDirectory (Join-Path $output 'workflow') `
        -AppxPackageFamilyName $installed.PackageFamilyName
    $workflow = Get-Content (Join-Path $output 'workflow/workflow-result.json') -Raw | ConvertFrom-Json
    if ($workflow.result -ne 'passed') { throw 'Installed MSIX workflow check failed.' }
    $report.checks += $workflow.checks

    $appcert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/App Certification Kit/appcert.exe'
    if (Test-Path $appcert) {
        & $appcert reset
        $certReport = Join-Path $output 'app-certification.xml'
        $certProcess = Start-Process $appcert -ArgumentList @('test', '-packagefullname', $installed.PackageFullName,
            '-reportoutputpath', "`"$certReport`"") -PassThru
        if (-not $certProcess.WaitForExit(900000)) {
            Stop-Process -Id $certProcess.Id -Force
            $report.certificationKit = 'timed out; manual certification-kit run required'
        } elseif (Test-Path $certReport) {
            $report.certificationKit = "completed; exit code $($certProcess.ExitCode); review app-certification.xml"
            $report.certificationKitExitCode = $certProcess.ExitCode
            # WACK can exit successfully with warnings or optional test failures.
            # Surface the XML results and never treat exit code zero as certification.
            [xml]$certXml = Get-Content $certReport -Raw
            $report.certificationKitOverall = [string]$certXml.REPORT.OVERALL_RESULT
            $issues = @(foreach ($test in $certXml.SelectNodes('/REPORT/REQUIREMENTS/REQUIREMENT/TEST')) {
                $result = $test.SelectSingleNode('RESULT').InnerText.Trim()
                if ($result -ne 'PASS') {
                    [ordered]@{
                        name = [string]$test.NAME; result = $result
                        optional = [string]$test.OPTIONAL -eq 'TRUE'
                        messages = @($test.SelectNodes('MESSAGES/MESSAGE') | ForEach-Object { [string]$_.TEXT })
                    }
                }
            })
            $report.certificationKitIssues = $issues
            if (@($issues | Where-Object { -not $_.optional -and $_.result -eq 'FAIL' }).Count -gt 0) {
                throw 'Windows App Certification Kit reported a required test failure. Review app-certification.xml.'
            }
            if ($issues.Count -gt 0) { Write-Warning 'Certification-kit findings require review; see store-package-check.json.' }
        } else {
            $report.certificationKit = "no report; exit code $($certProcess.ExitCode); manual certification-kit run required"
        }
    } else {
        $report.certificationKit = 'not installed on runner; manual certification-kit run required'
    }
    if ((Get-FileHash $package -Algorithm SHA256).Hash -ne $release.sha256) { throw 'Store upload file changed during testing.' }
    $report.result = 'passed'
    $report.remaining = 'Review certification-kit results; test on a supported Windows client, live sign-in/Premium, physical printing and backup/restore before publishing. This is not Microsoft Store certification.'
} catch {
    $report.result = 'failed'
    $report.error = $_.Exception.Message
    throw
} finally {
    if ($null -ne $installed) {
        Get-Process ripot -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($installed.InstallLocation + '\*') } | Stop-Process -Force
        Remove-AppxPackage -Package $installed.PackageFullName -ErrorAction Continue
        if (@(Get-AppxPackage -Name $identity).Count -eq 0) { $report.checks += 'The disposable MSIX installation was removed.' }
    }
    if ($null -ne $certificate) {
        Remove-Item "Cert:\LocalMachine\TrustedPeople\$($certificate.Thumbprint)" -Force -ErrorAction Continue
        Remove-Item "Cert:\CurrentUser\My\$($certificate.Thumbprint)" -Force -ErrorAction Continue
    }
    if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction Continue }
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'store-package-check.json') -Encoding utf8
    $report | ConvertTo-Json -Depth 8 | Write-Host
}
