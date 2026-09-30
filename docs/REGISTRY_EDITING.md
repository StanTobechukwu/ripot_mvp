# Registry editing update

The registry now groups its main actions and supports entering values directly
from the table.

- **Registry → Add:** add a patient or a field. Importing a report still uses
  the existing patient-confirmation and value-review flow.
- **Patient → Update:** add a dated observation or edit patient details,
  including name, identifier, facility and static fields.
- **Patient options:** export CSV or remove the patient from this registry.
- **Entry options:** explicitly correct an entry or delete it with confirmation.
- **Latest table:** tap a value or **+ Add**, use **Next field** to enter more
  values, then save once. Dated measurements create a new observation. Static
  details create a new revision; clearing a static value remains an explicit
  clear.
- **All updates / patient history table:** tapping an editable saved value
  opens **Correct this entry** with its original field definitions and units.
  Corrections replace that entry's values; they are not a separate audit log.
  Other observations and source reports are unchanged. Stale correction
  editors are rejected.
- **Column menu:** edit current field settings. Long press is a shortcut.
  Retired or changed-unit columns retain their historical definitions.
- **Columns:** reveal directory/source metadata or hide unwanted columns. The
  patient identity stays pinned while other columns scroll horizontally.

Renaming/regrouping a field no longer splits values with the same stable key,
unit, type and scope. Legacy values with missing field definitions remain
visible in a separate column; their units are not inferred and those entries
cannot be corrected through the table.

## Verification

Run from the project root:

```sh
flutter test test/features/registry_test.dart test/features/registry_dialog_test.dart test/features/registry_workflow_test.dart test/features/registry_patient_details_test.dart test/features/registry_editing_test.dart
```

Before publishing, check on an Android phone with fictional data:

1. Open a registry table. Add two measurements using **Next field** and confirm
   that one new dated observation is saved, with the previous observation intact.
2. Edit a static detail and the patient name. Verify that the same patient remains
   linked to their existing history. Cancel a second edit and verify no change.
3. Correct a historical entry, then cancel both an entry-deletion confirmation
   and a patient-removal confirmation.
4. Rename a column and verify its existing values remain visible. If a unit
   changes, verify the earlier unit stays in a separate column.
5. Check the keyboard, large text, table scrolling, CSV export and encrypted
   registry backup/restore.

This change does not publish a release or change the app version.
