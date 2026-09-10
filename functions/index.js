const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

const ACCESS = "ripot_user_access";
const INTERNAL = "ripot_internal";
const COUNTER_DOC = "founding_100";
const FOUNDING_MAX = 100;
const FOUNDER_TRIAL_DAYS = 84;
const STANDARD_TRIAL_DAYS = 21;
const FOUNDER_DISCOUNT_PERCENT = 25;

function requireUid(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in is required.");
  return uid;
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function dateFromAny(value) {
  if (!value) return null;
  if (value instanceof Timestamp) return value.toDate();
  if (typeof value === "string") {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

async function assignFounderIfAvailable(tx, userRef, currentData) {
  if (
    currentData.founderCohort === "founding_100" &&
    Number.isInteger(currentData.founderNumber)
  ) {
    return currentData.founderNumber;
  }

  const counterRef = db.collection(INTERNAL).doc(COUNTER_DOC);
  const counterSnap = await tx.get(counterRef);
  const counter = counterSnap.exists ? counterSnap.data() : {};
  const assigned = Number(counter.assignedCount || 0);

  if (assigned >= FOUNDING_MAX) return null;

  const founderNumber = assigned + 1;

  tx.set(
    counterRef,
    {
      assignedCount: founderNumber,
      maxFounders: FOUNDING_MAX,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  tx.set(
    userRef,
    {
      founderCohort: "founding_100",
      founderNumber,
      founderFirstYearDiscountPercent: FOUNDER_DISCOUNT_PERCENT,
      founderEarlyFeatureAccess: true,
      founderAssignedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return founderNumber;
}

// Compatibility/readback callable.
// It deliberately does NOT trust the old client-written isEarlyUser flag.
exports.syncFounderEntitlement = onCall(async (request) => {
  const uid = requireUid(request);
  const userRef = db.collection(ACCESS).doc(uid);
  const snap = await userRef.get();

  if (!snap.exists) {
    return { founder: false };
  }

  const data = snap.data();

  if (
    data.founderCohort === "founding_100" &&
    Number.isInteger(data.founderNumber)
  ) {
    return {
      founder: true,
      founderNumber: data.founderNumber,
    };
  }

  return {
    founder: false,
    preservedExistingTrial:
      data.hasUsedTrial === true &&
      dateFromAny(data.trialStartAtIso || data.trialStartAt) !== null,
  };
});

exports.activatePremiumTrial = onCall(async (request) => {
  const uid = requireUid(request);
  const userRef = db.collection(ACCESS).doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};

    if (data.plan === "premium") {
      throw new HttpsError(
        "failed-precondition",
        "Premium is already active.",
      );
    }

    const existingStart = dateFromAny(data.trialStartAtIso || data.trialStartAt);
    const existingEnd = dateFromAny(data.trialEndsAtIso || data.trialEndsAt);

    // One account gets one trial. Never restart it and never use a
    // client-controlled field to grant Founder status.
    if (data.hasUsedTrial === true || existingStart || existingEnd) {
      return {
        activated: false,
        alreadyUsed: true,
        founder:
          data.founderCohort === "founding_100" &&
          Number.isInteger(data.founderNumber),
        founderNumber: Number.isInteger(data.founderNumber)
          ? data.founderNumber
          : null,
        trialStartAtIso: existingStart?.toISOString() || null,
        trialEndsAtIso: existingEnd?.toISOString() || null,
      };
    }

    // Only a fresh authenticated server-side activation can consume a
    // Founding 100 slot. Counter allocation is transactional.
    const founderNumber = await assignFounderIfAvailable(tx, userRef, data);
    const isFounder = founderNumber !== null;
    const trialDays = isFounder ? FOUNDER_TRIAL_DAYS : STANDARD_TRIAL_DAYS;

    const now = new Date();
    const ends = addDays(now, trialDays);

    tx.set(
      userRef,
      {
        ownerType: "user",
        ownerId: uid,
        authUid: uid,
        plan: "trial",
        hasUsedTrial: true,
        trialStartAtIso: now.toISOString(),
        trialEndsAtIso: ends.toISOString(),
        trialLengthDaysGranted: trialDays,
        trialGrantedBy: isFounder ? "founding_100" : "standard_21_day",
        entitlementAuthority: "cloud_function",
        updatedAtIso: now.toISOString(),
        lastSyncedAtIso: now.toISOString(),
      },
      { merge: true },
    );

    return {
      activated: true,
      founder: isFounder,
      founderNumber,
      trialDays,
      trialStartAtIso: now.toISOString(),
      trialEndsAtIso: ends.toISOString(),
    };
  });
});
