const { createHash } = require("node:crypto");
const { FieldValue } = require("firebase-admin/firestore");
const {
  ACCESS, COHORT, MAX_FOUNDERS, FOUNDER_DAYS, DAY_MS, REGISTRY_VERSION,
  registryRef, founderFields, validateRegistry, dateFromAny, isFounder,
} = require("./founding-100");

function auditAccounts(registeredUids, rows) {
  const registered = new Set(registeredUids);
  const accounts = rows.filter((row) => registered.has(row.uid));
  const installations = rows.filter((row) => row.uid.startsWith("usr_") && !registered.has(row.uid));
  const linked = new Set(accounts.flatMap(({ data }) => [
    data.installationId, data.lastSeenInstallationId, data.migratedFromInstallationId,
    data.legacyInstallationIdObserved,
  ]).filter(Boolean));
  const unlinked = installations.filter((row) => !linked.has(row.uid));
  return {
    registeredAccounts: registered.size,
    registeredAccountsWithAccessDocument: accounts.length,
    registeredAccountsWithoutAccessDocument: registered.size - accounts.length,
    accessDocuments: rows.length,
    historicalInstallationRecords: installations.length,
    installationRecordsLinkedToRegisteredAccounts: installations.length - unlinked.length,
    installationRecordsWithoutKnownAccountLink: unlinked.length,
    otherUnmatchedAccessDocuments: rows.length - accounts.length - installations.length,
    uniqueUnregisteredPeople: null,
    currentlyActiveUnregisteredPeople: null,
    note: "Installation records may include reinstalls and testing. They are not a count of people or current guest activity.",
  };
}

function buildMigrationPlan({ registeredUids, rows, members, counter, includeLegacy }) {
  const registered = new Set(registeredUids);
  const ledger = new Map(members.map((member) => [member.uid, member]));
  if (ledger.size !== members.length) throw new Error("Duplicate member UIDs; review the registry manually.");
  const formal = rows.filter(({ data }) => data.founderCohort === COHORT || data.founderNumber != null);
  for (const { uid, data } of formal) {
    if (!isFounder(data)) throw new Error("Invalid existing Founder number; review the registry manually.");
    const existing = ledger.get(uid);
    if (existing && existing.founderNumber !== data.founderNumber) {
      throw new Error("Account and permanent Founder numbers disagree.");
    }
    if (!existing) ledger.set(uid, {
      uid, founderNumber: data.founderNumber, source: "existing_server_founder",
      trialStartAtIso: dateFromAny(data.trialStartAtIso || data.trialStartAt)?.toISOString() || null,
      trialEndsAtIso: dateFromAny(data.trialEndsAtIso || data.trialEndsAt)?.toISOString() || null,
    });
  }
  const existing = [...ledger.values()];
  validateRegistry({ schemaVersion: REGISTRY_VERSION, assignedCount: existing.length }, existing);
  if (counter && counter.assignedCount !== existing.length) {
    throw new Error("Counter differs from existing Founder records. Do not reset or reuse missing slots.");
  }
  if (counter?.schemaVersion === REGISTRY_VERSION) validateRegistry(counter, members);

  const candidates = includeLegacy ? rows.filter(({ uid, data }) => {
    const start = dateFromAny(data.trialStartAtIso || data.trialStartAt);
    const end = dateFromAny(data.trialEndsAtIso || data.trialEndsAt);
    return registered.has(uid) && !ledger.has(uid) && data.ownerType === "user" &&
      data.ownerId === uid && data.authUid === uid && data.hasUsedTrial === true &&
      start && end && end.getTime() - start.getTime() === FOUNDER_DAYS * DAY_MS;
  }).map(({ uid, data }) => ({
    uid,
    trialStartAtIso: dateFromAny(data.trialStartAtIso || data.trialStartAt).toISOString(),
    trialEndsAtIso: dateFromAny(data.trialEndsAtIso || data.trialEndsAt).toISOString(),
    source: "reviewed_legacy_84_day_trial",
  })).sort((a, b) => a.trialStartAtIso.localeCompare(b.trialStartAtIso) || a.uid.localeCompare(b.uid)) : [];
  if (existing.length + candidates.length > MAX_FOUNDERS) {
    throw new Error("Legacy candidates exceed remaining slots; review the cohort manually.");
  }
  for (const candidate of candidates) {
    ledger.set(candidate.uid, { ...candidate, founderNumber: ledger.size + 1 });
  }
  const planned = [...ledger.values()].sort((a, b) => a.founderNumber - b.founderNumber);
  // Only stable, relevant data enters the review hash. Last-seen updates do not
  // invalidate a review, but a changed trial, number, or account set does.
  const review = {
    registeredUids: [...registered].sort(), includeLegacy,
    counter: counter ? { assignedCount: counter.assignedCount, schemaVersion: counter.schemaVersion || null } : null,
    existingMemberUids: members.map((m) => m.uid).sort(),
    founders: planned.map(({ uid, founderNumber, trialStartAtIso, trialEndsAtIso, source }) =>
      ({ uid, founderNumber, trialStartAtIso, trialEndsAtIso, source })),
  };
  return {
    ...auditAccounts(registeredUids, rows),
    existingFounderCount: existing.length,
    legacyCandidatesToAdd: candidates.length,
    assignedAfterMigration: planned.length,
    remainingSlots: MAX_FOUNDERS - planned.length,
    founders: review.founders,
    reviewHash: createHash("sha256").update(JSON.stringify(review)).digest("hex"),
  };
}

async function migrateFounders(db, { registeredUids, includeLegacy = false, apply = false, expectedHash }) {
  const registry = registryRef(db);
  return db.runTransaction(async (tx) => {
    const counterSnap = await tx.get(registry);
    const memberSnaps = await tx.get(registry.collection("members"));
    const accessSnaps = await tx.get(db.collection(ACCESS));
    const rows = accessSnaps.docs.map((doc) => ({ uid: doc.id, data: doc.data() }));
    const members = memberSnaps.docs.map((doc) => ({ ...doc.data(), uid: doc.id }));
    const plan = buildMigrationPlan({
      registeredUids, rows, members, counter: counterSnap.data(), includeLegacy,
    });
    if (!apply) return { ...plan, applied: false };
    if (!expectedHash || expectedHash !== plan.reviewHash) {
      throw new Error("Review hash changed or is missing. Run a fresh dry run and review it before applying.");
    }
    const existingUids = new Set(members.map((m) => m.uid));
    const accessUids = new Set(rows.map((row) => row.uid));
    for (const member of plan.founders) {
      if (!existingUids.has(member.uid)) tx.create(registry.collection("members").doc(member.uid), {
        ...member, assignedAt: FieldValue.serverTimestamp(),
      });
      if (accessUids.has(member.uid)) tx.set(db.collection(ACCESS).doc(member.uid), {
        ...founderFields(member.founderNumber),
        founderRegistryVersion: REGISTRY_VERSION,
      }, { merge: true });
    }
    tx.set(registry, {
      schemaVersion: REGISTRY_VERSION, assignedCount: plan.assignedAfterMigration,
      maxFounders: MAX_FOUNDERS, updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ...plan, applied: true };
  });
}

module.exports = { auditAccounts, buildMigrationPlan, migrateFounders };
