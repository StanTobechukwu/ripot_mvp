# Microsoft Store package

The `Build Microsoft Store MSIX` workflow creates a Windows x64 MSIX from the
same Flutter source as the standalone Windows app. It uses Flutter 3.38.5 and
the Windows SDK on a disposable Windows Server 2022 runner.

## Partner Center identity

- Name: `RipotTechnologiesLtd.RipotClinicalReportsPDF`
- Publisher: `CN=3847E5A6-6457-4608-A67B-00E03F0C03C2`
- PublisherDisplayName: `Ripot Technologies Ltd`
- Store ID: `9P91S5JQ1FK0`

The source manifest is `windows/packaging/AppxManifest.xml`. The build derives
the package version from the three-part pubspec version, with a zero fourth
component reserved for the Store. For `1.0.25+60`, the package is `1.0.25.0`;
the Flutter build remains 60. Increment the three-part pubspec version before
publishing a subsequent Store update; incrementing only `+build` is insufficient.

## Build and checks

Run `./tools/windows/build_store_msix.ps1` on Windows. It runs the Flutter tests,
builds with `RIPOT_MICROSOFT_STORE=true`, includes the x64 MSVC runtime, generates
package logos from the existing Ripot asset and validates the package with
MakeAppx. The Store flag prevents the standalone EXE update prompt from appearing;
Store installs receive updates through Microsoft Store.

The package targets Windows Desktop build 19041 or newer. No Mobile, Xbox,
Team or Mixed Reality package is produced. The only declared restricted
capability is `runFullTrust`, required for this Flutter desktop executable.
If Partner Center requests justification, explain that the desktop process
creates, opens and exports local clinical report PDFs and uses native Windows
file dialogs and printing. It does not require administrator elevation.

In CI, `check_store_msix.ps1` validates the archive, exact identity, version,
source commit and checksum. A separate temporary copy is signed using a
non-exportable self-signed test key, installed, and activated through its AUMID.
The native workflow check verifies that the running process has package identity,
creates a fictional report, saves a PDF, reopens it after restarting and checks
the Free account prompts. The certificate and installation are removed afterward.
No test key or signed test copy is uploaded as a release artifact.

Windows App Certification Kit runs if installed on the runner. Its result is
reported separately from the install/workflow checks; inspect the XML report
and resolve failures. CI records each non-passing test, including whether it is
optional, and blocks required failures. A green workflow is not Microsoft
certification.

The initial package check flagged `NOTICES.Z` (verified to contain only UTF-8
licence text), process-launch API and executable-name references in Flutter,
PDFium, URL launching and printing dependencies, and a DPI-awareness warning.
The runner manifest now includes both the legacy per-monitor declaration and
PerMonitorV2. The binary-processing/DPI warning still occurred on the Windows
Server CI runner. After the main window initializes, the installed-app check
queries both process and window DPI modes and requires per-monitor window
awareness. Activation alone can return before User32 initializes. Re-run
WACK and check scaling on a supported Windows client before Store submission;
the runtime check does not override or clear WACK's warning.
Keep the licence notices; do not remove them to silence a scanner.
Review the current report and test the relevant URL/printing behavior on the
intended Windows editions. Microsoft describes the Desktop Bridge archive and
blocked-executable tests as informational [optional tests](https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-desktop-bridge-app-tests).

## Upload

Download `ripot-microsoft-store-x64-<run number>` and extract it. In Partner
Center, open **Submission 1 > Packages** and upload the `.msix` inside. The ZIP
artifact itself, JSON provenance, checksum file and manifest XML are not the
app package. Select Windows 10/11 Desktop as the device family.

Microsoft signs accepted MSIX submissions. No purchased code-signing
certificate is needed for Store upload. This unsigned file is not a public
sideload installer. Do not distribute the CI test certificate.

## Release checks still required

Test on a supported Windows client, including live account sign-in/Premium,
physical printing and backup/restore. The automated guest workflow uses fictional
data and does not exercise paid account credentials.

MSIX uses a different installation identity and can virtualize AppData. Do not
promise automatic migration from the existing EXE installation. Keep the old
installation and a verified exported backup until a migration has been tested;
never uninstall it as a migration step without protecting the user's data.

Complete the listing, screenshots, privacy-policy validation and accurate age
rating answers in Partner Center. Package generation does not submit or publish
the app.
