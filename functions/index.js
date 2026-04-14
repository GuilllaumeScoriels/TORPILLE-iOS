const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

admin.initializeApp();

const db = admin.firestore();
const storage = admin.storage();
const IOS_BUNDLE_ID = process.env.IOS_BUNDLE_ID || "com.torpille.ios";

function asInt64(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  return 0;
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

async function deleteMembershipsForUser(uid) {
  const communitiesSnapshot = await db.collection("communities").get();
  const references = [];

  for (const communityDocument of communitiesSnapshot.docs) {
    const memberRef = communityDocument.ref.collection("members").doc(uid);
    const memberSnapshot = await memberRef.get();
    if (memberSnapshot.exists) {
      references.push(memberRef);
    }
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
  return typeof mode === "string" ? mode : "mentionsOnly";
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

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title,
      body,
    },
    data: Object.fromEntries(
      Object.entries(data || {}).map(([key, value]) => [key, String(value)])
    ),
    apns: {
      headers: {
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-topic": IOS_BUNDLE_ID,
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  });

  const invalidTokens = [];
  response.responses.forEach((result, index) => {
    if (!result.success && result.error) {
      console.error("push send failure", {
        uid,
        token: tokens[index],
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
  await deleteCollectionDocuments(communityRef.collection("messages"));
  await deleteCollectionDocuments(communityRef.collection("torpilles"));
  await deleteCollectionDocuments(communityRef.collection("savedMessages"));
  await deleteCollectionDocuments(communityRef.collection("allowlist"));
  await deleteCollectionDocuments(communityRef.collection("banned"));
  await deleteCollectionDocuments(communityRef.collection("members"));
  await communityRef.delete();
}

exports.deleteMyAccount = onCall({region: "europe-west1"}, async (request) => {
  let step = "auth-check";

  try {
    const uid = request.auth && request.auth.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    step = "load-auth-user";
    const authUser = await getAuthUserIfExists(uid);
    const authEmail = authUser && authUser.email ? authUser.email : "";

    step = "load-user";
    const userRef = db.collection("users").doc(uid);
    const userSnapshot = await userRef.get();
    const userData = userSnapshot.data() || {};
    const pseudoKey = typeof userData.pseudoKey === "string" ? userData.pseudoKey : "";
    const photoUrl = typeof userData.photoUrl === "string" ? userData.photoUrl : "";

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
      } else {
        step = `delete-community-tree:${communityRef.id}`;
        await deleteCommunityTree(communityRef);
      }
    }

    step = "delete-memberships";
    await deleteMembershipsForUser(uid);

    step = "delete-notification-preferences";
    const notificationPreferencesSnapshot = await userRef.collection("notificationPreferences").get();
    await deleteReferences(notificationPreferencesSnapshot.docs.map((document) => document.ref));

    if (pseudoKey) {
      step = "delete-pseudo";
      await db.collection("pseudos").doc(pseudoKey).delete().catch(() => {});
    }

    if (userSnapshot.exists) {
      step = "delete-user-document";
      await userRef.delete();
    }

    if (photoUrl) {
      step = "delete-profile-photo";
      await deleteFileFromUrl(photoUrl).catch(() => {});
    }

    step = "delete-auth-user";
    await admin.auth().deleteUser(uid);

    step = "verify-auth-user-deleted";
    const remainingUidUser = await getAuthUserIfExists(uid);
    if (remainingUidUser) {
      throw new Error(`Firebase Auth user still exists for uid ${uid}`);
    }

    step = "verify-auth-email-deleted";
    const remainingEmailUser = await getAuthUserByEmailIfExists(authEmail);
    if (remainingEmailUser) {
      if (remainingEmailUser.uid === uid) {
        step = "delete-auth-user-by-email";
        await admin.auth().deleteUser(remainingEmailUser.uid);
      } else {
        throw new Error(`Email ${authEmail} still belongs to uid ${remainingEmailUser.uid}`);
      }
    }

    return {deleted: true};
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("deleteMyAccount failed", {step, message, error});
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
      const body = senderPseudo ?
        `@${senderPseudo} t'a torpille dans ${communityName}.` :
        `Tu as recu une torpille dans ${communityName}.`;

      const result = await sendPushToUser(toUid, {
        title: communityName,
        body,
        data: {
          destination: "notificationCenter",
          communityId,
          type: "torpille",
          torpilleId: event.params.torpilleId,
        },
      });
      console.log("notifyOnTorpilleCreated", {communityId, toUid, result});
    }
);

exports.notifyOnMessageCreated = onDocumentCreated(
    {
      region: "europe-west1",
      document: "communities/{communityId}/messages/{messageId}",
    },
    async (event) => {
      const message = event.data && event.data.data();
      if (!message) {
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
      const targetUid = typeof message.taggedUid === "string" ? message.taggedUid.trim() : "";
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
