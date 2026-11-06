const {isRankingActive, changedSettings} = require("./community-schedule");
const {notificationMode, shouldNotify, pushPayload} = require("./push-policy");
const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten, onDocumentWrittenWithAuthContext} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const functionsV1 = require("firebase-functions/v1");
const nodemailer = require("nodemailer");

admin.initializeApp();

const db = admin.firestore();
const invitationHandlers = require("./community-invitations").createInvitationHandlers(db, HttpsError);
exports.getCommunityInvitationCode = onCall({region: "europe-west1"}, invitationHandlers.getCommunityInvitationCode);
exports.resolveCommunityInvitationCode = onCall({region: "europe-west1"}, invitationHandlers.resolveCommunityInvitationCode);
const contactHandlers = require("./contact-discovery").createContactHandlers(db, admin.auth(), HttpsError);
for (const [name, handler] of Object.entries(contactHandlers)) {
  exports[name] = onCall({region: "europe-west1", enforceAppCheck: true}, handler);
}
const settingsHandlers = require("./community-settings").createSettingsHandlers({db, admin, HttpsError});
for (const [name, handler] of Object.entries(settingsHandlers)) {
  exports[name] = onCall({region: "europe-west1"}, handler);
}
const storage = admin.storage();
const IOS_BUNDLE_ID = process.env.IOS_BUNDLE_ID || "com.torpille.ios";
const REPORT_OWNER_EMAIL = process.env.REPORT_OWNER_EMAIL || process.env.APP_OWNER_EMAIL || "torpille.app@gmail.com";
const SMTP_PASSWORD = defineSecret("SMTP_PASS");
const CONTENT_RETENTION_DAYS = 14;
const OBJECTIONABLE_TERMS = [
  "porn",
  "porno",
  "xxx",
  "nude",
  "nudes",
  "sexe",
  "suicide",
  "kill yourself",
  "va te tuer",
  "pute",
  "connard",
  "salope",
];

// Keeps a private reverse index so a blocked user can hide the blocker without
// being allowed to read the blocker's private blockedUsers collection.
exports.syncBlockedRelationship = onDocumentWritten(
    {
      document: "users/{blockerUid}/blockedUsers/{blockedUid}",
      region: "europe-west1",
    },
    async (event) => {
      const {blockerUid, blockedUid} = event.params;
      const reverseRef = db.collection("users").doc(blockedUid)
          .collection("blockedBy").doc(blockerUid);

      if (event.data.after.exists) {
        await reverseRef.set({blockerUid, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
      } else {
        await reverseRef.delete();
      }
    },
);

// Backfills blocks created before the reverse-index trigger was deployed.
exports.syncBlockedByForMe = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const uid = request.auth.uid;
  const blockerUids = new Set();

  try {
    const snapshot = await db.collectionGroup("blockedUsers")
        .where("blockedUid", "==", uid)
        .get();
    snapshot.docs.forEach((document) => {
      const blockerUid = document.ref.parent.parent?.id;
      if (blockerUid && blockerUid !== uid) blockerUids.add(blockerUid);
    });
  } catch (error) {
    // A newly-created collection-group index can take several minutes to become
    // ready. Fall back to direct document reads so privacy never waits for it.
    if (error.code !== 9) throw error;
    const userRefs = await db.collection("users").listDocuments();
    const candidateRefs = userRefs
        .filter((userRef) => userRef.id !== uid)
        .map((userRef) => userRef.collection("blockedUsers").doc(uid));
    if (candidateRefs.length > 0) {
      const snapshots = await db.getAll(...candidateRefs);
      snapshots.forEach((document) => {
        if (document.exists) {
          const blockerUid = document.ref.parent.parent?.id;
          if (blockerUid) blockerUids.add(blockerUid);
        }
      });
    }
  }

  const batch = db.batch();
  blockerUids.forEach((blockerUid) => {
    batch.set(
        db.collection("users").doc(uid).collection("blockedBy").doc(blockerUid),
        {blockerUid, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true},
    );
  });

  const existingReverse = await db.collection("users").doc(uid).collection("blockedBy").get();
  existingReverse.docs.forEach((document) => {
    if (!blockerUids.has(document.id)) batch.delete(document.ref);
  });

  await batch.commit();
  return {count: blockerUids.size};
});

// Guarantees that every torpille has a visible entry in the community thread,
// including sends made by an older client that omitted the message write.
exports.syncTorpilleToDiscussion = onDocumentCreated(
    {
      document: "communities/{communityId}/torpilles/{torpilleId}",
      region: "europe-west1",
    },
    async (event) => {
      const torpille = event.data && event.data.data();
      if (!torpille) return;

  const {communityId, torpilleId} = event.params;
  const messages = db.collection("communities").doc(communityId).collection("messages");
  if (torpille.fromUid) {
    await db.collection("communities").doc(communityId)
        .collection("members").doc(torpille.fromUid)
        .set({lastTorpilleSentAt: torpille.createdAt || admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  }
  const existing = await messages.where("torpilleId", "==", torpilleId).limit(1).get();
      if (!existing.empty) return;

      const payload = {
        id: torpilleId,
        type: "video",
        senderUid: torpille.fromUid || "",
        senderPseudo: torpille.fromPseudo || "",
        taggedUid: torpille.toUid || "",
        taggedPseudo: torpille.taggedPseudo || "",
        torpilleId,
        videoBucket: torpille.videoBucket || null,
        videoPath: torpille.videoPath || null,
        tagX: typeof torpille.tagX === "number" ? torpille.tagX : 0.5,
        tagY: typeof torpille.tagY === "number" ? torpille.tagY : 0.2,
        createdAt: torpille.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        moderationStatus: "visible",
        reportCount: 0,
      };
      if (torpille.videoUrl) payload.videoUrl = torpille.videoUrl;

      await messages.doc(torpilleId).set(payload, {merge: true});
    },
);

exports.createVideoTorpille = onCall({region: "europe-west1"}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }

  const uid = request.auth.uid;
  const data = request.data || {};
  const communityId = String(data.communityId || "").trim();
  const taggedUid = String(data.taggedUid || "").trim();
  const senderPseudo = String(data.senderPseudo || "").trim();
  const taggedPseudo = String(data.taggedPseudo || "").trim();
  const videoBucket = String(data.videoBucket || "").trim();
  const videoPath = String(data.videoPath || "").trim();
  const videoUrl = String(data.videoUrl || "").trim();

  if (!communityId || !taggedUid || !senderPseudo || !taggedPseudo || !videoPath || taggedUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid torpille data.");
  }

  if (!videoPath.startsWith(`communities/${communityId}/videos/`)) {
    throw new HttpsError("invalid-argument", "Vidéo extérieure à la communauté.");
  }
  if (data.respondingTo) {
    const bucket = admin.storage().bucket();
    if (videoBucket && videoBucket !== bucket.name) throw new HttpsError("invalid-argument", "Stockage vidéo invalide.");
    const [exists] = await bucket.file(videoPath).exists();
    if (!exists) throw new HttpsError("failed-precondition", "Attends la fin de l’envoi de la vidéo.");
  }
  const communityRef = db.collection("communities").doc(communityId);
  const senderMemberRef = communityRef.collection("members").doc(uid);
  const targetMemberRef = communityRef.collection("members").doc(taggedUid);
  const targetBlockedSenderRef = db.collection("users").doc(taggedUid)
      .collection("blockedUsers").doc(uid);
  const senderBlockedTargetRef = db.collection("users").doc(uid)
      .collection("blockedUsers").doc(taggedUid);
  const torpilleRef = communityRef.collection("torpilles").doc();
  return db.runTransaction(async (batch) => {
  const [communitySnapshot, senderSnapshot, targetSnapshot,
    targetBlockedSenderSnapshot, senderBlockedTargetSnapshot] = await Promise.all([
    batch.get(communityRef), batch.get(senderMemberRef), batch.get(targetMemberRef),
    batch.get(targetBlockedSenderRef), batch.get(senderBlockedTargetRef),
  ]);

  if (!communitySnapshot.exists || !senderSnapshot.exists || !targetSnapshot.exists) {
    throw new HttpsError("permission-denied", "Both users must belong to the community.");
  }
  if (targetBlockedSenderSnapshot.exists || senderBlockedTargetSnapshot.exists) {
    throw new HttpsError("permission-denied", "This recipient is not available.");
  }

  const responseTimeSeconds = Number(communitySnapshot.data().responseTimeSeconds || 3600);
  const createdAt = admin.firestore.Timestamp.now();
  const deadlineAt = admin.firestore.Timestamp.fromMillis(
      createdAt.toMillis() + Math.max(1, responseTimeSeconds) * 1000,
  );
  const messageRef = communityRef.collection("messages").doc(torpilleRef.id);
  const tagX = typeof data.tagX === "number" ? data.tagX : 0.5;
  const tagY = typeof data.tagY === "number" ? data.tagY : 0.2;

  const media = {videoBucket: videoBucket || null, videoPath};
  if (videoUrl) media.videoUrl = videoUrl;
  const replyingTo = typeof data.respondingTo === "string" ? data.respondingTo : "";
  const rankingActive = isRankingActive(communitySnapshot.data().rankingSchedule, createdAt.toDate());
  if (!rankingActive && !replyingTo) throw new HttpsError("failed-precondition", "Les torpilles sont fermées à cet horaire. Tu peux seulement répondre à une torpille reçue.");
  let recoveryXp = 0;
  let previousRef = null;
  if (replyingTo) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(replyingTo)) throw new HttpsError("invalid-argument", "Torpille invalide.");
    previousRef = communityRef.collection("torpilles").doc(replyingTo);
    const previous = await batch.get(previousRef);
    if (!previous.exists || previous.data().toUid !== uid || previous.data().responded === true || previous.data().responseRequired === false) {
      throw new HttpsError("failed-precondition", "Cette torpille ne peut plus recevoir de réponse.");
    }
    if (previous.data().targetMembershipCreatedAt && !senderSnapshot.createTime.isEqual(previous.data().targetMembershipCreatedAt)) {
      throw new HttpsError("failed-precondition", "Cette torpille appartient à une ancienne adhésion.");
    }
    const late = previous.data().deadlineAt.toMillis() <= createdAt.toMillis();
    if (rankingActive && late && previous.data().eliminationMode === true && communitySnapshot.data().eliminationMode === true) {
      throw new HttpsError("deadline-exceeded", "Délai dépassé : tu vas être expulsé de cette communauté.");
    }
    recoveryXp = rankingActive && late ? 5 : 0;
  } else if (communitySnapshot.data().eliminationMode === true && senderSnapshot.data().pendingTorpilleId) {
    throw new HttpsError("failed-precondition", "Réponds à ta torpille en cours avant d’en envoyer une autre.");
  }
  const eliminationMode = rankingActive && communitySnapshot.data().eliminationMode === true;
  if (previousRef) {
    batch.update(previousRef, {responded: true, respondedAt: createdAt, nextToUid: taggedUid});
    batch.update(senderMemberRef, {
      ...(senderSnapshot.data().pendingTorpilleId === replyingTo ? {
        pendingTorpilleId: admin.firestore.FieldValue.delete(),
        pendingDeadlineAt: admin.firestore.FieldValue.delete(), pendingFromPseudo: admin.firestore.FieldValue.delete(),
      } : {}), lastRespondedAt: createdAt});
  }
  if (eliminationMode) batch.set(db.collection("communityEliminationQueue").doc(torpilleRef.id), {
    communityId, torpilleId: torpilleRef.id, deadlineAt,
  });
  batch.set(torpilleRef, {
    id: torpilleRef.id, fromUid: uid, fromPseudo: senderPseudo, toUid: taggedUid,
    communityId, ...media, taggedPseudo, tagX, tagY, createdAt, deadlineAt,
    eliminationMode, targetMembershipCreatedAt: targetSnapshot.createTime,
    responseRequired: rankingActive, responded: !rankingActive, isPublished: false, moderationStatus: "visible", reportCount: 0,
  });
  batch.set(messageRef, {
    id: torpilleRef.id, type: "video", senderUid: uid, senderPseudo,
    ...media, taggedUid, taggedPseudo, tagX, tagY, torpilleId: torpilleRef.id,
    responseRequired: rankingActive,
    createdAt, moderationStatus: "visible", reportCount: 0,
  });
  if (rankingActive) batch.set(targetMemberRef, {
    pendingTorpilleId: torpilleRef.id, pendingDeadlineAt: deadlineAt,
    pendingFromPseudo: senderPseudo, lastTorpilledAt: createdAt,
  }, {merge: true});
  batch.set(senderMemberRef, {
    uid, pseudo: senderPseudo, lastTorpilleSentAt: createdAt,
    ...(rankingActive ? {xpInCommunity: admin.firestore.FieldValue.increment(20 + recoveryXp)} : {}),
  }, {merge: true});
  return {torpilleId: torpilleRef.id, messageId: messageRef.id};
  });
});

function asInt64(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  return 0;
}

function normalizeModerationText(value) {
  return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/0/g, "o")
      .replace(/1/g, "i")
      .replace(/3/g, "e")
      .replace(/4/g, "a")
      .replace(/5/g, "s")
      .replace(/7/g, "t");
}

function containsObjectionableText(value) {
  const normalized = normalizeModerationText(value);
  const compact = normalized.replace(/[^a-z]/g, "");
  return OBJECTIONABLE_TERMS.some((term) => {
    const normalizedTerm = normalizeModerationText(term);
    const compactTerm = normalizedTerm.replace(/[^a-z]/g, "");
    return normalized.includes(normalizedTerm) || compact.includes(compactTerm);
  });
}

function moderationTextFromFields(data, fields) {
  return fields
      .map((field) => typeof data[field] === "string" ? data[field] : "")
      .filter(Boolean)
      .join(" ");
}

async function quarantineForContentFilter(documentRef, data, fields) {
  const moderationText = moderationTextFromFields(data || {}, fields);
  const matched = containsObjectionableText(moderationText);
  const latestSnapshot = await documentRef.get();
  const latestStatus = latestSnapshot.exists ? latestSnapshot.data()?.moderationStatus : null;
  const payload = {
    contentFilterMatched: matched,
    moderationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!["quarantined", "removed"].includes(latestStatus)) {
    payload.moderationStatus = "visible";
  }

  // A lexical match alone is never enough to quarantine content. It only
  // records a signal that can be combined with an actual user report.
  await documentRef.set(payload, {merge: true});
  return false;
}

function parseStorageLocation(rawUrl) {
  if (!rawUrl || typeof rawUrl !== "string") {
    return null;
  }

  if (rawUrl.startsWith("gs://")) {
    const withoutPrefix = rawUrl.slice(5);
    const slashIndex = withoutPrefix.indexOf("/");
    if (slashIndex <= 0) {
      return null;
    }
    return {
      bucket: withoutPrefix.slice(0, slashIndex),
      path: withoutPrefix.slice(slashIndex + 1),
    };
  }

  try {
    const parsed = new URL(rawUrl);
    const bucketMatch = parsed.pathname.match(/\/b\/([^/]+)\/o\/(.+)$/);
    if (!bucketMatch) {
      return null;
    }
    return {
      bucket: decodeURIComponent(bucketMatch[1]),
      path: decodeURIComponent(bucketMatch[2]),
    };
  } catch (error) {
    return null;
  }
}

async function deleteFileFromUrl(rawUrl) {
  const location = parseStorageLocation(rawUrl);
  if (!location || !location.path) {
    return;
  }

  await storage.bucket(location.bucket).file(location.path).delete({
    ignoreNotFound: true,
  });
}

async function deleteProfileImagesForUser(uid, photoUrl) {
  const bucketNames = new Set([storage.bucket().name]);
  const currentLocation = parseStorageLocation(photoUrl);
  if (currentLocation && currentLocation.bucket) {
    bucketNames.add(currentLocation.bucket);
  }

  const prefix = `users/${uid}/profile/`;
  await Promise.all([...bucketNames].map((bucketName) =>
    storage.bucket(bucketName).deleteFiles({prefix, force: true}),
  ));
}

// Safety net for accounts removed outside deleteMyAccount (Firebase console,
// another trusted backend, or a legacy client). Auth lifecycle triggers are
// currently first-generation functions, which can coexist with v2 functions.
exports.cleanupProfileImagesOnAuthDelete = functionsV1
    .region("europe-west1")
    .auth.user()
    .onDelete(async (user) => {
      const userRef = db.collection("users").doc(user.uid);
      await db.collection("contactDiscovery").doc(user.uid).delete();
      await db.collection("contactDiscoveryLimits").doc(user.uid).delete();
      const snapshot = await userRef.get();
      const photoUrl = snapshot.exists && typeof snapshot.data().photoUrl === "string" ?
        snapshot.data().photoUrl : "";
      await deleteProfileImagesForUser(user.uid, photoUrl);
      if (snapshot.exists) {
        await db.recursiveDelete(userRef);
      }
    });

function normalizedEmail(rawEmail) {
  return typeof rawEmail === "string" ? rawEmail.trim().toLowerCase() : "";
}

// A recreated Firebase Auth account receives a new UID. Remove only stale
// Firestore profiles for the same email whose former Auth account no longer
// exists; an active account is never deleted by this reconciliation.
exports.reconcileUserEmailOnAuthCreate = functionsV1
    .region("europe-west1")
    .auth.user()
    .onCreate(async (user) => {
      const email = normalizedEmail(user.email);
      if (!email) return;

      const legacyMatches = await db.collection("users").where("email", "==", user.email).get();
      const candidates = new Map();
      legacyMatches.docs.forEach((document) => {
        if (document.id !== user.uid) candidates.set(document.id, document.ref);
      });

      for (const [oldUid, reference] of candidates) {
        const oldAuthUser = await getAuthUserIfExists(oldUid);
        if (oldAuthUser) {
          console.error("Duplicate active Auth email detected; preserving both profiles", {
            email,
            newUid: user.uid,
            oldUid,
          });
          continue;
        }
        const snapshot = await reference.get();
        const photoUrl = snapshot.exists && typeof snapshot.data().photoUrl === "string" ?
          snapshot.data().photoUrl : "";
        await deleteProfileImagesForUser(oldUid, photoUrl);
        await db.recursiveDelete(reference);
      }
    });

async function deleteFileFromStorageLocation(bucketName, storagePath) {
  if (!bucketName || !storagePath || typeof bucketName !== "string" || typeof storagePath !== "string") {
    return;
  }

  await storage.bucket(bucketName).file(storagePath).delete({
    ignoreNotFound: true,
  });
}

function messageStorageLocations(message) {
  const locations = [];
  const fields = [
    ["imageBucket", "imagePath"],
    ["videoBucket", "videoPath"],
    ["audioBucket", "audioPath"],
  ];

  for (const [bucketField, pathField] of fields) {
    const bucket = message && message[bucketField];
    const path = message && message[pathField];
    if (typeof bucket === "string" && bucket.trim() && typeof path === "string" && path.trim()) {
      locations.push({bucket: bucket.trim(), path: path.trim()});
    }
  }

  return locations;
}

async function deleteStorageForMessage(message) {
  const locations = messageStorageLocations(message);
  await Promise.all(locations.map((location) =>
    deleteFileFromStorageLocation(location.bucket, location.path),
  ));
}

function isSavedContent(data) {
  return Boolean(data && data.savedAt);
}

async function deleteCollectionDocuments(collectionRef) {
  const snapshot = await collectionRef.get();
  if (snapshot.empty) {
    return;
  }

  let batch = db.batch();
  let opCount = 0;

  for (const document of snapshot.docs) {
    batch.delete(document.ref);
    opCount += 1;

    if (opCount === 400) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await batch.commit();
  }
}

async function syncFriendsCount(uid) {
  if (!uid || typeof uid !== "string") {
    return 0;
  }

  const userRef = db.collection("users").doc(uid);
  const userSnapshot = await userRef.get();
  // Friend deletion events can arrive after deleteMyAccount recursively
  // removed the profile. Never recreate a deleted user just to store zero.
  if (!userSnapshot.exists) {
    return 0;
  }

  const friendsSnapshot = await userRef.collection("friends").get();
  const friendsCount = friendsSnapshot.size;
  await userRef.set({
    friendsCount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return friendsCount;
}

async function deleteReferences(references) {
  if (!references.length) {
    return;
  }

  let batch = db.batch();
  let opCount = 0;

  for (const reference of references) {
    batch.delete(reference);
    opCount += 1;

    if (opCount === 400) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  }

  if (opCount > 0) {
    await batch.commit();
  }
}

async function deleteMembershipsForUser(uid, pseudoKey = "") {
  const communitiesSnapshot = await db.collection("communities").get();
  const references = [];

  for (const communityDocument of communitiesSnapshot.docs) {
    references.push(
        communityDocument.ref.collection("members").doc(uid),
        communityDocument.ref.collection("banned").doc(uid),
    );
    if (pseudoKey) references.push(communityDocument.ref.collection("allowlist").doc(pseudoKey));
  }

  await deleteReferences(references);
}

function normalizeStringArray(values) {
  if (!Array.isArray(values)) {
    return [];
  }
  const cleaned = [];
  for (const value of values) {
    if (typeof value !== "string") {
      continue;
    }
    const trimmed = value.trim();
    if (!trimmed || cleaned.includes(trimmed)) {
      continue;
    }
    cleaned.push(trimmed);
  }
  return cleaned;
}

async function getUserPushTokens(uid) {
  const userSnapshot = await db.collection("users").doc(uid).get();
  const data = userSnapshot.data() || {};
  const tokens = normalizeStringArray([
    ...(Array.isArray(data.fcmTokens) ? data.fcmTokens : []),
    data.fcmToken,
  ]);
  return tokens;
}

async function getNotificationPreferenceMode(uid, communityId) {
  const snapshot = await db
    .collection("users")
    .doc(uid)
    .collection("notificationPreferences")
    .doc(communityId)
    .get();

  const mode = snapshot.data() && snapshot.data().mode;
  return notificationMode(mode);
}

function shouldNotifyForPreference(mode, isExplicitlyIdentified) {
  return shouldNotify(mode, isExplicitlyIdentified);
}

function torpilleActionBody(fromPseudo, toPseudo) {
  const sender = typeof fromPseudo === "string" && fromPseudo.trim() ? fromPseudo.trim() : "Un utilisateur";
  const target = typeof toPseudo === "string" && toPseudo.trim() ? toPseudo.trim() : "un utilisateur";
  return `${sender} a torpillé ${target}`;
}

function remainingTorpilleTimeText(deadlineAt) {
  const deadlineMillis = deadlineAt && typeof deadlineAt.toMillis === "function" ?
    deadlineAt.toMillis() : Date.now();
  const remainingMinutes = Math.max(1, Math.ceil((deadlineMillis - Date.now()) / 60000));
  if (remainingMinutes < 60) {
    return remainingMinutes === 1 ? "1 minute" : `${remainingMinutes} minutes`;
  }
  const hours = Math.floor(remainingMinutes / 60);
  const minutes = remainingMinutes % 60;
  const hoursText = hours === 1 ? "1 heure" : `${hours} heures`;
  return minutes === 0 ? hoursText : `${hoursText} ${minutes} min`;
}

function messageTargetUid(message) {
  if (!message || typeof message !== "object") {
    return "";
  }
  const taggedUid = typeof message.taggedUid === "string" ? message.taggedUid.trim() : "";
  if (taggedUid) {
    return taggedUid;
  }
  const toUid = typeof message.toUid === "string" ? message.toUid.trim() : "";
  return toUid;
}

async function cleanupInvalidTokens(uid, invalidTokens) {
  const cleaned = normalizeStringArray(invalidTokens);
  if (!cleaned.length) {
    return;
  }

  const userRef = db.collection("users").doc(uid);
  const snapshot = await userRef.get();
  const currentPrimaryToken = snapshot.data() && snapshot.data().fcmToken;

  const payload = {
    fcmTokens: admin.firestore.FieldValue.arrayRemove(...cleaned),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (typeof currentPrimaryToken === "string" && cleaned.includes(currentPrimaryToken)) {
    payload.fcmToken = admin.firestore.FieldValue.delete();
  }

  await userRef.set(payload, {merge: true});
}

async function sendPushToUser(uid, {title, body, data}) {
  const tokens = await getUserPushTokens(uid);
  if (!tokens.length) {
    console.log("push skipped: no FCM tokens", {uid, title});
    return {successCount: 0, failureCount: 0};
  }

  const response = await admin.messaging().sendEachForMulticast(
      pushPayload(tokens, {title, body, data}, IOS_BUNDLE_ID)
  );

  const invalidTokens = [];
  response.responses.forEach((result, index) => {
    if (!result.success && result.error) {
      console.error("push send failure", {
        uid,
        code: result.error.code || "",
        message: result.error.message || "",
      });
      const code = result.error.code || "";
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token") {
        invalidTokens.push(tokens[index]);
      }
    }
  });

  if (invalidTokens.length) {
    await cleanupInvalidTokens(uid, invalidTokens);
  }

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

function buildMessageBody(message) {
  const sender = typeof message.senderPseudo === "string" ? message.senderPseudo.trim() : "";
  const senderPrefix = sender ? `@${sender} ` : "Quelqu'un ";

  switch (message.type) {
    case "image":
      return `${senderPrefix}a envoye une photo.`;
    case "video":
      return `${senderPrefix}a envoye une video.`;
    case "audio":
      return `${senderPrefix}a envoye un vocal.`;
    case "text":
    default:
      return `${senderPrefix}a envoye un message.`;
  }
}

function moderatorUidsFromEnv() {
  return normalizeStringArray((process.env.MODERATOR_UIDS || "").split(","));
}

function smtpTransportConfig() {
  const host = process.env.SMTP_HOST || "smtp.gmail.com";
  const user = process.env.SMTP_USER || "torpille.app@gmail.com";
  const pass = SMTP_PASSWORD.value();
  if (!host || !user || !pass) {
    return null;
  }

  const port = Number.parseInt(process.env.SMTP_PORT || "587", 10);
  return {
    host,
    port: Number.isFinite(port) ? port : 587,
    secure: String(process.env.SMTP_SECURE || "false").toLowerCase() === "true",
    auth: {user, pass},
  };
}

async function sendReportEmail(to, subject, text) {
  const cleanTo = typeof to === "string" ? to.trim() : "";
  if (!cleanTo) {
    return {status: "skipped", reason: "missing-recipient"};
  }

  const config = smtpTransportConfig();
  if (!config) {
    console.warn("report email skipped: SMTP is not configured", {to: cleanTo, subject});
    return {status: "skipped", reason: "smtp-not-configured"};
  }

  const from = process.env.SMTP_FROM || process.env.SMTP_USER || "torpille.app@gmail.com";
  const transporter = nodemailer.createTransport(config);
  await transporter.sendMail({
    from,
    to: cleanTo,
    subject,
    text,
  });
  return {status: "sent"};
}

async function authEmailForUid(uid) {
  const cleanUid = typeof uid === "string" ? uid.trim() : "";
  if (!cleanUid) {
    return "";
  }
  const authUser = await getAuthUserIfExists(cleanUid);
  return authUser && authUser.email ? authUser.email : "";
}

function reportReasonTitle(reason) {
  switch (reason) {
    case "harassment":
      return "Harcèlement";
    case "sexualContent":
      return "Contenu sexuel";
    case "violenceThreat":
      return "Violence ou menace";
    case "hateSpeech":
      return "Discours haineux";
    case "spam":
      return "Spam";
    case "unwantedContent":
      return "Contenu non désiré";
    default:
      return "Autre";
  }
}

async function sendReportEmails(reportId, report, moderationResult) {
  const reporterUid = typeof report.reporterUid === "string" ? report.reporterUid.trim() : "";
  const communityId = typeof report.communityId === "string" ? report.communityId.trim() : "";
  const [reporterEmail, reporterSnapshot, communitySnapshot] = await Promise.all([
    authEmailForUid(reporterUid),
    reporterUid ? db.collection("users").doc(reporterUid).get() : Promise.resolve(null),
    communityId ? db.collection("communities").doc(communityId).get() : Promise.resolve(null),
  ]);
  const reporterData = reporterSnapshot && reporterSnapshot.exists ? reporterSnapshot.data() : {};
  const reporterPseudo = typeof reporterData.pseudo === "string" ? reporterData.pseudo.trim() : "";
  const communityData = communitySnapshot && communitySnapshot.exists ? communitySnapshot.data() : {};
  const communityName = typeof communityData.name === "string" ? communityData.name.trim() : "";
  const authorPseudo = typeof report.authorPseudo === "string" ? report.authorPseudo.trim() : "";
  const authorUid = typeof report.authorUid === "string" ? report.authorUid.trim() : "";
  const contentType = typeof report.contentType === "string" ? report.contentType.trim() : "";
  const contentId = typeof report.contentId === "string" ? report.contentId.trim() : "";
  const reason = typeof report.reason === "string" ? report.reason : "other";
  const details = typeof report.details === "string" && report.details.trim() ?
    report.details.trim() :
    "Aucun détail fourni.";
  const createdAt = report.createdAt && typeof report.createdAt.toDate === "function" ?
    report.createdAt.toDate().toISOString() :
    "date inconnue";

  const ownerText = [
    "Nouveau signalement Torpille.",
    "",
    `Report ID: ${reportId}`,
    `Date: ${createdAt}`,
    `Type: ${contentType}`,
    `Contenu / profil ID: ${contentId}`,
    `Communauté: ${communityName || "nom inconnu"} (${communityId || "ID non renseigné"})`,
    `Utilisateur signalé: ${authorPseudo ? `@${authorPseudo}` : "non renseigné"} (${authorUid || "uid inconnu"})`,
    `Auteur du signalement: ${reporterPseudo ? `@${reporterPseudo} ` : ""}(${reporterUid || "uid inconnu"})${reporterEmail ? ` <${reporterEmail}>` : ""}`,
    `Motif: ${reportReasonTitle(reason)} (${reason})`,
    `Détails: ${details}`,
    `Nombre de signalements: ${moderationResult.reportCount}`,
    `Quarantaine automatique: ${moderationResult.quarantined ? "oui" : "non"}`,
    "",
    "Action attendue: analyser sous 24h, retirer le contenu abusif et exclure l'utilisateur fautif si nécessaire.",
  ].join("\n");

  const reporterText = [
    "Nous avons bien reçu ton signalement.",
    "",
    `Référence: ${reportId}`,
    `Utilisateur ou contenu signalé: ${authorPseudo ? `@${authorPseudo}` : contentId}`,
    `Motif: ${reportReasonTitle(reason)}`,
    "",
    moderationResult.quarantined ?
      "Le contenu a été automatiquement mis en quarantaine pendant l'analyse." :
      "Nous allons vérifier la situation et agir si nécessaire.",
    "",
    "Merci de contribuer à garder Torpille sûr.",
  ].join("\n");

  const results = {};
  results.owner = await sendReportEmail(
    REPORT_OWNER_EMAIL,
    `[Torpille] Nouveau signalement ${authorPseudo ? `@${authorPseudo}` : contentId}`,
    ownerText
  );
  results.reporter = await sendReportEmail(
    reporterEmail,
    "Signalement Torpille reçu",
    reporterText
  );
  return results;
}

async function moderatorUidsForReport(report) {
  const configured = moderatorUidsFromEnv();
  if (configured.length) {
    return configured;
  }

  const communityId = typeof report.communityId === "string" ? report.communityId.trim() : "";
  if (!communityId) {
    return [];
  }

  const communitySnapshot = await db.collection("communities").doc(communityId).get();
  const adminUid = communitySnapshot.data() && communitySnapshot.data().adminUid;
  return typeof adminUid === "string" && adminUid.trim() ? [adminUid.trim()] : [];
}

function targetRefForReport(report) {
  const contentId = typeof report.contentId === "string" ? report.contentId.trim() : "";
  const communityId = typeof report.communityId === "string" ? report.communityId.trim() : "";
  const contentType = typeof report.contentType === "string" ? report.contentType.trim() : "";
  if (!contentId) {
    return null;
  }

  if (contentType === "reel") {
    return db.collection("reels").doc(contentId);
  }

  if (!communityId) {
    return null;
  }

  if (contentType === "message") {
    return db.collection("communities").doc(communityId).collection("messages").doc(contentId);
  }
  if (contentType === "torpille") {
    return db.collection("communities").doc(communityId).collection("torpilles").doc(contentId);
  }
  return null;
}

async function quarantineIfNeeded(report) {
  const targetRef = targetRefForReport(report);
  if (!targetRef) {
    return {quarantined: false, reportCount: 0};
  }

  const contentId = typeof report.contentId === "string" ? report.contentId.trim() : "";
  const contentType = typeof report.contentType === "string" ? report.contentType.trim() : "";
  const reportsSnapshot = await db.collection("reports")
    .where("contentId", "==", contentId)
    .where("contentType", "==", contentType)
    .get();
  const reportCount = reportsSnapshot.size;
  const targetSnapshot = await targetRef.get();
  const targetData = targetSnapshot.exists ? targetSnapshot.data() || {} : {};
  const moderationFieldsByType = {
    message: ["text", "senderPseudo"],
    torpille: ["taggedPseudo", "fromPseudo"],
    reel: ["taggedPseudo", "authorPseudo", "communityName"],
  };
  const moderationText = moderationTextFromFields(
      targetData,
      moderationFieldsByType[contentType] || [],
  );
  const contentFilterMatched = containsObjectionableText(moderationText);
  const shouldQuarantine = reportCount > 0 && contentFilterMatched;

  const payload = {
    reportCount,
    contentFilterMatched,
    moderationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (shouldQuarantine) {
    payload.moderationStatus = "quarantined";
    payload.quarantinedAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await targetRef.set(payload, {merge: true});

  if (contentType === "message") {
    const torpilleId = targetData.torpilleId;
    const communityId = typeof report.communityId === "string" ? report.communityId.trim() : "";
    if (typeof torpilleId === "string" && torpilleId.trim() && communityId) {
      await db.collection("communities")
        .doc(communityId)
        .collection("torpilles")
        .doc(torpilleId.trim())
        .set(payload, {merge: true});
      const reelRef = db.collection("reels").doc(torpilleId.trim());
      const reelSnapshot = await reelRef.get();
      if (reelSnapshot.exists) {
        await reelRef.set(payload, {merge: true});
      }
    }
  }

  return {quarantined: shouldQuarantine, reportCount, contentFilterMatched};
}

async function removeReportedContentAndEjectAuthor(reportRef, report, source, moderatorUid = "") {
  if (!moderatorUid) {
    throw new Error("A human moderator UID is required for removal and ejection.");
  }
  const targetRef = targetRefForReport(report);
  let targetData = {};

  if (targetRef) {
    const targetSnapshot = await targetRef.get();
    targetData = targetSnapshot.exists ? targetSnapshot.data() || {} : {};
    await deleteStorageForMessage(targetData).catch((error) => {
      console.warn("moderation storage deletion failed", {
        reportId: reportRef.id,
        message: error instanceof Error ? error.message : String(error),
      });
    });
    await targetRef.delete();

    const linkedTorpilleId = typeof targetData.torpilleId === "string" ? targetData.torpilleId.trim() : "";
    const communityId = typeof report.communityId === "string" ? report.communityId.trim() : "";
    if (linkedTorpilleId && communityId) {
      await db.collection("communities").doc(communityId)
        .collection("torpilles").doc(linkedTorpilleId).delete().catch(() => undefined);
      await db.collection("reels").doc(linkedTorpilleId).delete().catch(() => undefined);
    }
  }

  const authorUid = typeof report.authorUid === "string" ? report.authorUid.trim() : "";
  const communityId = typeof report.communityId === "string" ? report.communityId.trim() : "";
  if (authorUid) {
    if (communityId) {
      const communityRef = db.collection("communities").doc(communityId);
      const batch = db.batch();
      batch.set(communityRef.collection("banned").doc(authorUid), {
        uid: authorUid,
        pseudo: report.authorPseudo || "",
        bannedAt: admin.firestore.FieldValue.serverTimestamp(),
        bannedByUid: moderatorUid,
        reason: report.reason || "other",
        reportId: reportRef.id,
      }, {merge: true});
      batch.delete(communityRef.collection("members").doc(authorUid));
      batch.set(db.collection("users").doc(authorUid), {
        communityIds: admin.firestore.FieldValue.arrayRemove(communityId),
        accountStatus: "ejected",
        moderationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await batch.commit();
    } else {
      await db.collection("users").doc(authorUid).set({
        accountStatus: "ejected",
        moderationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    const authUser = await getAuthUserIfExists(authorUid);
    if (authUser) {
      await admin.auth().updateUser(authorUid, {disabled: true});
      await admin.auth().revokeRefreshTokens(authorUid);
    }
  }

  await reportRef.set({
    status: "enforced",
    resolution: "contentRemovedAndAuthorEjected",
    resolutionSource: source,
    resolvedByUid: moderatorUid,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

exports.resolveModerationReport = onCall({region: "europe-west1"}, async (request) => {
  const moderatorUid = request.auth && request.auth.uid;
  if (!moderatorUid || !moderatorUidsFromEnv().includes(moderatorUid)) {
    throw new HttpsError("permission-denied", "Moderator access required.");
  }

  const reportId = typeof request.data?.reportId === "string" ? request.data.reportId.trim() : "";
  const decision = request.data?.decision;
  if (!reportId || !["uphold", "dismiss"].includes(decision)) {
    throw new HttpsError("invalid-argument", "A reportId and a valid decision are required.");
  }

  const reportRef = db.collection("reports").doc(reportId);
  const snapshot = await reportRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Report not found.");
  }

  if (decision === "uphold") {
    await removeReportedContentAndEjectAuthor(reportRef, snapshot.data() || {}, "moderator", moderatorUid);
  } else {
    await reportRef.set({
      status: "dismissed",
      resolution: "noViolationFound",
      resolvedByUid: moderatorUid,
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {status: decision === "uphold" ? "enforced" : "dismissed"};
});

exports.notifyOverdueModerationReports = onSchedule(
    {
      region: "europe-west1",
      schedule: "every 15 minutes",
      maxInstances: 1,
      timeZone: "Europe/Brussels",
    },
    async () => {
      const cutoff = Date.now() - 24 * 60 * 60 * 1000;
      const snapshot = await db.collection("reports").where("status", "==", "reviewing").get();
      const overdue = snapshot.docs.filter((document) => {
        const createdAt = document.data().createdAt;
        return createdAt && typeof createdAt.toMillis === "function" && createdAt.toMillis() <= cutoff;
      });

      for (const reportDocument of overdue) {
        const report = reportDocument.data();
        const moderatorUids = await moderatorUidsForReport(report);
        await Promise.all(moderatorUids.map((moderatorUid) => sendPushToUser(moderatorUid, {
          title: "Signalement à vérifier immédiatement",
          body: "Ce signalement a dépassé le délai de vérification de 24 heures.",
          data: {
            destination: "notificationCenter",
            type: "moderationReportOverdue",
            reportId: reportDocument.id,
          },
        })));
        await reportDocument.ref.set({
          status: "overdue",
          overdueNotifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      console.log("notifyOverdueModerationReports complete", {notified: overdue.length});
    },
);

async function getAuthUserIfExists(uid) {
  try {
    return await admin.auth().getUser(uid);
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      return null;
    }
    throw error;
  }
}

async function getAuthUserByEmailIfExists(email) {
  if (!email) {
    return null;
  }

  try {
    return await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error && error.code === "auth/user-not-found") {
      return null;
    }
    throw error;
  }
}

function selectReplacementAdmin(memberDocs, currentUid) {
  return memberDocs
    .map((document) => ({id: document.id, data: document.data() || {}}))
    .filter((entry) => {
      const uid = (entry.data.uid || entry.id || "").trim();
      return uid && uid !== currentUid;
    })
    .sort((lhs, rhs) => {
      const xpDiff = asInt64(rhs.data.xpInCommunity) - asInt64(lhs.data.xpInCommunity);
      if (xpDiff !== 0) {
        return xpDiff;
      }

      const leftPseudo = String(lhs.data.pseudo || "").toLowerCase();
      const rightPseudo = String(rhs.data.pseudo || "").toLowerCase();
      if (leftPseudo !== rightPseudo) {
        return leftPseudo < rightPseudo ? -1 : 1;
      }

      const leftUid = String(lhs.data.uid || lhs.id || "").toLowerCase();
      const rightUid = String(rhs.data.uid || rhs.id || "").toLowerCase();
      if (leftUid === rightUid) {
        return 0;
      }
      return leftUid < rightUid ? -1 : 1;
    })[0] || null;
}

async function deleteCommunityTree(communityRef) {
  const mediaSnapshots = await Promise.all([
    communityRef.collection("messages").get(),
    communityRef.collection("savedMessages").get(),
    communityRef.collection("torpilles").get(),
  ]);
  await Promise.all(mediaSnapshots.flatMap((snapshot) => snapshot.docs).map((document) =>
    deleteStorageForMessage(document.data() || {}).catch(() => undefined),
  ));
  await storage.bucket().deleteFiles({
    prefix: `communities/${communityRef.id}/`,
    force: true,
  }).catch((error) => {
    console.warn("Community storage prefix cleanup failed", {
      communityId: communityRef.id,
      error: error && error.message ? error.message : String(error),
    });
  });
  await db.recursiveDelete(communityRef);
}

async function deleteCommunityReferences(communityId) {
  const specifications = [
    ["communityJoinRequests", false],
    ["reports", false],
    ["reels", true],
  ];
  for (const [collection, deleteStorage] of specifications) {
    await deleteQueryMatches(
        db.collection(collection).where("communityId", "==", communityId),
        {deleteStorage},
    );
  }

  const userDocuments = await db.collection("users").get();
  let batch = db.batch();
  let operationCount = 0;
  for (const userDocument of userDocuments.docs) {
    const data = userDocument.data() || {};
    const communityXP = {...(data.communityXP || {})};
    delete communityXP[communityId];
    const xpTotal = Object.values(communityXP).reduce(
        (total, value) => total + asInt64(value),
        0,
    );
    batch.set(userDocument.ref, {
      communityIds: admin.firestore.FieldValue.arrayRemove(communityId),
      pinnedCommunityIds: admin.firestore.FieldValue.arrayRemove(communityId),
      communityXP,
      xpTotal,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    operationCount += 1;
    if (operationCount === 350) {
      await batch.commit();
      batch = db.batch();
      operationCount = 0;
    }
  }
  if (operationCount > 0) await batch.commit();

  const userScopedReferences = userDocuments.docs.flatMap((userDocument) => [
    userDocument.ref.collection("notificationPreferences").doc(communityId),
    userDocument.ref.collection("contentFilters").doc(communityId),
  ]);
  for (let index = 0; index < userScopedReferences.length; index += 25) {
    await Promise.all(userScopedReferences.slice(index, index + 25).map((reference) =>
      db.recursiveDelete(reference),
    ));
  }
}

exports.deleteCommunity = onCall(
    {region: "europe-west1", timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
      const uid = request.auth && request.auth.uid;
      const communityId = typeof request.data?.communityId === "string" ?
        request.data.communityId.trim() : "";
      if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
      if (!communityId) throw new HttpsError("invalid-argument", "A communityId is required.");

      const communityRef = db.collection("communities").doc(communityId);
      const snapshot = await communityRef.get();
      if (!snapshot.exists) throw new HttpsError("not-found", "Community not found.");
      if (snapshot.data().adminUid !== uid) {
        throw new HttpsError("permission-denied", "Administrator access required.");
      }

      await communityRef.set({
        deletionInProgress: true,
        deletionRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletionRequestedByUid: uid,
      }, {merge: true});

      await deleteCommunityReferences(communityId);
      await deleteCommunityTree(communityRef);
      return {status: "deleted", communityId};
    },
);

async function deleteQueryMatches(query, options = {}) {
  const snapshot = await query.get();
  if (options.deleteStorage) {
    await Promise.all(snapshot.docs.map((document) =>
      deleteStorageForMessage(document.data() || {}).catch(() => undefined),
    ));
  }
  await deleteReferences(snapshot.docs.map((document) => document.ref));
  return snapshot.size;
}

async function deleteTopLevelReferencesForUser(uid) {
  const specifications = [
    ["friendRequests", "fromUid"],
    ["friendRequests", "toUid"],
    ["friendRemovals", "actorUid"],
    ["friendRemovals", "toUid"],
    ["communityJoinRequests", "requesterUid"],
    ["communityJoinRequests", "adminUid"],
    ["reports", "reporterUid"],
    ["reports", "authorUid"],
  ];
  for (const [collection, field] of specifications) {
    await deleteQueryMatches(db.collection(collection).where(field, "==", uid));
  }

  await deleteQueryMatches(db.collection("reels").where("authorUid", "==", uid), {deleteStorage: true});
}

async function deleteCommunityContentForUser(uid) {
  const specifications = [
    ["messages", "senderUid", true],
    ["savedMessages", "senderUid", true],
    ["torpilles", "fromUid", true],
    ["torpilles", "toUid", false],
  ];
  // Collection-group field indexes can be disabled independently in
  // Firestore. Query each known community subcollection instead so account
  // deletion never depends on an optional collection-group index.
  const communitiesSnapshot = await db.collection("communities").get();
  for (const communityDocument of communitiesSnapshot.docs) {
    for (const [subcollection, field, deleteStorage] of specifications) {
      await deleteQueryMatches(
          communityDocument.ref.collection(subcollection).where(field, "==", uid),
          {deleteStorage},
      );
    }
  }
}

async function deleteUserReferencesFromOtherProfiles(uid) {
  const userRefs = await db.collection("users").listDocuments();
  const directReferences = [];
  for (const otherUserRef of userRefs) {
    if (otherUserRef.id === uid) continue;
    directReferences.push(
        otherUserRef.collection("friends").doc(uid),
        otherUserRef.collection("blockedUsers").doc(uid),
        otherUserRef.collection("blockedBy").doc(uid),
    );
    const contentFilterRefs = await otherUserRef.collection("contentFilters").listDocuments();
    for (const contentFilterRef of contentFilterRefs) {
      directReferences.push(contentFilterRef.collection("hiddenMembers").doc(uid));
    }
  }
  await deleteReferences(directReferences);
}

exports.deleteMyAccount = onCall({region: "europe-west1", timeoutSeconds: 540, memory: "512MiB"}, async (request) => {
  let step = "auth-check";
  const uid = request.auth && request.auth.uid;
  let authDeleted = false;

  try {
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    step = "load-auth-user";
    const authUser = await getAuthUserIfExists(uid);

    step = "load-user";
    const userRef = db.collection("users").doc(uid);
    const userSnapshot = await userRef.get();
    const userData = userSnapshot.data() || {};
    const pseudoKey = typeof userData.pseudoKey === "string" ? userData.pseudoKey : "";
    const photoUrl = typeof userData.photoUrl === "string" ? userData.photoUrl : "";

    // Firebase Auth owns email uniqueness. Delete that identity before any
    // best-effort data cleanup so a missing Firestore index or stale reference
    // can never leave the email reserved after the user requested deletion.
    step = "delete-auth-user";
    if (authUser) {
      await admin.auth().deleteUser(uid);
    }
    authDeleted = true;
    await db.collection("contactDiscovery").doc(uid).delete();
    await db.collection("contactDiscoveryLimits").doc(uid).delete();

    step = "owned-communities";
    const ownedCommunitiesSnapshot = await db
      .collection("communities")
      .where("adminUid", "==", uid)
      .get();

    for (const communityDocument of ownedCommunitiesSnapshot.docs) {
      const communityRef = communityDocument.ref;

      step = `owned-community-members:${communityRef.id}`;
      const membersSnapshot = await communityRef.collection("members").get();
      const replacement = selectReplacementAdmin(membersSnapshot.docs, uid);

      if (replacement) {
        const replacementUid = (replacement.data.uid || replacement.id || "").trim();
        step = `transfer-admin:${communityRef.id}`;
        await communityRef.update({
          adminUid: replacementUid,
        });
        const pendingRequests = await db.collection("communityJoinRequests")
            .where("communityId", "==", communityRef.id)
            .get();
        for (const pendingRequest of pendingRequests.docs) {
          if (pendingRequest.data().adminUid === uid) {
            await pendingRequest.ref.set({adminUid: replacementUid}, {merge: true});
          }
        }
      } else {
        step = `delete-community-tree:${communityRef.id}`;
        await deleteCommunityTree(communityRef);
        await deleteQueryMatches(
            db.collection("communityJoinRequests").where("communityId", "==", communityRef.id),
        );
      }
    }

    step = "delete-community-content";
    await deleteCommunityContentForUser(uid);

    step = "delete-memberships";
    await deleteMembershipsForUser(uid, pseudoKey);

    step = "delete-top-level-references";
    await deleteTopLevelReferencesForUser(uid);

    step = "delete-references-from-other-users";
    await deleteUserReferencesFromOtherProfiles(uid);

    if (pseudoKey) {
      step = "delete-pseudo";
      await db.collection("pseudos").doc(pseudoKey).delete().catch(() => {});
    }

    if (userSnapshot.exists) {
      step = "delete-user-tree";
      await db.recursiveDelete(userRef);
    }

    step = "delete-profile-photos";
    await deleteProfileImagesForUser(uid, photoUrl).catch((error) => {
      console.error("Profile image prefix cleanup failed", {uid, error});
    });

    return {deleted: true, cleanupComplete: true};
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("deleteMyAccount failed", {step, message, error});
    if (authDeleted) {
      // The account and its email reservation are already gone. Returning a
      // success lets the client clear its obsolete local session; the Auth
      // onDelete safety net also retries user-tree and profile-image cleanup.
      return {deleted: true, cleanupComplete: false, cleanupFailedAt: step};
    }
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError(
      "failed-precondition",
      `deleteMyAccount failed at ${step}: ${message}`,
      {step, message}
    );
  }
});

exports.notifyOnTorpilleCreated = onDocumentCreated(
    {
      region: "europe-west1",
      document: "communities/{communityId}/torpilles/{torpilleId}",
    },
    async (event) => {
      const torpille = event.data && event.data.data();
      if (!torpille) {
        return;
      }

      const communityId = event.params.communityId;
      const toUid = typeof torpille.toUid === "string" ? torpille.toUid.trim() : "";
      const fromUid = typeof torpille.fromUid === "string" ? torpille.fromUid.trim() : "";
      if (!toUid || toUid === fromUid) {
        return;
      }

      const communitySnapshot = await db.collection("communities").doc(communityId).get();
      const communityName = (communitySnapshot.data() && communitySnapshot.data().name) || "Torpille";
      const senderPseudo = typeof torpille.fromPseudo === "string" ? torpille.fromPseudo.trim() : "";
      const senderLabel = senderPseudo ? `@${senderPseudo}` : "Un utilisateur";
      const remainingTime = remainingTorpilleTimeText(torpille.deadlineAt);
      const body = torpille.responseRequired === false ? `${senderLabel} a répondu hors horaires. Aucune réponse ni pénalité pour toi.` : `${senderLabel} t'a torpillé. Il te reste ${remainingTime} pour répondre.`;
      // A direct torpille always alerts its recipient, even if discussion alerts are muted.

      const result = await sendPushToUser(toUid, {
        title: torpille.responseRequired === false ? "Réponse hors horaires" : `Torpille reçue • ${remainingTime}`,
        body,
        data: {
          destination: "communityDiscussion",
          communityId,
          type: "torpille",
          torpilleId: event.params.torpilleId,
        },
      });
      console.log("notifyOnTorpilleCreated", {communityId, toUid, result});
    }
);

exports.notifyOnFriendRequestCreated = onDocumentCreated(
    {
      region: "europe-west1",
      document: "friendRequests/{requestId}",
    },
    async (event) => {
      const request = event.data && event.data.data();
      if (!request) {
        return;
      }

      const toUid = typeof request.toUid === "string" ? request.toUid.trim() : "";
      const fromUid = typeof request.fromUid === "string" ? request.fromUid.trim() : "";
      const fromPseudo = typeof request.fromPseudo === "string" ? request.fromPseudo.trim() : "";
      const status = typeof request.status === "string" ? request.status : "";
      if (!toUid || !fromUid || toUid === fromUid || status !== "pending") {
        return;
      }

      const sender = fromPseudo ? `@${fromPseudo}` : "Un utilisateur";
      const result = await sendPushToUser(toUid, {
        title: "Demande d'ami",
        body: `${sender} veut devenir ami avec toi.`,
        data: {
          destination: "notificationCenter",
          type: "friendRequest",
          requestId: event.params.requestId,
        },
      });
      console.log("notifyOnFriendRequestCreated", {toUid, fromUid, requestId: event.params.requestId, result});
    }
);

exports.requestCommunityMembership = onCall({region: "europe-west1"}, async (request) => {
  const uid = request.auth && request.auth.uid;
  const communityId = typeof request.data?.communityId === "string" ? request.data.communityId.trim() : "";
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  if (request.auth.token.email_verified !== true) {
    throw new HttpsError("failed-precondition", "A verified email is required.");
  }
  if (!communityId) throw new HttpsError("invalid-argument", "A communityId is required.");

  const userRef = db.collection("users").doc(uid);
  const communityRef = db.collection("communities").doc(communityId);
  const memberRef = communityRef.collection("members").doc(uid);
  const bannedRef = communityRef.collection("banned").doc(uid);
  const joinRequestRef = db.collection("communityJoinRequests").doc(`${communityId}_${uid}`);

  return db.runTransaction(async (transaction) => {
    const [userSnapshot, communitySnapshot, memberSnapshot, bannedSnapshot, joinRequestSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(communityRef), transaction.get(memberRef),
      transaction.get(bannedRef), transaction.get(joinRequestRef),
    ]);
    if (!userSnapshot.exists) throw new HttpsError("failed-precondition", "Profile required.");
    if (!communitySnapshot.exists) throw new HttpsError("not-found", "Community not found.");
    if (bannedSnapshot.exists) throw new HttpsError("permission-denied", "You cannot join this community.");
    if (memberSnapshot.exists) return {status: "already-member"};

    const user = userSnapshot.data() || {};
    const community = communitySnapshot.data() || {};
    const pseudo = typeof user.pseudo === "string" ? user.pseudo.trim() : "";
    const hasAvatar = (typeof user.photoUrl === "string" && user.photoUrl.trim()) ||
      (typeof user.profileIcon === "string" && user.profileIcon.trim());
    if (pseudo.length < 3 || !hasAvatar || !user.termsAcceptedAt || !user.moderationRulesAcceptedAt) {
      throw new HttpsError("failed-precondition", "A complete profile is required.");
    }

    if (community.isPublic !== false) {
      transaction.set(memberRef, {
        uid, pseudo, photoUrl: user.photoUrl || null, profileIcon: user.profileIcon || null, xpInCommunity: 0,
      }, {merge: true});
      transaction.set(userRef, {
        communityIds: admin.firestore.FieldValue.arrayUnion(communityId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      if (joinRequestSnapshot.exists) transaction.delete(joinRequestRef);
      return {status: "joined"};
    }

    const existing = joinRequestSnapshot.data() || {};
    if (joinRequestSnapshot.exists && existing.status === "pending") return {status: "already-pending"};
    transaction.set(joinRequestRef, {
      communityId,
      communityName: community.name || "Torpille",
      requesterUid: uid,
      requesterPseudo: pseudo,
      requesterPhotoUrl: user.photoUrl || null,
      requesterProfileIcon: user.profileIcon || null,
      adminUid: community.adminUid,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      resolvedAt: null,
      reminderSentAt: null,
    });
    return {status: "pending"};
  });
});

exports.resolveCommunityJoinRequest = onCall({region: "europe-west1"}, async (request) => {
  const adminUid = request.auth && request.auth.uid;
  const requestId = typeof request.data?.requestId === "string" ? request.data.requestId.trim() : "";
  const decision = request.data?.decision;
  if (!adminUid) throw new HttpsError("unauthenticated", "Authentication required.");
  if (!requestId || !["accepted", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "A requestId and valid decision are required.");
  }
  const joinRequestRef = db.collection("communityJoinRequests").doc(requestId);
  return db.runTransaction(async (transaction) => {
    const joinSnapshot = await transaction.get(joinRequestRef);
    if (!joinSnapshot.exists) throw new HttpsError("not-found", "Join request not found.");
    const joinRequest = joinSnapshot.data() || {};
    if (joinRequest.adminUid !== adminUid) throw new HttpsError("permission-denied", "Administrator access required.");
    if (joinRequest.status !== "pending") throw new HttpsError("failed-precondition", "This request has already been answered.");

    const communityRef = db.collection("communities").doc(joinRequest.communityId);
    const communitySnapshot = await transaction.get(communityRef);
    if (!communitySnapshot.exists || communitySnapshot.data().adminUid !== adminUid) {
      throw new HttpsError("permission-denied", "Administrator access required.");
    }
    if (decision === "accepted") {
      const requesterRef = db.collection("users").doc(joinRequest.requesterUid);
      const bannedRef = communityRef.collection("banned").doc(joinRequest.requesterUid);
      const [requesterSnapshot, bannedSnapshot] = await Promise.all([
        transaction.get(requesterRef), transaction.get(bannedRef),
      ]);
      if (!requesterSnapshot.exists || bannedSnapshot.exists) {
        throw new HttpsError("failed-precondition", "The requester can no longer join.");
      }
      const profile = requesterSnapshot.data() || {};
      transaction.set(communityRef.collection("members").doc(joinRequest.requesterUid), {
        uid: joinRequest.requesterUid,
        pseudo: profile.pseudo || joinRequest.requesterPseudo || "Utilisateur",
        photoUrl: profile.photoUrl || null,
        profileIcon: profile.profileIcon || null,
        xpInCommunity: 0,
      }, {merge: true});
      transaction.set(requesterRef, {
        communityIds: admin.firestore.FieldValue.arrayUnion(joinRequest.communityId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.set(joinRequestRef, {
      status: decision,
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return {status: decision};
  });
});

exports.notifyOnCommunityJoinRequestCreated = onDocumentCreated(
    {region: "europe-west1", document: "communityJoinRequests/{requestId}"},
    async (event) => {
      const joinRequest = event.data && event.data.data();
      if (!joinRequest || joinRequest.status !== "pending") return;
      const requester = joinRequest.requesterPseudo ? `@${joinRequest.requesterPseudo}` : "Un utilisateur";
      await sendPushToUser(joinRequest.adminUid, {
        title: "Nouvelle demande d’accès",
        body: `${requester} souhaite rejoindre ${joinRequest.communityName || "ta communauté"}.`,
        data: {destination: "communityInfo", communityId: joinRequest.communityId, type: "communityJoinRequest", requestId: event.params.requestId},
      });
    },
);

exports.notifyOnCommunityJoinRequestResolved = onDocumentWritten(
    {region: "europe-west1", document: "communityJoinRequests/{requestId}"},
    async (event) => {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();
      if (!before || !after || before.status !== "pending" || !["accepted", "rejected"].includes(after.status)) return;
      const accepted = after.status === "accepted";
      await sendPushToUser(after.requesterUid, {
        title: accepted ? "Demande acceptée" : "Demande refusée",
        body: accepted ? `Tu peux maintenant rejoindre ${after.communityName}.` : `Ta demande pour rejoindre ${after.communityName} a été refusée.`,
        data: {destination: accepted ? "communityDiscussion" : "notificationCenter", communityId: after.communityId, type: "communityJoinRequestDecision", requestId: event.params.requestId, status: after.status},
      });
    },
);

exports.remindOverdueCommunityJoinRequests = onSchedule(
    {region: "europe-west1", schedule: "every 60 minutes", maxInstances: 1, timeZone: "Europe/Brussels", secrets: [SMTP_PASSWORD]},
    async () => {
      const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
      const snapshot = await db.collection("communityJoinRequests")
          .where("status", "==", "pending").where("createdAt", "<=", cutoff).get();
      let sent = 0;
      for (const document of snapshot.docs) {
        const joinRequest = document.data() || {};
        if (joinRequest.reminderSentAt) continue;
        const email = await authEmailForUid(joinRequest.adminUid);
        const result = await sendReportEmail(
            email,
            `Rappel : demande d’accès à ${joinRequest.communityName || "votre communauté"}`,
            `${joinRequest.requesterPseudo ? `@${joinRequest.requesterPseudo}` : "Un utilisateur"} attend votre réponse depuis plus de 24 heures. Ouvrez Torpille pour accepter ou refuser la demande.`,
        );
        if (result && result.status === "sent") {
          await document.ref.set({reminderSentAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
          sent += 1;
        }
      }
      console.log("remindOverdueCommunityJoinRequests complete", {sent});
    },
);

exports.notifyOnFriendRequestStatusChanged = onDocumentWritten(
    {
      region: "europe-west1",
      document: "friendRequests/{requestId}",
    },
    async (event) => {
      const before = event.data && event.data.before && event.data.before.data();
      const after = event.data && event.data.after && event.data.after.data();
      if (!before || !after) {
        return;
      }

      const previousStatus = typeof before.status === "string" ? before.status : "";
      const status = typeof after.status === "string" ? after.status : "";
      if (previousStatus === status || previousStatus !== "pending") {
        return;
      }
      if (status !== "accepted" && status !== "rejected") {
        return;
      }

      const fromUid = typeof after.fromUid === "string" ? after.fromUid.trim() : "";
      const toUid = typeof after.toUid === "string" ? after.toUid.trim() : "";
      const toPseudo = typeof after.toPseudo === "string" ? after.toPseudo.trim() : "";
      if (!fromUid || !toUid || fromUid === toUid) {
        return;
      }

      const target = toPseudo ? `@${toPseudo}` : "Un utilisateur";
      const body = status === "accepted" ?
        `${target} a accepté ta demande d'ami.` :
        `${target} a refusé ta demande d'ami.`;
      const result = await sendPushToUser(fromUid, {
        title: "Demande d'ami",
        body,
        data: {
          destination: "notificationCenter",
          type: "friendRequestStatus",
          requestId: event.params.requestId,
          status,
        },
      });
      console.log("notifyOnFriendRequestStatusChanged", {fromUid, toUid, requestId: event.params.requestId, status, result});
    }
);

exports.notifyOnFriendRemoved = onDocumentCreated(
    {
      region: "europe-west1",
      document: "friendRemovals/{removalId}",
    },
    async (event) => {
      const removal = event.data && event.data.data();
      if (!removal) {
        return;
      }

      const actorUid = typeof removal.actorUid === "string" ? removal.actorUid.trim() : "";
      const actorPseudo = typeof removal.actorPseudo === "string" ? removal.actorPseudo.trim() : "";
      const toUid = typeof removal.toUid === "string" ? removal.toUid.trim() : "";
      if (!actorUid || !toUid || actorUid === toUid || removal.type !== "friendRemoved") {
        return;
      }

      const actor = actorPseudo ? `@${actorPseudo}` : "Un utilisateur";
      const result = await sendPushToUser(toUid, {
        title: "Amitié terminée",
        body: `${actor} a mis fin à votre amitié.`,
        data: {
          destination: "notificationCenter",
          type: "friendRemoved",
          removalId: event.params.removalId,
        },
      });
      console.log("notifyOnFriendRemoved", {actorUid, toUid, removalId: event.params.removalId, result});
    }
);

exports.notifyOnMessageCreated = onDocumentCreated(
    {
      region: "europe-west1",
      document: "communities/{communityId}/messages/{messageId}",
    },
    async (event) => {
      const message = event.data && event.data.data();
      if (!message || message.type === "system") {
        return;
      }

      const communityId = event.params.communityId;
      const senderUid = typeof message.senderUid === "string" ? message.senderUid.trim() : "";
      if (!senderUid) {
        return;
      }

      const communitySnapshot = await db.collection("communities").doc(communityId).get();
      const communityName = (communitySnapshot.data() && communitySnapshot.data().name) || "Torpille";
      const membersSnapshot = await db.collection("communities").doc(communityId).collection("members").get();
      const targetUid = messageTargetUid(message);
      const isTorpilleMessage = typeof message.torpilleId === "string" && message.torpilleId.trim().length > 0;

      await Promise.all(membersSnapshot.docs.map(async (memberDocument) => {
        const recipientUid = (memberDocument.data().uid || memberDocument.id || "").trim();
        if (!recipientUid || recipientUid === senderUid) {
          return;
        }
        if (isTorpilleMessage && recipientUid === targetUid) {
          return;
        }

        const mode = await getNotificationPreferenceMode(recipientUid, communityId);
        if (mode !== "all") {
          return;
        }

        const result = await sendPushToUser(recipientUid, {
          title: communityName,
          body: buildMessageBody(message),
          data: {
            destination: "notificationCenter",
            communityId,
            type: "message",
            messageId: event.params.messageId,
          },
        });
        console.log("notifyOnMessageCreated", {
          communityId,
          recipientUid,
          messageId: event.params.messageId,
          result,
        });
      }));
    }
);

exports.syncFriendsCountOnFriendWrite = onDocumentWritten(
    {
      region: "europe-west1",
      document: "users/{uid}/friends/{friendUid}",
    },
    async (event) => {
      const uid = event.params.uid;
      const friendsCount = await syncFriendsCount(uid);
      console.log("syncFriendsCountOnFriendWrite", {
        uid,
        friendUid: event.params.friendUid,
        friendsCount,
      });
    }
);

exports.filterCommunityMessageOnCreate = onDocumentCreated(
    {
      region: "europe-west1",
      document: "communities/{communityId}/messages/{messageId}",
    },
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) {
        return;
      }

      const quarantined = await quarantineForContentFilter(event.data.ref, data, [
        "text",
      ]);
      if (quarantined) {
        console.log("filterCommunityMessageOnCreate quarantined", {
          communityId: event.params.communityId,
          messageId: event.params.messageId,
        });
      }
    }
);

exports.filterTorpilleOnCreate = onDocumentCreated(
    {
      region: "europe-west1",
      document: "communities/{communityId}/torpilles/{torpilleId}",
    },
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) {
        return;
      }

      const quarantined = await quarantineForContentFilter(event.data.ref, data, [
        "taggedPseudo",
        "fromPseudo",
      ]);
      if (quarantined) {
        console.log("filterTorpilleOnCreate quarantined", {
          communityId: event.params.communityId,
          torpilleId: event.params.torpilleId,
        });
      }
    }
);

exports.cleanupExpiredCommunityContent = onSchedule(
    {
      region: "europe-west1",
      schedule: "every 24 hours",
      maxInstances: 1,
      timeZone: "Europe/Brussels",
    },
    async () => {
      const cutoffDate = new Date(Date.now() - CONTENT_RETENTION_DAYS * 24 * 60 * 60 * 1000);
      const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);
      const communitiesSnapshot = await db.collection("communities").get();
      let deletedMessages = 0;
      let deletedTorpilles = 0;
      let skippedSavedMessages = 0;

      for (const communityDocument of communitiesSnapshot.docs) {
        const communityRef = communityDocument.ref;
        const expiredMessagesSnapshot = await communityRef
            .collection("messages")
            .where("createdAt", "<=", cutoffTimestamp)
            .get();

        let batch = db.batch();
        let opCount = 0;

        for (const messageDocument of expiredMessagesSnapshot.docs) {
          const message = messageDocument.data() || {};
          if (isSavedContent(message)) {
            skippedSavedMessages += 1;
            continue;
          }

          await deleteStorageForMessage(message).catch((error) => {
            console.warn("cleanupExpiredCommunityContent storage delete failed", {
              communityId: communityDocument.id,
              messageId: messageDocument.id,
              error: error && error.message ? error.message : String(error),
            });
          });

          batch.delete(messageDocument.ref);
          opCount += 1;
          deletedMessages += 1;

          const torpilleId = typeof message.torpilleId === "string" ? message.torpilleId.trim() : "";
          if (torpilleId) {
            batch.delete(communityRef.collection("torpilles").doc(torpilleId));
            opCount += 1;
            deletedTorpilles += 1;
          }

          if (opCount >= 350) {
            await batch.commit();
            batch = db.batch();
            opCount = 0;
          }
        }

        if (opCount > 0) {
          await batch.commit();
        }
      }

      console.log("cleanupExpiredCommunityContent complete", {
        cutoff: cutoffDate.toISOString(),
        deletedMessages,
        deletedTorpilles,
        skippedSavedMessages,
      });
    }
);

exports.filterReelOnCreate = onDocumentCreated(
    {
      region: "europe-west1",
      document: "reels/{reelId}",
    },
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) {
        return;
      }

      const quarantined = await quarantineForContentFilter(event.data.ref, data, [
        "taggedPseudo",
        "authorPseudo",
        "communityName",
      ]);
      if (quarantined) {
        console.log("filterReelOnCreate quarantined", {
          reelId: event.params.reelId,
        });
      }
    }
);

exports.onReportCreated = onDocumentCreated(
    {
      region: "europe-west1",
      document: "reports/{reportId}",
      secrets: [SMTP_PASSWORD],
    },
    async (event) => {
      const report = event.data && event.data.data();
      if (!report) {
        return;
      }

      const reportId = event.params.reportId;
      const reporterUid = typeof report.reporterUid === "string" ? report.reporterUid.trim() : "";
      const reportedUid = typeof report.authorUid === "string" ? report.authorUid.trim() : "";
      const reason = typeof report.reason === "string" ? report.reason : "other";
      const authorPseudo = typeof report.authorPseudo === "string" && report.authorPseudo.trim() ?
        `@${report.authorPseudo.trim()}` :
        "un contenu";

      let moderationResult = {quarantined: false, reportCount: 0};
      try {
        moderationResult = await quarantineIfNeeded(report);
      } catch (error) {
        console.error("onReportCreated quarantine failed", {
          reportId,
          message: error instanceof Error ? error.message : String(error),
        });
      }

      const moderatorUids = await moderatorUidsForReport(report);
      await Promise.all(moderatorUids.map(async (moderatorUid) => {
        if (!moderatorUid || moderatorUid === reporterUid || moderatorUid === reportedUid) {
          return;
        }
        await sendPushToUser(moderatorUid, {
          title: "Nouveau signalement Torpille",
          body: `${authorPseudo} a été signalé (${reason}).`,
          data: {
            destination: "notificationCenter",
            type: "moderationReport",
            reportId,
            contentId: report.contentId || "",
            contentType: report.contentType || "",
          },
        });
      }));

      if (reporterUid) {
        await sendPushToUser(reporterUid, {
          title: "Signalement reçu",
          body: moderationResult.quarantined ?
            "Merci. Ce contenu est automatiquement mis en quarantaine pendant l'analyse." :
            "Merci. Nous vérifions ce contenu et agirons si nécessaire.",
          data: {
            destination: "notificationCenter",
            type: "reportAcknowledgement",
            reportId,
          },
        });
      }

      let emailResults = {
        owner: {status: "skipped", reason: "not-attempted"},
        reporter: {status: "skipped", reason: "not-attempted"},
      };
      try {
        emailResults = await sendReportEmails(reportId, report, moderationResult);
      } catch (error) {
        emailResults = {
          owner: {status: "failed"},
          reporter: {status: "failed"},
        };
        console.error("onReportCreated email failed", {
          reportId,
          message: error instanceof Error ? error.message : String(error),
        });
      }

      await event.data.ref.set({
        status: "reviewing",
        reviewDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
        reportCountAtCreation: moderationResult.reportCount,
        autoQuarantined: moderationResult.quarantined,
        moderatorUids,
        emailResults,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
);


const lifecycle = require("./community-lifecycle").createLifecycle({db, admin, HttpsError});
exports.leaveCommunity = onCall({region: "europe-west1"}, lifecycle.leave);
exports.recordCommunityMembershipEvent = onDocumentWrittenWithAuthContext({
  region: "europe-west1", document: "communities/{communityId}/members/{memberId}", retry: true,
}, lifecycle.membershipChanged);
exports.processCommunityEliminations = onSchedule({
  region: "europe-west1", schedule: "every 1 minutes", maxInstances: 1, timeZone: "Etc/UTC", timeoutSeconds: 540,
}, lifecycle.sweep);

// Deterministic message ID keeps the in-app notice unique across trigger retries.
exports.notifyOnCommunitySettingsChanged = onDocumentWritten({
  region: "europe-west1", document: "communities/{communityId}", retry: true,
}, async event => {
  if (!event.data?.before.exists || !event.data?.after.exists) return;
  const before = event.data.before.data(), after = event.data.after.data();
  const changes = changedSettings(before, after);
  if (!changes.length) return;
  const ref = event.data.after.ref;
  const id = `settings-${require("node:crypto").createHash("sha256").update(event.id).digest("hex")}`;
  const body = `Paramètres modifiés : ${changes.join(", ")}. Consulte les informations de la communauté.`;
  await ref.collection("messages").doc(id).set({id, type: "system", systemEvent: "settingsChanged",
    senderUid: "__system__", senderPseudo: "", text: body,
    createdAt: admin.firestore.Timestamp.fromDate(new Date(event.time)), moderationStatus: "visible", reportCount: 0});
  const members = await ref.collection("members").get();
  for (const member of members.docs) {
    await sendPushToUser(member.id, {title: after.name || "Paramètres de la communauté", body,
      data: {destination: "communityDiscussion", communityId: event.params.communityId, type: "communitySettingsChanged"}});
  }
});
