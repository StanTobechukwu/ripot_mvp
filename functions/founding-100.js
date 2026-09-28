const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const ACCESS = "ripot_user_access";
const COHORT = "founding_100";
const MAX_FOUNDERS = 100;
const FOUNDER_DAYS = 84;
const STANDARD_DAYS = 21;
const DAY_MS = 86400000;
const REGISTRY_VERSION = 1;

function dateFromAny(value) {
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value !== "string") return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function isFounder(data = {}) {
  return data.founderCohort === COHORT &&
    Number.isInteger(data.founderNumber) &&
    data.founderNumber >= 1 && data.founderNumber <= MAX_FOUNDERS;
}

function requireRegisteredUid(request) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  if (request.auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("failed-precondition", "Register or sign in to start a Premium trial.");
  }
  return request.auth.uid;
}

function registryRef(db) {
  return db.collection("ripot_internal").doc(COHORT);
}

function founderFields(number) {
  return {
    founderCohort: COHORT,
    founderNumber: number,
    // The launch benefit is the free trial. Paid offers are configured separately.
    founderFirstYearDiscountPercent: 0,
  };
}

function validateRegistry(counter, members) {
  const numbers = members.map((member) => member.founderNumber).sort((a, b) => a - b);
  if (counter?.schemaVersion !== REGISTRY_VERSION ||
      !Number.isInteger(counter.assignedCount) ||
      counter.assignedCount < 0 || counter.assignedCount > MAX_FOUNDERS ||
      counter.assignedCount !== members.length ||
      numbers.some((number, index) => number !== index + 1)) {
    throw new HttpsError("failed-precondition", "The Founder register needs an administrator review. Please try again later.");
  }
}

function createFounderService(db, clock = () => new Date()) {
  const registry = registryRef(db);
  const members = registry.collection("members");

  async function sync(uid) {
    return db.runTransaction(async (tx) => {
      const memberSnap = await tx.get(members.doc(uid));
      const userRef = db.collection(ACCESS).doc(uid);
      const userSnap = await tx.get(userRef);
      const data = userSnap.data() || {};
      if (!memberSnap.exists) {
        return { founder: false, preservedExistingTrial: data.hasUsedTrial === true };
      }
      const member = memberSnap.data();
      if (!isFounder({ ...member, founderCohort: COHORT })) {
        throw new HttpsError("failed-precondition", "The Founder record needs an administrator review.");
      }
      if (!isFounder(data) || data.founderNumber !== member.founderNumber ||
          data.founderFirstYearDiscountPercent !== 0) {
        tx.set(userRef, {
          ownerType: "user", ownerId: uid, authUid: uid,
          ...founderFields(member.founderNumber),
        }, { merge: true });
      }
      return { founder: true, founderNumber: member.founderNumber };
    });
  }

  async function activate(uid) {
    return db.runTransaction(async (tx) => {
      const userRef = db.collection(ACCESS).doc(uid);
      const userSnap = await tx.get(userRef);
      const memberSnap = await tx.get(members.doc(uid));
      const data = userSnap.data() || {};
      const member = memberSnap.data();
      if (data.plan === "premium") {
        throw new HttpsError("failed-precondition", "Premium is already active.");
      }
      const start = dateFromAny(data.trialStartAtIso || data.trialStartAt);
      const end = dateFromAny(data.trialEndsAtIso || data.trialEndsAt);
      // A permanent member record also prevents a fresh trial if an access
      // document is accidentally removed. Its original dates never restart.
      if (data.hasUsedTrial === true || start || end || memberSnap.exists) {
        if (memberSnap.exists && !isFounder({ ...member, founderCohort: COHORT })) {
          throw new HttpsError("failed-precondition", "The Founder record needs an administrator review.");
        }
        const originalStart = start || dateFromAny(member?.trialStartAtIso);
        const originalEnd = end || dateFromAny(member?.trialEndsAtIso);
        if (memberSnap.exists && !start && !end && originalStart && originalEnd) {
          tx.set(userRef, {
            ownerType: "user", ownerId: uid, authUid: uid,
            ...founderFields(member.founderNumber),
            plan: "trial", hasUsedTrial: true,
            trialStartAtIso: originalStart.toISOString(),
            trialEndsAtIso: originalEnd.toISOString(),
          }, { merge: true });
        }
        return {
          activated: false, alreadyUsed: true,
          founder: memberSnap.exists,
          founderNumber: member?.founderNumber ?? null,
          trialStartAtIso: originalStart?.toISOString() || null,
          trialEndsAtIso: originalEnd?.toISOString() || null,
        };
      }

      // All reads precede writes. A shared counter serializes concurrent claims;
      // the immutable UID ledger detects missing/corrupt counters and duplicates.
      const counterSnap = await tx.get(registry);
      const memberSnaps = await tx.get(members.limit(MAX_FOUNDERS + 1));
      const counter = counterSnap.data();
      validateRegistry(counter, memberSnaps.docs.map((doc) => doc.data()));
      if (data.founderCohort === COHORT || data.founderNumber != null) {
        throw new HttpsError("failed-precondition", "This Founder account needs an administrator review.");
      }
      const founderNumber = counter.assignedCount < MAX_FOUNDERS ? counter.assignedCount + 1 : null;
      const trialDays = founderNumber === null ? STANDARD_DAYS : FOUNDER_DAYS;
      const now = clock();
      const trialStartAtIso = now.toISOString();
      const trialEndsAtIso = new Date(now.getTime() + trialDays * DAY_MS).toISOString();
      if (founderNumber !== null) {
        tx.create(members.doc(uid), {
          uid, founderNumber, trialStartAtIso, trialEndsAtIso,
          source: "server_trial_activation", assignedAt: FieldValue.serverTimestamp(),
        });
        tx.set(registry, {
          assignedCount: founderNumber, updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      tx.set(userRef, {
        ownerType: "user", ownerId: uid, authUid: uid,
        ...(founderNumber !== null ? founderFields(founderNumber) : {}),
        ...(founderNumber !== null ? { founderAssignedAt: FieldValue.serverTimestamp() } : {}),
        plan: "trial", hasUsedTrial: true, trialStartAtIso, trialEndsAtIso,
        trialLengthDaysGranted: trialDays,
        trialGrantedBy: founderNumber !== null ? COHORT : "standard_21_day",
        entitlementAuthority: "cloud_function",
        updatedAtIso: trialStartAtIso, lastSyncedAtIso: trialStartAtIso,
      }, { merge: true });
      return { activated: true, founder: founderNumber !== null, founderNumber, trialDays, trialStartAtIso, trialEndsAtIso };
    }, { maxAttempts: 10 });
  }

  return { sync, activate };
}

module.exports = {
  ACCESS, COHORT, MAX_FOUNDERS, FOUNDER_DAYS, STANDARD_DAYS, DAY_MS,
  REGISTRY_VERSION, registryRef, founderFields, validateRegistry,
  dateFromAny, isFounder, requireRegisteredUid, createFounderService,
};
