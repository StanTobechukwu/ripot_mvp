# Template contributions and catalogue

The app and landing page read the same approved community catalogue in Firebase
project **ripot-4edf7**. The landing Hosting project is separately **ripot-landing**.
Starter templates remain available from the static landing catalogue.

## One-time setup (project owner)

Run commands from the repository root, with Node 20 and Firebase CLI installed.
The production backend is not deployed by GitHub CI or Deploy-Web.command.

1. `npm ci --prefix functions`
2. Register/sign in to Ripot with the account that will review submissions.
   Use an administrator's Google application-default credentials on your own
   computer (for example `gcloud auth application-default login`), then:
   `node functions/scripts/template-reviewer.js ripot-4edf7 YOUR_REGISTERED_EMAIL grant`
   `check` verifies the assigned role; `revoke` removes it. Contributors cannot
   grant themselves this role. A second reviewer must review your own submissions.
3. Store the outgoing mailbox/app password securely, at the Firebase CLI prompt:
   `firebase functions:secrets:set TEMPLATE_SMTP_PASSWORD --project ripot-4edf7`
   Never put this password in Git, this chat, the browser app, or an email.
   Defaults: SMTP host mail.privateemail.com, TLS port 465, SMTP user
   support@ripot.app. Confirm these with your actual mail provider. If different,
   set TEMPLATE_SMTP_HOST and TEMPLATE_SMTP_USER in functions/.env.ripot-4edf7.
   Only the notification worker can access the password. Recipient is fixed at
   support@ripot.app, not controlled by a contributor.
4. Deploy only the new backend and the existing restrictive rules:
   `firebase deploy --project ripot-4edf7 --only functions:submitTemplateContribution,functions:listTemplateContributions,functions:reviewTemplateContribution,functions:publicTemplateLibrary,functions:notifyTemplateContribution,firestore:rules`
5. Deploy the compiled web app using its Deploy-Web.command. Deploy the updated
   landing directory separately: run `firebase deploy --only hosting --project ripot-landing`
   from inside landing/.
6. Sign in to https://ripot-web.web.app/?templateLibrary=review. The queue shows
   the pending count. Confirm a deliberately submitted patient-free test template
   appears in the queue, triggers an email, can be reviewed by a different account,
   and appears at https://ripot.app/templates/ and in the app after approval.

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
