const { test, beforeEach, after } = require("node:test");
const assert = require("node:assert/strict");

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.GCLOUD_PROJECT?.startsWith("demo-")) {
  throw new Error("Run with the Firestore emulator and a demo- project. These tests delete emulator data.");
}
const endpoints = require("../index");
const { getFirestore } = require("firebase-admin/firestore");
const { getApp, deleteApp } = require("firebase-admin/app");
const {
  createFounderService, registryRef, ACCESS, DAY_MS, isFounder, requireRegisteredUid,
} = require("../founding-100");
const { migrateFounders, auditAccounts } = require("../founder-migration");
const db = getFirestore();
const fixedNow = new Date("2026-09-27T12:00:00Z");
const service = createFounderService(db, () => fixedNow);

beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: "DELETE" });
  assert.equal(response.ok, true);
});
after(() => deleteApp(getApp()));

async function initialize(count = 0) {
  const batch = db.batch();
  batch.set(registryRef(db), { schemaVersion: 1, assignedCount: count, maxFounders: 100 });
  for (let i = 1; i <= count; i++) {
    batch.set(registryRef(db).collection("members").doc(`previous-${i}`), { uid: `previous-${i}`, founderNumber: i });
  }
  await batch.commit();
}

test("registration is required and invalid Founder numbers are rejected", () => {
  assert.throws(() => requireRegisteredUid({}), { code: "unauthenticated" });
  assert.throws(() => requireRegisteredUid({ auth: { uid: "guest", token: { firebase: { sign_in_provider: "anonymous" } } } }), { code: "failed-precondition" });
  assert.equal(requireRegisteredUid({ auth: { uid: "account", token: { firebase: { sign_in_provider: "password" } } } }), "account");
  for (const number of [0, -1, 101, 2.5, "1", null]) assert.equal(isFounder({ founderCohort: "founding_100", founderNumber: number }), false);
});

test("first activation grants exactly 84 days; concurrent retries consume one slot", async () => {
  await initialize();
  const results = await Promise.all(Array.from({ length: 6 }, () => service.activate("same-account")));
  assert.equal(results.filter((r) => r.activated).length, 1);
  assert(results.every((r) => r.founderNumber === 1));
  const data = (await db.collection(ACCESS).doc("same-account").get()).data();
  assert.equal(Date.parse(data.trialEndsAtIso) - Date.parse(data.trialStartAtIso), 84 * DAY_MS);
  assert.equal((await registryRef(db).get()).data().assignedCount, 1);
  const replay = await createFounderService(db, () => new Date("2027-01-01")).activate("same-account");
  assert.equal(replay.activated, false);
  assert.equal(replay.trialEndsAtIso, data.trialEndsAtIso);
});

test("concurrent claims at the cap grant only Founder #100; others get 21 days", async () => {
  await initialize(99);
  const results = await Promise.all(Array.from({ length: 6 }, (_, i) => service.activate(`last-slot-${i}`)));
  assert.equal(results.filter((r) => r.founder).length, 1);
  assert.equal(results.find((r) => r.founder).founderNumber, 100);
  assert(results.filter((r) => !r.founder).every((r) => r.trialDays === 21));
  assert.equal((await registryRef(db).collection("members").get()).size, 100);
  assert.equal((await registryRef(db).get()).data().assignedCount, 100);
});

test("missing or corrupt counters fail closed instead of reusing Founder numbers", async () => {
  await assert.rejects(service.activate("fresh"), { code: "failed-precondition" });
  await initialize(2);
  await registryRef(db).set({ assignedCount: 0 }, { merge: true });
  await assert.rejects(service.activate("fresh"), { code: "failed-precondition" });
  assert.equal((await db.collection(ACCESS).doc("fresh").get()).exists, false);
});

test("legacy flags and 21-day trials cannot claim or restart Founder access", async () => {
  await initialize();
  await db.collection(ACCESS).doc("legacy").set({
    plan: "trial", hasUsedTrial: true, isEarlyUser: true,
    trialStartAtIso: "2026-05-01T00:00:00Z", trialEndsAtIso: "2026-05-22T00:00:00Z",
  });
  const response = await service.activate("legacy");
  assert.equal(response.alreadyUsed, true);
  assert.equal(response.founder, false);
  assert.equal((await service.sync("legacy")).founder, false);
  assert.equal((await registryRef(db).get()).data().assignedCount, 0);
});

test("membership survives access-document removal without starting another 84 days", async () => {
  await initialize();
  const original = await service.activate("founder");
  await db.collection(ACCESS).doc("founder").delete();
  await service.sync("founder");
  const restored = await createFounderService(db, () => new Date("2027-01-01")).activate("founder");
  assert.equal(restored.activated, false);
  assert.equal(restored.founderNumber, 1);
  assert.equal(restored.trialEndsAtIso, original.trialEndsAtIso);
  assert.equal((await registryRef(db).get()).data().assignedCount, 1);
});

test("reviewed legacy migration is chronological, idempotent, and preserves paid/trial access", async () => {
  const rows = [
    ["later", "2026-08-01T00:00:00Z", "trial"],
    ["earlier", "2026-07-01T00:00:00Z", "premium"],
  ];
  for (const [uid, start, plan] of rows) await db.collection(ACCESS).doc(uid).set({
    ownerType: "user", ownerId: uid, authUid: uid, plan, hasUsedTrial: true,
    trialStartAtIso: start, trialEndsAtIso: new Date(Date.parse(start) + 84 * DAY_MS).toISOString(),
    billingProvider: plan === "premium" ? "google_play" : null,
  });
  await db.collection(ACCESS).doc("usr_installation").set({ ...((await db.collection(ACCESS).doc("earlier").get()).data()), ownerType: "installation" });
  const options = { registeredUids: ["later", "earlier", "no-profile"], includeLegacy: true };
  const before = (await db.collection(ACCESS).doc("earlier").get()).data();
  const preview = await migrateFounders(db, options);
  assert.equal(preview.legacyCandidatesToAdd, 2);
  assert.equal(preview.founders[0].uid, "earlier");
  assert.equal((await registryRef(db).get()).exists, false);
  await assert.rejects(migrateFounders(db, { ...options, apply: true, expectedHash: "wrong" }), /Review hash/);
  await migrateFounders(db, { ...options, apply: true, expectedHash: preview.reviewHash });
  const migrated = (await db.collection(ACCESS).doc("earlier").get()).data();
  for (const key of Object.keys(before)) assert.deepEqual(migrated[key], before[key]);
  assert.equal(migrated.founderNumber, 1);
  assert.equal(migrated.founderFirstYearDiscountPercent, 0);
  const second = await migrateFounders(db, options);
  assert.equal(second.legacyCandidatesToAdd, 0);
  await migrateFounders(db, { ...options, apply: true, expectedHash: second.reviewHash });
  assert.equal((await registryRef(db).get()).data().assignedCount, 2);
  assert.equal((await service.sync("earlier")).founderNumber, 1);
  await assert.rejects(service.activate("earlier"), /Premium is already active/);
  const next = await service.activate("next-account");
  assert.equal(next.founderNumber, 3);
});

test("migration rechecks trial dates before committing the reviewed plan", async () => {
  const data = { ownerType: "user", ownerId: "old", authUid: "old", hasUsedTrial: true,
    trialStartAtIso: "2026-07-01T00:00:00Z", trialEndsAtIso: "2026-09-23T00:00:00Z" };
  await db.collection(ACCESS).doc("old").set(data);
  const options = { registeredUids: ["old"], includeLegacy: true };
  const preview = await migrateFounders(db, options);
  await db.collection(ACCESS).doc("old").update({ trialEndsAtIso: "2026-07-22T00:00:00Z" });
  await assert.rejects(migrateFounders(db, { ...options, apply: true, expectedHash: preview.reviewHash }), /Review hash/);
});

test("audit separates accounts, linked installations, unlinked records, and unknown people", () => {
  const report = auditAccounts(["a", "b"], [
    { uid: "a", data: { installationId: "usr_linked" } },
    { uid: "usr_linked", data: {} }, { uid: "usr_unlinked", data: {} },
  ]);
  assert.equal(report.registeredAccounts, 2);
  assert.equal(report.registeredAccountsWithoutAccessDocument, 1);
  assert.equal(report.installationRecordsWithoutKnownAccountLink, 1);
  assert.equal(report.uniqueUnregisteredPeople, null);
  assert.equal(report.currentlyActiveUnregisteredPeople, null);
});

test("Founder trial status does not enable the separate annual paid offer", async () => {
  await initialize();
  await service.activate("founder");
  const status = await endpoints.getBillingEligibility.run({ auth: { uid: "founder" }, data: {} });
  assert.equal(status.founder, true);
  assert.equal(status.founderDiscountEligible, false);
  assert.equal(status.founderDiscountPercent, 0);
});

test("an already-owned Founder Play purchase can refresh; new discount purchases stay disabled", async () => {
  const { GoogleAuth } = require("google-auth-library");
  const { createHash } = require("node:crypto");
  const token = "test-only-existing-purchase-token";
  const tokenHash = createHash("sha256").update(token).digest("hex");
  await db.collection(ACCESS).doc("paid-founder").set({
    founderCohort: "founding_100", founderNumber: 1, founderDiscountRedeemed: true,
    founderDiscountRedeemedAtIso: "2026-01-01T00:00:00Z", plan: "premium",
  });
  await db.collection("ripot_internal_play").doc("paid-founder").set({
    purchaseTokenHash: tokenHash, offerId: "founding-100-annual-25",
  });
  const originalClient = GoogleAuth.prototype.getClient;
  const originalFetch = global.fetch;
  GoogleAuth.prototype.getClient = async () => ({ getAccessToken: async () => "test-only-mocked-token" });
  global.fetch = async (url, options) => {
    if (!String(url).startsWith("https://androidpublisher.googleapis.com/")) return originalFetch(url, options);
    return new Response(JSON.stringify({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
      lineItems: [{ productId: "ripot_premium", expiryTime: "2099-01-01T00:00:00Z",
        offerDetails: { basePlanId: "annual", offerId: "founding-100-annual-25" } }],
    }), { status: 200 });
  };
  try {
    const result = await endpoints.verifyGooglePlaySubscription.run({
      auth: { uid: "paid-founder" }, data: { productId: "ripot_premium", purchaseToken: token },
    });
    assert.equal(result.entitled, true);
    assert.equal((await db.collection(ACCESS).doc("paid-founder").get()).data().founderDiscountRedeemedAtIso, "2026-01-01T00:00:00Z");
    await assert.rejects(endpoints.verifyGooglePlaySubscription.run({
      auth: { uid: "other-account" }, data: { productId: "ripot_premium", purchaseToken: token },
    }), { code: "permission-denied" });
    await assert.rejects(endpoints.verifyGooglePlaySubscription.run({
      auth: { uid: "paid-founder" }, data: { productId: "ripot_premium", purchaseToken: "test-only-new-discount-token" },
    }), { code: "failed-precondition" });
  } finally {
    GoogleAuth.prototype.getClient = originalClient;
    global.fetch = originalFetch;
  }
});
