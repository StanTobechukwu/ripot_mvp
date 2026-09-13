# Ripot card menus, template groups and Logbook

Baseline: `a7a498948e8f3d3421f7398099f6fa91501010d9` on `ripot-structured-inputs-image-flow`.

Reports and templates now open their action menu on long press or the visible three-dot button. Normal report taps preserve the existing editor/PDF flow. Normal template taps start a report. Template groups have one level; removing a group moves its templates to Ungrouped. Existing report/template identifiers are preserved.

Use the Logbook destination for Quick Log. Choose your name in Doctors and select “This is me” to prefill it next time. Other participants are optional. Each doctor has a stable identity; performer, assistant and observer roles, supervision, report author and the person signing are recorded separately.

A report's menu offers Add to Logbook, then View log entry once saved. To prefill selected clinical fields in future reports, enable “Include when adding to Logbook” in the template section's field settings. Review/remove copied subject information before saving. Log entries are saved snapshots; deleting their source report does not delete them. Records retain their existing Premium access rules. Quick Log and backup introduce no new paywall.

Filter Logbook by doctor, procedure/facility/reference and date, then print or share the filtered PDF. “Include entry details” adds participant names, notes, copied fields and the current signature. Counts describe the filtered entries, with supervision counted separately. These exports do not imply institutional acceptance or competency certification.

In-person signatures require a fresh drawing after review. The displayed label is “Signature recorded”; this does not authenticate identity. Editing an entry creates a new version requiring a fresh signature. Earlier signed snapshots remain available. Signature timestamps come from the device.

## Backup and restore

The working Logbook remains local. Android's Logbook files are excluded from automatic OS cloud backup/device transfer; use the explicit encrypted backup instead. No new Firebase collection, billing change, server deployment or patient-data upload is introduced.

An encrypted Logbook backup contains entries, doctor identities and signed versions. It does not include original reports, PDFs, images, Records or account entitlements. Encryption uses AES-256-GCM and PBKDF2-HMAC-SHA256 (600,000 iterations, random salt/nonce). The passphrase is not stored and cannot be recovered by Ripot. Each backup needs the passphrase used when it was created. The v1 import limit is 40 MB (28 MB of unencrypted content).

Android uses the system folder picker and persisted access to the user-selected folder; files are visible in Files. A new backup is written and read back before an older managed copy is deleted. Ripot keeps two backups it manages in that folder. Files copied/renamed manually, or retained from another installation, may remain. Failed cleanup is reported. Desktop folders support rotation too. Web and iOS use individual file export and explicitly state that automatic rotation is unavailable.

A backup kept on the same phone cannot recover data after losing the phone. Copy an encrypted backup to a computer, drive or a storage provider you choose. Your selected provider may sync its folder.

An inline reminder appears after 20 new entries or a week with unbacked changes. Snooze postpones it for one day. A successful backup marks only the snapshot actually written. Restore validates/decrypts the entire backup, previews its counts and asks before replacing the current Logbook. It does not append duplicate entries or replace other app data.

## Validation and device review

Automated coverage includes group removal, report deletion preserving logs, stable doctor identities, concurrent saves, failed writes, stale signatures, signed revision preservation, reminder counters, repeated restore, wrong passwords, tampered backups, local recovery, rotation and narrow-screen/large-text interactions. A PDF test covers Unicode text, a long note and a signature image. Android Kotlin sources are compiled against the Flutter embedding and Android API classes.

Before a Play release, run the app on your Android test device and check the actual Files-provider interaction: create sample logs, sign one, save three backups, confirm two managed completed files remain, and restore the latest backup. Check the report/template menus and a doctor-filtered PDF. A full Android app-bundle build and real-device SAF test are still required on your configured Mac. The patch does not bump the app version or deploy/push anything.
