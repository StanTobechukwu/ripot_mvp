const { test, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { ACTIVITY, ANDROID_APP_ID, createActivityService, summarizeActivity } = require("../installation-activity");

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith("demo-")) {
  throw new Error("Use the Firestore emulator and a demo- project. Tests erase emulator data.");
}
const app = initializeApp();
const db = getFirestore(app);
let now;
const record = createActivityService(db, () => now);
const request = (uid) => ({
  app: { appId: ANDROID_APP_ID },
  ...(uid ? { auth: { uid, token: { firebase: { sign_in_provider: "password" } } } } : {}),
  data: { schemaVersion: 1, installationSecret: "ab".repeat(32), platform: "android", appVersion: "1.0.11", buildNumber: "40" },
});
const read = async () => (await db.collection(ACTIVITY).get()).docs[0]?.data();

beforeEach(async () => {
  now = new Date("2026-09-27T12:00:00Z");
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  assert.equal(response.ok, true);
});
after(() => deleteApp(app));

test("unattested and unexpected apps cannot submit activity", async () => {
  for (const app of [undefined, { appId: "other-app" }]) {
    await assert.rejects(record({ ...request(), app }), { code: "failed-precondition" });
  }
  assert.equal((await db.collection(ACTIVITY).get()).size, 0);
});

test("guest heartbeats are idempotent, use trusted time, and never create entitlements", async () => {
  const replies = await Promise.all(Array.from({ length: 5 }, () => record(request())));
  assert.equal(replies.filter((r) => r.recorded).length, 1);
  const first = await read();
  assert.equal(first.lastSeenAt.toDate().toISOString(), now.toISOString());
  assert.equal(first.firstSeenAt.toDate().toISOString(), now.toISOString());
  assert.equal(first.observedDays, 1);
  assert.equal(first.lastAuthState, "guest");
  assert.equal(first.everRegistered, false);
  assert.equal(first.installationSecret, undefined);
  assert.equal(first.lastRegisteredUid, undefined);
  assert.equal((await db.collection("ripot_user_access").get()).size, 0);
  assert.equal((await db.collection("ripot_internal").get()).size, 0);
  now = new Date("2026-09-27T18:01:00Z");
  assert.equal((await record(request())).recorded, true);
  assert.equal((await read()).observedDays, 1);
  now = new Date("2026-09-28T00:01:00Z");
  await record(request());
  assert.equal((await read()).observedDays, 2);
  assert.equal((await read()).firstSeenAt.toMillis(), first.firstSeenAt.toMillis());
});

test("registration is linked only from verified auth; signing out preserves the known link", async () => {
  await record(request());
  await record(request("registered-a"));
  const signedIn = await read();
  assert.equal(signedIn.lastAuthState, "registered");
  assert.equal(signedIn.lastRegisteredUid, "registered-a");
  assert.equal(signedIn.everRegistered, true);
  await record(request());
  const guest = await read();
  assert.equal(guest.lastAuthState, "guest");
  assert.equal(guest.lastRegisteredUid, "registered-a");
  assert.equal(guest.everRegistered, true);
  assert.equal((await db.collection(ACTIVITY).get()).size, 1);
  await record(request("registered-b"));
  assert.equal((await read()).lastRegisteredUid, "registered-b");
  const anonymous = request("anonymous");
  anonymous.auth.token.firebase.sign_in_provider = "anonymous";
  await record(anonymous);
  assert.equal((await read()).lastRegisteredUid, "registered-b");
  assert.equal((await read()).lastAuthState, "guest");
});

test("client IDs, clocks, content and entitlements are rejected, not silently stored", async () => {
  for (const extra of [{ uid: "someone-else" }, { plan: "premium" }, { founderNumber: 1 },
    { lastSeenAt: "2030-01-01" }, { patientName: "must-not-be-stored" }]) {
    const input = request();
    Object.assign(input.data, extra);
    await assert.rejects(record(input), { code: "invalid-argument" });
  }
  for (const invalid of [{ installationSecret: "guessable" }, { buildNumber: "" },
    { appVersion: "x".repeat(100) }, { schemaVersion: 2 }, { platform: "web" }]) {
    const input = request();
    Object.assign(input.data, invalid);
    await assert.rejects(record(input), { code: "invalid-argument" });
  }
  assert.equal((await db.collection(ACTIVITY).get()).size, 0);
});

test("activity leaves paid access and Founder membership byte-for-byte intact", async () => {
  const access = { ownerId: "paid", plan: "premium", founderNumber: 7, trialEndsAtIso: "2026-10-01T00:00:00Z" };
  const ledger = { uid: "paid", founderNumber: 7 };
  await db.doc("ripot_user_access/paid").set(access);
  await db.doc("ripot_internal/founding_100/members/paid").set(ledger);
  await record(request("paid"));
  assert.deepEqual((await db.doc("ripot_user_access/paid").get()).data(), access);
  assert.deepEqual((await db.doc("ripot_internal/founding_100/members/paid").get()).data(), ledger);
});

test("summary separates guest activity from accounts and shows stale/empty coverage", async () => {
  const empty = summarizeActivity([], now);
  assert.equal(empty.collectionStatus, "no_observations");
  assert.equal(empty.firstObservationAtIso, null);
  await record(request());
  let summary = summarizeActivity([await read()], now);
  assert.equal(summary.sinceRollout.neverObservedSignedIn, 1);
  await record(request("account"));
  await record(request());
  summary = summarizeActivity([await read()], now);
  assert.equal(summary.sinceRollout.neverObservedSignedIn, 0);
  assert.equal(summary.sinceRollout.previouslySignedInNowGuest, 1);
  assert.equal(summary.sinceRollout.observedInstallations, 1);
  summary = summarizeActivity([await read(), {}], new Date("2026-10-01T12:00:00Z"));
  assert.equal(summary.collectionStatus, "no_observations_in_48_hours");
  assert.equal(summary.last24Hours.observedInstallations, 0);
  assert.equal(summary.last7Days.observedInstallations, 1);
  assert.equal(summary.excludedInvalidRecords, 1);
});
