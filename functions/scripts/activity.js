#!/usr/bin/env node
// Read-only operator report. Uses existing ADC, never prints account IDs.
const { initializeApp, applicationDefault, deleteApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { ACTIVITY, summarizeActivity } = require("../installation-activity");

async function main() {
  const args = process.argv.slice(2);
  if (args.length !== 2 || args[0] !== "--project" || !/^[a-z][a-z0-9-]+$/.test(args[1])) {
    throw new Error("Usage: npm run activity:audit -- --project YOUR_FIREBASE_PROJECT");
  }
  const app = initializeApp({ projectId: args[1], credential: applicationDefault() });
  try {
    const db = getFirestore(app);
    const [snapshot, registry, members] = await Promise.all([
      db.collection(ACTIVITY).get(),
      db.doc("ripot_internal/founding_100").get(),
      db.collection("ripot_internal/founding_100/members").get(),
    ]);
    let registeredAccounts = 0;
    let accountsWithoutLinkedProvider = 0;
    let nextPageToken;
    do {
      const page = await getAuth(app).listUsers(1000, nextPageToken);
      for (const user of page.users) {
        if (user.providerData?.length) registeredAccounts++;
        else accountsWithoutLinkedProvider++;
      }
      nextPageToken = page.pageToken;
    } while (nextPageToken);
    const numbers = members.docs.map((doc) => doc.data().founderNumber).sort((a, b) => a - b);
    const consistent = registry.exists && registry.data().assignedCount === numbers.length &&
      numbers.length <= 100 && numbers.every((n, i) => n === i + 1);
    console.log(JSON.stringify({
      projectId: args[1],
      registeredAccounts,
      accountsWithoutLinkedProvider,
      accountCountDefinition: "Registered accounts have a linked sign-in provider. Providerless records are separate; they may be anonymous or custom-auth accounts.",
      founders: {
        registryStatus: !registry.exists ? "not_initialized" : consistent ? "consistent" : "needs_review",
        confirmedAssigned: consistent ? numbers.length : null,
        remaining: consistent ? 100 - numbers.length : null,
      },
      activity: summarizeActivity(snapshot.docs.map((doc) => doc.data())),
    }, null, 2));
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  // No payload, tokens, or UIDs in the error output.
  console.error("Activity audit failed:", error.code || error.name);
  process.exitCode = 1;
});
