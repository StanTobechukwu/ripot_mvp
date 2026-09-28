const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { GoogleAuth } = require("google-auth-library");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { createHash } = require("node:crypto");

initializeApp();
const db = getFirestore();

// An operator creates preview/apply documents in the Firebase console. App
// clients cannot create or read these jobs. Never accept a project override.
const { runFounderAdminJob } = require('./founder-admin-job');
exports.founderMigrationJob = onDocumentCreated({
  document: 'ripot_internal_founder_jobs/{jobId}', region: 'us-central1',
  maxInstances: 1, timeoutSeconds: 120, memory: '256MiB',
}, async (event) => {
  if (process.env.GCLOUD_PROJECT !== 'ripot-4edf7') {
    throw new Error('Founder migration is restricted to the Ripot project.');
  }
  if (event.data) await runFounderAdminJob(event.data.ref, db, getAuth());
});

// Activity has its own attested endpoint and collection. It cannot grant access.
const { createActivityService } = require("./installation-activity");
exports.recordInstallationActivity = onCall({
  enforceAppCheck: true,
  maxInstances: 2,
  concurrency: 20,
  timeoutSeconds: 15,
  memory: "256MiB",
}, createActivityService(db));

const ACCESS = "ripot_user_access";
const {
  requireRegisteredUid, createFounderService, isFounder,
} = require("./founding-100");
const requireUid = requireRegisteredUid;
const founders = createFounderService(db);
// Free Founder access is independent of the optional paid Play offer.
const FOUNDER_ANNUAL_OFFER_ENABLED = false;
const FOUNDER_DISCOUNT_PERCENT = 25;

exports.syncFounderEntitlement = onCall(async (request) =>
  founders.sync(requireUid(request)));

exports.activatePremiumTrial = onCall(async (request) =>
  founders.activate(requireUid(request)));

// Google Play paid Premium verification.
const PLAY_PACKAGE_NAME = "com.nduaguba.report";
const PLAY_PREMIUM_PRODUCT_ID = "ripot_premium";
const PLAY_FOUNDER_OFFER_ID = "founding-100-annual-25";
const PLAY_INTERNAL_COLLECTION = "ripot_internal_play";
const PLAY_TOKEN_OWNERS_COLLECTION = "ripot_internal_play_tokens";
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

function purchaseTokenDocumentId(purchaseToken) {
  return createHash("sha256").update(purchaseToken).digest("hex");
}

async function claimPurchaseToken(uid, purchaseToken) {
  const tokenHash = purchaseTokenDocumentId(purchaseToken);
  const tokenRef = db.collection(PLAY_TOKEN_OWNERS_COLLECTION).doc(tokenHash);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(tokenRef);
    const ownerUid = snap.exists ? String(snap.data()?.ownerUid || "") : "";
    if (ownerUid && ownerUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "This Google Play purchase is already linked to another Ripot account.",
      );
    }
    tx.set(
      tokenRef,
      {
        ownerUid: uid,
        provider: "google_play",
        productId: PLAY_PREMIUM_PRODUCT_ID,
        tokenHash,
        firstLinkedAt: snap.exists
          ? snap.data()?.firstLinkedAt || FieldValue.serverTimestamp()
          : FieldValue.serverTimestamp(),
        lastVerifiedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  return tokenHash;
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

  // A Play token can belong to only one Ripot account, including when Google
  // omits externalAccountIdentifiers for an older purchase.
  const purchaseTokenHash = await claimPurchaseToken(uid, purchaseToken);

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
    // Restoring the same verified purchase is not a second redemption.
    const previous = (await internalRef.get()).data();
    const restoring = previous?.purchaseTokenHash === purchaseTokenHash &&
      previous?.offerId === PLAY_FOUNDER_OFFER_ID;
    const eligible = restoring || (FOUNDER_ANNUAL_OFFER_ENABLED &&
      isFounder(current) && current.founderDiscountRedeemed !== true);
    if (!eligible) throw new HttpsError("failed-precondition", "The Founding 100 annual offer is not available for this account.");
  }

  await acknowledgeIfNeeded(playData, purchaseToken);
  await Promise.all([
    internalRef.set({ uid, provider:"google_play", productId:PLAY_PREMIUM_PRODUCT_ID, purchaseToken, purchaseTokenHash,
      latestOrderId:e.latestOrderId, basePlanId:e.basePlanId, offerId:e.offerId, lastVerifiedAtIso:nowIso }, { merge:true }),
    accessRef.set({
      ownerType:"user", ownerId:uid, authUid:uid, plan:"premium",
      premiumStartedAtIso:current.premiumStartedAtIso || playData?.startTime || nowIso,
      billingProvider:"google_play", billingProductId:PLAY_PREMIUM_PRODUCT_ID,
      billingBasePlanId:e.basePlanId, billingOfferId:e.offerId, billingSubscriptionState:e.state,
      billingLatestOrderId:e.latestOrderId, playEntitlementExpiresAtIso:e.expiry?.toISOString() || null,
      billingLastVerifiedAtIso:nowIso, entitlementAuthority:"google_play_verified",
      ...(isFounderOffer ? { founderDiscountRedeemed:true, founderDiscountRedeemedAtIso:current.founderDiscountRedeemedAtIso || nowIso } : {}),
      updatedAtIso:nowIso, lastSyncedAtIso:nowIso,
    }, { merge:true }),
  ]);
  return e;
}

exports.getBillingEligibility = onCall(async (request) => {
  const uid = requireUid(request);
  const snap = await db.collection(ACCESS).doc(uid).get();
  const data = snap.exists ? snap.data() : {};
  const founder = isFounder(data);
  return { founder, founderNumber:founder ? data.founderNumber : null,
    founderDiscountEligible: FOUNDER_ANNUAL_OFFER_ENABLED && founder && data.founderDiscountRedeemed !== true,
    founderDiscountPercent: FOUNDER_ANNUAL_OFFER_ENABLED && founder ? FOUNDER_DISCOUNT_PERCENT : 0 };
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
