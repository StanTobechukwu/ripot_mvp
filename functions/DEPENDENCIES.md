# Backend dependency maintenance

Use Node.js 22, matching `package.json` and the Firebase deployment runtime.
Install the committed dependency graph with `npm ci --prefix functions` from
the repository root. Both backend CI workflows run `npm audit --prefix functions`
and the Firestore emulator suite.

Two scoped overrides accompany the November 2026 security update:

- Firebase's Node 22-compatible test SDK pins `@grpc/grpc-js` to the 1.9 line.
  Its Firestore dependency uses 1.14.7 here to address
  [GHSA-m9gg-hp2v-232j](https://github.com/advisories/GHSA-m9gg-hp2v-232j)
  and [GHSA-f596-whhp-79r4](https://github.com/advisories/GHSA-f596-whhp-79r4).
  The rules tests exercise the patched client against the emulator.
- `@google-cloud/firestore-api` accepts `google-gax ^5.0.0`. Pin its copy to
  5.0.4, within that supported range. Later 5.0 patches add an unused runtime
  dependency on `rimraf` / `glob` / `minimatch`, bringing
  [GHSA-3g3m-2fjr-6pw4](https://github.com/advisories/GHSA-3g3m-2fjr-6pw4)
  and [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249).
  The published 5.0.8 runtime has no `rimraf` imports. Keep the separate
  top-level Firestore dependency on google-gax 6 as declared by its publisher.

Review these overrides when upstream dependencies change; remove each once its
parent selects a patched dependency without the override. Do not use
`npm audit fix --force` to cross major versions without compatibility testing.

Run the full backend checks with a demo project only:

```sh
npm ci --prefix functions
npm audit --prefix functions
npx --yes firebase-tools@14.22.0 emulators:exec --only firestore --project demo-ripot-founders --config firebase.test.json "npm test --prefix functions"
```

The tests include transactions, limits, entitlement protections, Firestore
rules, template review and actual Nodemailer message serialization using an
in-memory transport. They do not contact a real SMTP server or send email.
