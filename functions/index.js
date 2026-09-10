const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { GoogleAuth } = require("google-auth-library");
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

// Google Play paid Premium verification.
const PLAY_PACKAGE_NAME = "com.nduaguba.report";
const PLAY_PREMIUM_PRODUCT_ID = "ripot_premium";
const PLAY_FOUNDER_OFFER_ID = "founding-100-annual-25";
const PLAY_INTERNAL_COLLECTION = "ripot_internal_play";
const playAuth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/androidpublisher"] });

async function playAccessToken() {
  const client = await playAuth.getClient();
  const r = await client.getAccessToken();
  const token = typeof r === "string" ? r : r?.token;
  if (!token) throw new HttpsError("unavailable", "Google Play verification credentials are unavailable.");
  return token;
}

async function playJson(url, options = {}) {
  const token = await playAccessToken();
  const response = await fetch(url, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json", "Content-Type": "application/json", ...(options.headers || {}) },
  });
  const text = await response.text();
  let body = null;
  if (text) { try { body = JSON.parse(text); } catch (_) { body = { raw: text }; } }
  if (!response.ok) {
    console.error("Google Play API error", response.status, body);
    throw new HttpsError(response.status === 404 ? "not-found" : "unavailable", "Google Play could not verify this subscription.");
  }
  return body;
}

async function getPlaySubscription(purchaseToken) {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(PLAY_PACKAGE_NAME)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  return playJson(url);
}

function premiumLineItems(playData) {
  const items = Array.isArray(playData?.lineItems) ? playData.lineItems : [];
  return items.filter((item) => item?.productId === PLAY_PREMIUM_PRODUCT_ID);
}

function latestPremiumLineItem(playData) {
  const candidates = premiumLineItems(playData)
    .map((item) => ({ item, expiry: item?.expiryTime ? new Date(item.expiryTime) : null }))
    .filter((x) => x.expiry && !Number.isNaN(x.expiry.getTime()))
    .sort((a,b) => b.expiry.getTime() - a.expiry.getTime());
  return candidates[0] || null;
}

function playEntitlement(playData) {
  const latest = latestPremiumLineItem(playData);
  if (!latest) return { entitled:false, expiry:null, state:String(playData?.subscriptionState || ""), basePlanId:null, offerId:null, latestOrderId:null };
  const state = String(playData?.subscriptionState || "");
  const allowed = state === "SUBSCRIPTION_STATE_ACTIVE" || state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" || state === "SUBSCRIPTION_STATE_CANCELED";
  const entitled = allowed && latest.expiry.getTime() > Date.now();
  return {
    entitled,
    expiry: latest.expiry,
    state,
    basePlanId: latest.item?.offerDetails?.basePlanId || null,
    offerId: latest.item?.offerDetails?.offerId || null,
    latestOrderId: latest.item?.latestSuccessfulOrderId || playData?.latestOrderId || null,
  };
}

function assertPlayAccountMatches(uid, playData) {
  const external = playData?.externalAccountIdentifiers?.obfuscatedExternalAccountId;
  if (external && external !== uid) throw new HttpsError("permission-denied", "This Google Play purchase belongs to a different Ripot account.");
}

async function acknowledgeIfNeeded(playData, purchaseToken) {
  if (playData?.acknowledgementState !== "ACKNOWLEDGEMENT_STATE_PENDING") return;
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(PLAY_PACKAGE_NAME)}/purchases/subscriptions/${encodeURIComponent(PLAY_PREMIUM_PRODUCT_ID)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  await playJson(url, { method:"POST", body:JSON.stringify({}) });
}

async function applyVerifiedPlayEntitlement(uid, purchaseToken, playData) {
  const accessRef = db.collection(ACCESS).doc(uid);
  const internalRef = db.collection(PLAY_INTERNAL_COLLECTION).doc(uid);
  const accessSnap = await accessRef.get();
  const current = accessSnap.exists ? accessSnap.data() : {};
  const e = playEntitlement(playData);
  const nowIso = new Date().toISOString();

  if (!e.entitled) {
    if (current.entitlementAuthority === "google_play_verified") {
      await accessRef.set({
        plan:"free", billingProvider:"google_play", billingProductId:PLAY_PREMIUM_PRODUCT_ID,
        billingSubscriptionState:e.state, billingBasePlanId:e.basePlanId, billingOfferId:e.offerId,
        playEntitlementExpiresAtIso:e.expiry?.toISOString() || null,
        billingLastVerifiedAtIso:nowIso, entitlementAuthority:"google_play_verified", updatedAtIso:nowIso,
      }, { merge:true });
    }
    return e;
  }

  const isFounderOffer = e.offerId === PLAY_FOUNDER_OFFER_ID;
  if (isFounderOffer) {
    const eligible = current.founderCohort === "founding_100" && Number.isInteger(current.founderNumber) && current.founderDiscountRedeemed !== true;
    if (!eligible) throw new HttpsError("failed-precondition", "The Founding 100 annual offer is not available for this account.");
  }

  await acknowledgeIfNeeded(playData, purchaseToken);
  await Promise.all([
    internalRef.set({ uid, provider:"google_play", productId:PLAY_PREMIUM_PRODUCT_ID, purchaseToken,
      latestOrderId:e.latestOrderId, basePlanId:e.basePlanId, offerId:e.offerId, lastVerifiedAtIso:nowIso }, { merge:true }),
    accessRef.set({
      ownerType:"user", ownerId:uid, authUid:uid, plan:"premium",
      premiumStartedAtIso:current.premiumStartedAtIso || playData?.startTime || nowIso,
      billingProvider:"google_play", billingProductId:PLAY_PREMIUM_PRODUCT_ID,
      billingBasePlanId:e.basePlanId, billingOfferId:e.offerId, billingSubscriptionState:e.state,
      billingLatestOrderId:e.latestOrderId, playEntitlementExpiresAtIso:e.expiry?.toISOString() || null,
      billingLastVerifiedAtIso:nowIso, entitlementAuthority:"google_play_verified",
      ...(isFounderOffer ? { founderDiscountRedeemed:true, founderDiscountRedeemedAtIso:nowIso } : {}),
      updatedAtIso:nowIso, lastSyncedAtIso:nowIso,
    }, { merge:true }),
  ]);
  return e;
}

exports.getBillingEligibility = onCall(async (request) => {
  const uid = requireUid(request);
  const snap = await db.collection(ACCESS).doc(uid).get();
  const data = snap.exists ? snap.data() : {};
  const founder = data.founderCohort === "founding_100" && Number.isInteger(data.founderNumber);
  return { founder, founderNumber:founder ? data.founderNumber : null,
    founderDiscountEligible: founder && data.founderDiscountRedeemed !== true,
    founderDiscountPercent: founder ? FOUNDER_DISCOUNT_PERCENT : 0 };
});

exports.verifyGooglePlaySubscription = onCall(async (request) => {
  const uid = requireUid(request);
  const purchaseToken = String(request.data?.purchaseToken || "").trim();
  const productId = String(request.data?.productId || "").trim();
  if (!purchaseToken || purchaseToken.length < 20) throw new HttpsError("invalid-argument", "A valid purchase token is required.");
  if (productId !== PLAY_PREMIUM_PRODUCT_ID) throw new HttpsError("invalid-argument", "Unknown Premium product.");
  const playData = await getPlaySubscription(purchaseToken);
  assertPlayAccountMatches(uid, playData);
  if (!premiumLineItems(playData).length) throw new HttpsError("failed-precondition", "This is not a Ripot Premium purchase.");
  const e = await applyVerifiedPlayEntitlement(uid, purchaseToken, playData);
  return { entitled:e.entitled, subscriptionState:e.state, basePlanId:e.basePlanId, offerId:e.offerId,
    expiresAtIso:e.expiry?.toISOString() || null };
});

exports.refreshPlayEntitlement = onCall(async (request) => {
  const uid = requireUid(request);
  const snap = await db.collection(PLAY_INTERNAL_COLLECTION).doc(uid).get();
  if (!snap.exists) return { checked:false, entitled:false, reason:"no_play_purchase" };
  const purchaseToken = String(snap.data()?.purchaseToken || "").trim();
  if (!purchaseToken) return { checked:false, entitled:false, reason:"no_play_purchase" };
  const playData = await getPlaySubscription(purchaseToken);
  assertPlayAccountMatches(uid, playData);
  const e = await applyVerifiedPlayEntitlement(uid, purchaseToken, playData);
  return { checked:true, entitled:e.entitled, subscriptionState:e.state, basePlanId:e.basePlanId,
    offerId:e.offerId, expiresAtIso:e.expiry?.toISOString() || null };
});

