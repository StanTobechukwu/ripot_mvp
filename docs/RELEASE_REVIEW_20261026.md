# Release review — 26 October 2026

Base inspected: `b7b70a95d117d25e2db21f8c3671cd97c95b9939` on `codex/release-hardening-20261025`.
Fix branch: `codex/review-dialog-fix-20261026`; PR #6.

## Verified

- Base web and Android Actions builds passed (runs 40277550738 and 40277550762). Android artifact is unsigned; successful compilation is not a Play release.
- Template backend public health probe returns `contributions: ready`. Notification and reviewer setup have already been completed; no reason to repeat setup.
- Source catalogue has 15 templates, including the new specialty/procedure templates. Landing verification checks 30 PDF assets, their hashes, preview pages, links and download labels.
- No analytics collector is configured. Funnel tests confirm no patient values, arbitrary query values or network collector. Retain Google Search Console only, per the user's decision.
- Production web `https://ripot-web.web.app/release.json` still reports **1.0.16+51**, commit `5e3664884c1603e780f86aea84cc89906ba14a5a`. The newer 1.0.17+52 preview does not imply a production release.
- Live landing catalogue still contains **4** templates; the source catalogue has **15**.
- Live landing community script does not yet contain the hardening branch's empty-state hiding change.

## Review fix

Feedback and errors stay inside one review dialog. Reject and Request changes require a reason, show a saving state and prevent duplicate clicks. Close dismisses without a mutation. A confirmed decision removes the pending row immediately; a subsequent refresh failure is reported separately.

Self-review remains prohibited by the backend for every decision, including rejection. The dialog explains this rule; errors no longer appear only on the underlying queue screen. An independent reviewer is still required for the owner's contributions.

Widget regressions cover narrow-screen Close with 200 preview sections, required feedback, rejection/change-request completion, duplicate taps, permission/network/stale-revision failures and publication confirmation. A backend emulator test verifies rejected status, author feedback, removal from the pending queue and absence from public templates. Check PR #6 Actions for final outcomes.

## Outstanding before release

1. Verify the fix in the deployed web preview using a submission owned by a different account. Confirm rejection feedback in My submissions, then check Request changes and approval/publication with synthetic patient-free content.
2. Complete full-app backup work if it remains a release requirement. Current encrypted backups are separate Registry and Logbook features. Records packages explicitly omit editable reports, templates and field settings. A complete encrypted My Reports/template/app backup is not implemented.
3. The current report-save reminder is first save/every fifth explicit save. It has no full-app backup history reset, 20-record-change trigger, last full-app backup date or direct full-app backup action. Corrected its copy so it does not promise a nonexistent report backup tool. Do not suppress report reminders after a partial Registry/Logbook backup.
4. Finish synthetic backup/restore acceptance checks for the supported formats and explicitly document unsupported content. Existing automated tests do not constitute a full-app round-trip.
5. Check free/trial/Premium PDF regression artifacts and physically print a long report with images/signature. Automated geometry checks cannot verify a physical printer.
6. Deploy the verified web and landing artifacts; neither an Actions build nor a preview updates production. Recheck the production release marker afterward.
7. Sign the Android bundle with the existing Play upload key, verify its version code is available in Play, run an internal-device smoke test, and upload/release it through Play Console.
8. Request indexing/submit the sitemap in Search Console after landing deployment. No additional usage analytics is required or enabled.
