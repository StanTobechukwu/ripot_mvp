const { test, before, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, query, where } = require("firebase/firestore");

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith("demo-")) {
  throw new Error("Use the Firestore emulator and a demo- project. Tests erase emulator data.");
}
let env;
const ownMetadata = { ownerType: "user", ownerId: "alice", authUid: "alice", installationId: "usr_existing" };
before(async () => {
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
  env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT,
    firestore: { host, port: Number(port), rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8") },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "ripot_user_access", "alice"), { ...ownMetadata, plan: "premium", founderNumber: 3 });
    await setDoc(doc(db, "ripot_app_config", "access"), { founderLimit: 100 });
    await setDoc(doc(db, "ripot_template_structures", "existing"), { ...ownMetadata, name: "Existing" });
    await setDoc(doc(db, "ripot_installation_activity", "existing"), { lastAuthState: "guest" });
  });
});
after(async () => { if (env) await env.cleanup(); });

test("guests retain public config access without gaining access or template permissions", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(db, "ripot_app_config", "access")));
  await assertFails(setDoc(doc(db, "ripot_app_config", "access"), { founderLimit: 1 }));
  await assertFails(getDoc(doc(db, "ripot_user_access", "alice")));
  await assertFails(setDoc(doc(db, "ripot_user_access", "usr_guest"), ownMetadata));
  await assertFails(getDoc(doc(db, "ripot_template_structures", "existing")));
  await assertFails(setDoc(doc(db, "ripot_template_structures", "new"), ownMetadata));
});

test("accounts can read their own entitlement and update existing harmless metadata", async () => {
  const db = env.authenticatedContext("alice").firestore();
  assert.equal((await assertSucceeds(getDoc(doc(db, "ripot_user_access", "alice")))).data().plan, "premium");
  await assertSucceeds(setDoc(doc(db, "ripot_user_access", "alice"), {
    ...ownMetadata, lastSeenInstallationId: "usr_current", lastClientSeenAtIso: "2026-09-27T12:00:00Z",
  }, { merge: true }));
  const bob = env.authenticatedContext("bob").firestore();
  await assertSucceeds(setDoc(doc(bob, "ripot_user_access", "bob"), { ownerType: "user", ownerId: "bob", authUid: "bob" }));
  await assertFails(getDoc(doc(bob, "ripot_user_access", "alice")));
  await assertFails(updateDoc(doc(bob, "ripot_user_access", "alice"), { installationId: "stolen" }));
  await assertFails(getDocs(collection(db, "ripot_user_access")));
  await assertFails(deleteDoc(doc(db, "ripot_user_access", "alice")));
});

test("accounts cannot self-grant Premium, trials, Founder status or billing access", async () => {
  const db = env.authenticatedContext("alice").firestore();
  for (const change of [{ plan: "free" }, { trialEndsAtIso: "2030-01-01" }, { founderNumber: 1 },
    { founderCohort: "founding_100" }, { hasUsedTrial: false }, { billingProvider: "google_play" },
    { playEntitlementExpiresAtIso: "2030-01-01" }, { ownerId: "bob" }]) {
    await assertFails(updateDoc(doc(db, "ripot_user_access", "alice"), change));
  }
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(setDoc(doc(bob, "ripot_user_access", "bob"), { ownerType: "user", ownerId: "bob", authUid: "bob", plan: "premium" }));
});

test("activity, Founder ledger and purchase tokens remain private for every client", async () => {
  for (const context of [env.unauthenticatedContext(), env.authenticatedContext("alice")]) {
    const db = context.firestore();
    for (const path of ["ripot_installation_activity/existing", "ripot_installation_activity/existing/events/day",
      "ripot_internal/founding_100", "ripot_internal/founding_100/members/alice",
      "ripot_internal_play/alice", "ripot_internal_play_tokens/token"] ) {
      await assertFails(getDoc(doc(db, path)));
      await assertFails(setDoc(doc(db, path), { arbitrary: true }));
      await assertFails(deleteDoc(doc(db, path)));
    }
    await assertFails(getDocs(collection(db, "ripot_installation_activity")));
  }
  await env.withSecurityRulesDisabled(async (context) => {
    await assertSucceeds(setDoc(doc(context.firestore(), "ripot_installation_activity", "backend"), { lastAuthState: "guest" }));
  });
});

test("existing account-owned template create, read, list, edit and delete still work", async () => {
  const db = env.authenticatedContext("alice").firestore();
  await assertSucceeds(getDoc(doc(db, "ripot_template_structures", "existing")));
  await assertSucceeds(getDocs(query(collection(db, "ripot_template_structures"), where("ownerType", "==", "user"), where("ownerId", "==", "alice"))));
  await assertSucceeds(setDoc(doc(db, "ripot_template_structures", "new"), { ...ownMetadata, name: "New" }));
  await assertSucceeds(updateDoc(doc(db, "ripot_template_structures", "new"), { name: "Edited" }));
  await assertFails(updateDoc(doc(db, "ripot_template_structures", "existing"), { ownerId: "bob" }));
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "ripot_template_structures", "existing")));
  await assertFails(updateDoc(doc(bob, "ripot_template_structures", "existing"), { name: "stolen" }));
  await assertFails(deleteDoc(doc(bob, "ripot_template_structures", "existing")));
  await assertSucceeds(deleteDoc(doc(db, "ripot_template_structures", "new")));
});
