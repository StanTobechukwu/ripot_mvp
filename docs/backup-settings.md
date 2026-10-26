# Backup settings — implementation and validation

Open **More → Backup & restore** from My Reports.

- Everything includes editable reports, saved PDFs, images, signatures, templates, letterheads, Records, Registry and Logbook. Account credentials, billing and device settings are excluded.
- Reports, Registry, Logbook, Records and Templates can also be backed up separately. Managed full and section backups share the selected folder, with independent retention for each type.
- Keep 3, 5, 7 or 10 dated copies. Earlier owned copies are removed only after the replacement is written and verified. Unrelated files are not rotated.
- Automatic full backups are optional, daily or weekly, at a preferred local time. Manual backups and retention changes preserve the next automatic due time. Unchanged data is skipped. Failed automatic saves retain the due time and retry after 15 minutes.
- Unsaved automatic settings are marked on screen. Leaving through app navigation offers Save settings, Discard changes or Keep editing. A cancelled passphrase or failed save keeps the page and draft open. Folder selection, retention updates and manual backups preserve an unfinished schedule; folder and retention choices are saved immediately. Simply visiting the page does not prompt.
- Android uses a persisted folder grant and a Workmanager worker. Android may delay background execution; force-stop suspends it until the app reopens. Desktop scheduling requires the app to be open. Browser scheduling requires an open tab, folder permission and the session passphrase.
- Unsupported managed-folder platforms use a normal file save/download. Browser downloads require the user to confirm that the file was saved; they cannot be automatically verified or rotated.
- Backups use AES-256-GCM and PBKDF2-HMAC-SHA256 with 600,000 iterations. Native automatic backups store the passphrase using secure storage; web keeps it in memory for the current tab. Forgotten passphrases cannot be recovered.
- Restore validates and previews the backup before confirmation. Everything replaces local data; section restores add missing items and preserve current versions. Records restore rebuilds report links and skips duplicate entries for the same report.
- A recovery journal protects interrupted restores. Automatic backups pause before restore changes local data. Verify restored work before re-enabling automatic backups.

## Verification

Flutter 3.38.5 / Dart 3.10.4:

- Full Dart test suite: 227 passed, one skipped.
- Backup-specific tests: 12 passed, covering encryption/tampering, schedule preservation, automatic skip/retry, folder changes, full restore with media/PDFs, missing attachments, invalid identities/paths, section merges, interrupted recovery and retention.
- Backup static analysis: no issues.
- Release web build: passed.
- Dependency resolution with the checked-in lockfile: passed.
- Browser file bridge tests: seven passed, covering rotation, failure recovery, permissions, collisions, locking and unrelated files.

Reproduce with:

```sh
flutter pub get --enforce-lockfile
flutter analyze lib/features/backup test/features/backup
flutter test --no-pub
node --test tools/web/backup_bridge_test.cjs
flutter build web --release --no-pub --no-wasm-dry-run
```

The backup-checks workflow also compiles an Android debug APK to check the selected-folder plugin and worker. Android compilation, device folder permissions and background timing still need verification before release. No production deployment is included in this change.
