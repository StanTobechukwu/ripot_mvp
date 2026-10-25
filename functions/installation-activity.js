const { createHash } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { Timestamp, FieldValue } = require("firebase-admin/firestore");

const ACTIVITY = "ripot_installation_activity";
const HEARTBEAT_MS = 6 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
// These are public Firebase app identifiers, not credentials. Only Android is
// included in the first rollout; add other apps after testing their attestation.
const ANDROID_APP_ID = "1:802565511046:android:9a0015539a64e9aff57e07";

function validateActivity(request) {
  if (request.app?.appId !== ANDROID_APP_ID) {
    throw new HttpsError("failed-precondition", "Verified Ripot app required.");
  }
  const data = request.data;
  const fields = ["schemaVersion", "installationSecret", "platform", "appVersion", "buildNumber"];
  if (!data || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).length !== fields.length ||
      !fields.every((field) => Object.hasOwn(data, field)) ||
      data.schemaVersion !== 1 || data.platform !== "android" ||
      typeof data.installationSecret !== "string" || !/^[a-f0-9]{64}$/.test(data.installationSecret) ||
      typeof data.appVersion !== "string" || !/^[0-9][0-9A-Za-z.+_-]{0,39}$/.test(data.appVersion) ||
      typeof data.buildNumber !== "string" || !/^[0-9]{1,12}$/.test(data.buildNumber)) {
    throw new HttpsError("invalid-argument", "Unsupported activity record.");
  }
  // Never accept a UID, time, entitlement, or report content from the payload.
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  const registeredUid = request.auth?.uid && provider && provider !== "anonymous"
    ? request.auth.uid : null;
  return {
    documentId: createHash("sha256").update(data.installationSecret).digest("hex"),
    appId: request.app.appId,
    platform: data.platform,
    appVersion: data.appVersion,
    buildNumber: data.buildNumber,
    registeredUid,
  };
}

function createActivityService(db, clock = () => new Date()) {
  return async (request) => {
    const input = validateActivity(request);
    const now = clock();
    const nowMs = now.getTime();
    const day = now.toISOString().slice(0, 10);
    const ref = db.collection(ACTIVITY).doc(input.documentId);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const previous = snap.data();
      if (previous && (previous.appId !== input.appId || previous.platform !== input.platform)) {
        throw new HttpsError("failed-precondition", "Installation app mismatch.");
      }
      const authState = input.registeredUid ? "registered" : "guest";
      const lastSeenMs = previous?.lastSeenAt?.toMillis?.() || 0;
      const identityChanged = previous?.lastAuthState !== authState ||
        (input.registeredUid && input.registeredUid !== previous?.lastRegisteredUid);
      const versionChanged = previous?.appVersion !== input.appVersion ||
        previous?.buildNumber !== input.buildNumber;
      const newDay = previous?.lastSeenDay !== day;
      // Never move the clock backwards. Retry storms cause no extra writes.
      if (previous && (nowMs < lastSeenMs ||
          (!identityChanged && !versionChanged && !newDay && nowMs - lastSeenMs < HEARTBEAT_MS))) {
        return { recorded: false, nextHeartbeatSeconds: Math.max(60, Math.ceil((lastSeenMs + HEARTBEAT_MS - nowMs) / 1000)) };
      }
      const at = Timestamp.fromDate(now); // Trusted function clock, never client time.
      tx.set(ref, {
        schemaVersion: 1,
        appId: input.appId,
        platform: input.platform,
        appVersion: input.appVersion,
        buildNumber: input.buildNumber,
        ...(previous ? {} : { firstSeenAt: at, firstSeenDay: day, source: "app_check_callable_v1" }),
        lastSeenAt: at,
        lastSeenDay: day,
        // Number of UTC days on which this instance was observed, not sessions.
        observedDays: (previous?.observedDays || 0) + (newDay ? 1 : 0),
        lastAuthState: authState,
        everRegistered: previous?.everRegistered === true || !!input.registeredUid,
        ...(input.registeredUid ? {
          lastRegisteredUid: input.registeredUid,
          lastRegisteredSeenAt: at,
          ...(!previous?.everRegistered ? { firstRegisteredSeenAt: at } : {}),
        } : {}),
        committedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      return { recorded: true, nextHeartbeatSeconds: HEARTBEAT_MS / 1000 };
    });
  };
}

function summarizeActivity(rows, now = new Date()) {
  const millis = (value) => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : NaN);
  const valid = rows.filter((r) => r.schemaVersion === 1 &&
    Number.isFinite(millis(r.firstSeenAt)) && Number.isFinite(millis(r.lastSeenAt)) &&
    millis(r.lastSeenAt) >= millis(r.firstSeenAt) && millis(r.lastSeenAt) <= now.getTime());
  const first = valid.length ? Math.min(...valid.map((r) => millis(r.firstSeenAt))) : null;
  const latest = valid.length ? Math.max(...valid.map((r) => millis(r.lastSeenAt))) : null;
  const active = (days) => valid.filter((r) => millis(r.lastSeenAt) >= now.getTime() - days * DAY_MS);
  const split = (records) => ({
    observedInstallations: records.length,
    neverObservedSignedIn: records.filter((r) => !r.everRegistered).length,
    previouslySignedInNowGuest: records.filter((r) => r.everRegistered && r.lastAuthState === "guest").length,
    lastObservedSignedIn: records.filter((r) => r.lastAuthState === "registered").length,
  });
  const versions = {};
  for (const row of active(30)) {
    const version = `${row.platform} ${row.appVersion}+${row.buildNumber}`;
    versions[version] = (versions[version] || 0) + 1;
  }
  return {
    generatedAtIso: now.toISOString(),
    coverage: "Android installations with activity sharing enabled, running the reporting release with network access and valid App Check. Counts start at rollout.",
    firstObservationAtIso: first === null ? null : new Date(first).toISOString(),
    latestObservationAtIso: latest === null ? null : new Date(latest).toISOString(),
    hoursSinceLatestObservation: latest === null ? null : Math.round((now.getTime() - latest) / 360000) / 10,
    collectionStatus: latest === null ? "no_observations" : now.getTime() - latest > 2 * DAY_MS ? "no_observations_in_48_hours" : "recent_observations",
    excludedInvalidRecords: rows.length - valid.length,
    sinceRollout: split(valid),
    last24Hours: split(active(1)),
    last7Days: split(active(7)),
    last30Days: split(active(30)),
    activeVersionsLast30Days: versions,
    limitations: [
      "Installations are not people, registrations, or Google Play all-time installs. Reinstall/reset can create another installation.",
      "Never observed signed in does not prove the person has no account on another installation.",
      "No activity may mean inactivity, opt-out, offline use, old app versions, or reporting failure. Check function/App Check error metrics.",
      "Missing historical activity before rollout cannot be reconstructed from these records.",
    ],
  };
}

module.exports = { ACTIVITY, ANDROID_APP_ID, HEARTBEAT_MS, createActivityService, summarizeActivity };
