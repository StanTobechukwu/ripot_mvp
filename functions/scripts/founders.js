#!/usr/bin/env node
// Administrator-only audit/migration. Never ship credentials or its output.
const { parseArgs } = require("node:util");
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { migrateFounders } = require("../founder-migration");

async function main() {
  const { values } = parseArgs({ options: {
    project: { type: "string" }, apply: { type: "boolean", default: false },
    "expected-hash": { type: "string" },
    "include-legacy-84-day-trials": { type: "boolean", default: false },
  } });
  if (!values.project) throw new Error("Pass --project explicitly. The default operation is read-only.");
  if (values.apply && !values["expected-hash"]) throw new Error("Apply requires the reviewed dry-run --expected-hash.");
  initializeApp({ projectId: values.project, credential: applicationDefault() });
  const registeredUids = [];
  let anonymousAuthAccounts = 0;
  let pageToken;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      if (user.providerData.length > 0) registeredUids.push(user.uid);
      else anonymousAuthAccounts++;
    }
    pageToken = page.pageToken;
  } while (pageToken);
  const report = await migrateFounders(getFirestore(), {
    registeredUids,
    includeLegacy: values["include-legacy-84-day-trials"],
    apply: values.apply,
    expectedHash: values["expected-hash"],
  });
  console.log(JSON.stringify({ project: values.project, anonymousAuthAccounts, ...report }, null, 2));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
