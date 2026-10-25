# Template contributions and catalogue

The app and landing page read the same approved community catalogue in Firebase
project **ripot-4edf7**. The landing Hosting project is separately **ripot-landing**.
Starter templates remain available from the static landing catalogue.

## One-time setup (project owner)

Run commands from the repository root, with Node 20 and Firebase CLI installed.
The production backend is not deployed by GitHub CI or Deploy-Web.command.

The core submission/review service and email delivery are deployed separately.
A missing SMTP password must not prevent contributors submitting templates.
The scripts are in the release folder, or `tools/deploy/` in the source checkout.
They select project `ripot-4edf7` explicitly and do not deploy unrelated functions.

1. On your Mac, sign into the Firebase CLI with an authorised project-owner
   account: `firebase login`. Use Node 20 or newer. Open Terminal in the extracted
   release folder (the folder containing these scripts, not inside `landing`).
2. Run `bash Deploy-Template-Services.command`. This installs backend dependencies,
   deploys submission/list/review/public-library functions and restrictive rules,
   then runs a read-only endpoint check. It does not require an SMTP password.
   A 404 means a route is absent at the configured project/region; it is not proof
   that the contributor's internet is broken.
3. Register/sign in to Ripot with the account that will review submissions.
   The reviewer setup uses Google application-default credentials with authority
   to read Firebase Auth and write Firestore. Firebase CLI login alone is not
   application-default login. If needed, install Google Cloud CLI and run
   `gcloud auth application-default login` on your own computer, then run
   `bash Setup-Template-Reviewer.command` and enter the registered account email.
   No service-account key belongs in the app or release folder. For manual control:
   `node functions/scripts/template-reviewer.js ripot-4edf7 YOUR_REGISTERED_EMAIL check`
   (replace `check` with `grant` or `revoke` when intended).
   A second reviewer must review your own contributions.
4. Confirm the outgoing mailbox provider. Defaults are SMTP `mail.privateemail.com`,
   TLS port 465 and user `support@ripot.app`. If different, set TEMPLATE_SMTP_HOST
   and TEMPLATE_SMTP_USER in `functions/.env.ripot-4edf7` locally; never commit
   credentials. Run `bash Setup-Template-Notifications.command`. Enter the mailbox
   or app password only into Firebase's secure secret prompt. The script deploys
   only the notification worker. Recipient is fixed at `support@ripot.app`.
5. Run `bash Deploy-Web.command`, then `bash Deploy-Landing.command` from the release
   folder. In a source checkout, build the web app before deploying hosting and
   deploy the separate landing project from `landing/`.
6. Sign in to https://ripot-web.web.app/?templateLibrary=review. Test the following
   with two registered accounts (contributor and independent reviewer):
   - Create or import a patient-free template in Templates; open Online templates
     and choose Contribute. Enter specialty, description, contributor credit and
     the two declarations. Submit and confirm it appears in My submissions.
   - Confirm the reviewer sees the pending item and support@ripot.app receives
     an email. Deployment success alone does not establish inbox delivery.
   - Request changes with feedback. Confirm the contributor can see the feedback,
     update the local structure and resubmit a new revision.
   - Approve as the independent reviewer. Confirm the same approved version is
     available on https://ripot.app/templates/ and in the app. The public catalogue
     may be cached for up to 60 seconds.
   - Preview, add a personal copy, reopen offline and confirm the original
     contribution is not changed by edits to that copy.

At any time, `node functions/scripts/check-template-services.js` safely checks the
public response and verifies all three callables reject unauthenticated requests.
It does not submit data, approve templates, send mail or prove signed-in access.
The app now separates missing service, sign-in, validation, rate-limit, stale
revision and connectivity errors, preserving form entries for safe retries.

## Workflow and privacy

Submit a template from the online library's Contribute action; use Templates →
Import first for a file. Required metadata: name, specialty, description, public
contributor name, patient-free declaration and permission to publish. Report
content, notes, signatures, registry flags, custom subject fields and unknown
keys are stripped. A human reviewer must still inspect titles, choices and
metadata for identifiers or inappropriate content. The declaration and reviewed
revision are retained. Approval is not a guarantee of clinical suitability.

Pending submissions and review feedback are accessible only through authenticated
server endpoints to their owner or a server-assigned reviewer. Firestore client
rules deny all contribution, role, publication and email collection access.
Each account may submit at most ten new templates or revisions per day. Retries
reuse a request ID, preventing duplicate submissions and queue items. Approval
requires the same revision the reviewer previewed; revisions don't replace the
last approved public version until approved. The public API never returns account
IDs, reviewer notes or private queue records. Published payload versions are
immutable and SHA-256 checked by both app and landing page. To withdraw an unsafe
publication, a project administrator sets its ripot_public_templates/<slug>
status to withdrawn; this hides current and historical versions after the short
public cache expires. Existing downloaded personal copies cannot be recalled.

The app saves a separate personal copy, preserving source slug, version and
contributor. An updated publication is offered as a NEW copy; it never changes
edited templates or reports. Saved templates work offline. Plan template limits
still apply. The landing community gallery is fetched dynamically; its new
community pages are not generated as individual server-rendered SEO pages.

## Notifications and recovery

A durable ripot_template_mail/<submission>-<revision> record is created in the
same transaction as submission. Its status is queued, retrying, or sent. The
Firestore worker sends a minimal alert with a fixed review link, without template
content or patient data, over authenticated TLS SMTP. Email delivery retries
when SMTP fails. SMTP has no exactly-once guarantee: a crash after provider
acceptance can deliver the same Message-ID twice. `sent` means SMTP accepted the
message, not that it reached the inbox. The review queue works independently.
Monitor failed function invocations and stale queued/retrying records in Firebase.
After retries expire or for records created before the worker was deployed,
a project administrator can create a NEW mail document containing the same
submissionId/revision/createdAt and status queued to explicitly requeue it.
Never grant clients write access to the mail collection. Configure provider SPF,
DKIM and mailbox delivery separately. No live email has been sent by automated tests.

## Verification

`npx firebase-tools@14.22.0 emulators:exec --only firestore --project demo-ripot-founders --config firebase.test.json "npm test --prefix functions"`

`flutter test` and `flutter analyze --no-fatal-infos --no-fatal-warnings` cover
client models and catalogue validation. CI compiles the web app and exercises
its template opening flow in a real browser, then packages exact compiled bytes.
Backend tests use only a disposable demo emulator, never production Firebase.
