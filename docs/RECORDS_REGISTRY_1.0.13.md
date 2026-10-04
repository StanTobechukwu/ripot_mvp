# Ripot 1.0.13 (48) — Records and Registry product pass

This release builds on 1.0.12 (47). It does not replace the already-published
Android or Windows 47 packages in place.

## Records

Records are structured-first rather than a second copy of the report.

- Structured Yes/No, choice and numeric values remain the preferred reusable
  data for filtering, CSV export, comparison and future analytics.
- Narrative fields are still supported where prose is clinically appropriate,
  especially diagnosis, impression, conclusion, notes and recommendations.
- Choosing arbitrary free-text report/template fields for Records now explains
  that the value is narrative and asks for confirmation.
- Creating an arbitrary narrative-only extra Records field also asks for
  confirmation.
- A report action is state-aware:
  - **Add to Records** when no linked Record exists.
  - **View Record** when the linked Record is current.
  - **Update Record** when selected source-report data changed.
- Updating from a report refreshes the stored report snapshot while preserving
  a deliberate clinician correction made inside Records.
- The linked report ID remains the unique report-to-Record relationship, so
  repeating the action does not create duplicate Records.

## Registry

Registry remains the longitudinal patient view; Reports remain the complete
clinical document.

- A Registry patient can keep a **Related reports** list.
- Importing a report into a dated Registry update links that report to the
  patient automatically.
- A clinician may explicitly link another finalized Ripot report from the
  patient screen. Ripot does not auto-link by patient name alone.
- A report cannot be linked to two different Registry patient identities.
- Source-linked reports stay linked while their Registry update exists.
- Dated Registry updates can contain images without requiring another value.
- Images can be:
  - selected from the source Ripot report; or
  - added directly to the dated Registry update.
- Direct Registry images can have an optional caption.
- Dated image thumbnails appear on the patient timeline and open into a larger
  viewer.
- Selected Registry images are embedded in the encrypted Registry backup so
  restored backups retain their images. Source report PDFs remain outside the
  Registry backup.
- Existing Registry backup versions remain readable.

## Updates

Android keeps the Google Play in-app update check introduced for build 47.

Windows build 48 adds support for a future update prompt. On startup it can read
`https://ripot.app/updates/windows.json`. If the manifest advertises a higher
build, Ripot offers **Download update** or **Later**. It never silently installs
an update. The Windows landing-page release preparer now writes this manifest
alongside a verified public installer release.

A Windows user on build 47 cannot receive Ripot's own Windows update dialog,
because that code was not in build 47. Build 48 can prompt for build 49 and
later. The landing page remains the manual upgrade path for earlier Windows
builds.

## Manual checks before publishing

1. From a finalized report, verify **Add to Records**. Save the Record.
2. Reopen the report action and verify **View Record**.
3. Change a selected report value, save/finalize, and verify **Update Record**.
4. Correct that field inside Records, change the report again, update the
   Record, and confirm the deliberate Record correction remains.
5. Select an arbitrary free-text field for Records and verify the narrative
   warning. Verify diagnosis/impression remains intentionally supported.
6. Open a Registry patient, link an existing report and open it from Related
   reports.
7. Add a report to Registry, select some source report images, save and verify
   thumbnails on the dated patient card.
8. Add a direct Registry image, caption it, save it, and reopen the image.
9. Create an encrypted Registry backup containing images and restore it as a
   copy. Verify the thumbnails still open.
10. Verify the existing Add patient/Add field flow, direct table-cell editing,
    Next field navigation and explicit Patient detail/Dated measurement selector.
11. On Android installed through Google Play, keep the Play update flow
    regression-tested.
12. On a Windows build, verify a missing/unreachable update manifest never
    blocks startup. When publishing a later Windows build, update the landing
    manifest and verify Download update opens the exact published installer.
