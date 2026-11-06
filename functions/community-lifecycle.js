const {isRankingActive} = require("./community-schedule");
const {createHash} = require("node:crypto");

function membershipEventId(member, suffix) {
  const time = member.createTime;
  return `membership-${createHash("sha256").update(`${member.ref.path}:${time.seconds}:${time.nanoseconds}`).digest("hex")}-${suffix}`;
}
function noticeText(pseudo, kind) {
  const name = pseudo ? `@${pseudo}` : "Un membre";
  if (kind === "joined") return `${name} a rejoint la communauté.`;
  if (kind === "left") return `${name} a quitté la communauté.`;
  if (kind === "eliminated") return `${name} a été expulsé : délai de réponse dépassé.`;
  return `${name} a été expulsé de la communauté.`;
}
function createLifecycle({db, admin, HttpsError}) {
  const fv = () => admin.firestore.FieldValue;
  const now = () => admin.firestore.Timestamp.now();
  function notice(tx, community, member, kind, timestamp = now()) {
    const id = membershipEventId(member, kind === "joined" ? "joined" : "exit");
    tx.set(community.collection("messages").doc(id), {
      id, type: "system", systemEvent: kind, senderUid: "__system__", senderPseudo: "",
      text: noticeText(member.data().pseudo || "", kind), createdAt: timestamp,
      moderationStatus: "visible", reportCount: 0,
    });
  }
  async function removalContext(tx, community, member) {
    const uid = member.id;
    const user = await tx.get(db.collection("users").doc(uid));
    let successor = null;
    let requests = [];
    if (community.data().adminUid === uid) {
      const members = await tx.get(community.ref.collection("members"));
      successor = members.docs.filter(m => m.id !== uid).sort((a, b) =>
        a.createTime.toMillis() - b.createTime.toMillis() || a.id.localeCompare(b.id))[0] || null;
      if (successor) requests = (await tx.get(db.collection("communityJoinRequests")
          .where("communityId", "==", community.id))).docs.filter(d => d.data().status === "pending");
    }
    return {user, successor, requests};
  }
  function remove(tx, community, member, context, kind) {
    if (context.successor) {
      tx.update(community.ref, {adminUid: context.successor.id});
      for (const request of context.requests) tx.update(request.ref, {adminUid: context.successor.id});
    }
    notice(tx, community.ref, member, kind);
    tx.delete(member.ref);
    cleanProfile(tx, context.user, community.id);
  }
  function cleanProfile(tx, user, communityId) {
    if (!user.exists) return;
      const profile = user.data();
      const xp = {...(profile.communityXP || {})};
      delete xp[communityId];
      const total = Object.values(xp).reduce((sum, value) => sum + (Number(value) || 0), 0);
      tx.update(user.ref, {communityIds: fv().arrayRemove(communityId),
        pinnedCommunityIds: fv().arrayRemove(communityId), communityXP: xp, xpTotal: total, xptotal: total});
  }

  async function expire(queueRef) {
    return db.runTransaction(async tx => {
      const task = await tx.get(queueRef);
      if (!task.exists || task.data().deadlineAt.toMillis() > Date.now()) return "not-due";
      const {communityId, torpilleId} = task.data();
      const communityRef = db.collection("communities").doc(communityId);
      const [community, torpille] = await Promise.all([
        tx.get(communityRef), tx.get(communityRef.collection("torpilles").doc(torpilleId)),
      ]);
      if (!community.exists || !torpille.exists || community.data().eliminationMode !== true ||
          torpille.data().eliminationMode !== true || torpille.data().responded === true) {
        tx.delete(queueRef); return "cancelled";
      }
      if (!isRankingActive(community.data().rankingSchedule)) {
        // Defer the queue task too, so closed communities do not starve other due tasks.
        tx.update(queueRef, {deadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000)});
        return "outside-schedule";
      }
      const data = torpille.data();
      if (data.deadlineAt.toMillis() > Date.now()) return "not-due";
      const member = await tx.get(communityRef.collection("members").doc(data.toUid));
      if (!member.exists || !data.targetMembershipCreatedAt ||
          !member.createTime.isEqual(data.targetMembershipCreatedAt)) {
        tx.delete(queueRef); return "membership-changed";
      }
      const context = await removalContext(tx, community, member);
      if (community.data().adminUid === member.id && !context.successor) {
        tx.update(communityRef, {eliminationMode: false});
        tx.update(torpille.ref, {eliminationProcessed: true});
        tx.delete(queueRef); return "sole-admin-protected";
      }
      remove(tx, community, member, context, "eliminated");
      tx.update(torpille.ref, {eliminationProcessed: true});
      tx.delete(queueRef);
      return "eliminated";
    });
  }
  async function leave(request) {
    const uid = request.auth?.uid;
    const id = request.data?.communityId;
    if (!uid) throw new HttpsError("unauthenticated", "Connexion requise.");
    if (typeof id !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw new HttpsError("invalid-argument", "Communauté invalide.");
    const ref = db.collection("communities").doc(id);
    return db.runTransaction(async tx => {
      const [community, member] = await Promise.all([tx.get(ref), tx.get(ref.collection("members").doc(uid))]);
      if (!community.exists || !member.exists) return {status: "left"};
      const context = await removalContext(tx, community, member);
      if (community.data().adminUid === uid && !context.successor) {
        throw new HttpsError("failed-precondition", "Tu es le dernier membre : supprime la communauté depuis ses paramètres.");
      }
      remove(tx, community, member, context, "left");
      return {status: "left"};
    });
  }
  async function membershipChanged(event) {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before || !after || before.exists === after.exists) return;
    const member = after.exists ? after : before;
    const communityRef = member.ref.parent.parent;
    const kind = after.exists ? "joined" : (event.authId === member.id ? "left" : "expelled");
    const messageRef = communityRef.collection("messages").doc(membershipEventId(member, after.exists ? "joined" : "exit"));
    await db.runTransaction(async tx => {
      const [community, existing] = await Promise.all([tx.get(communityRef), tx.get(messageRef)]);
      if (!community.exists || existing.exists) return;
      let removedUser = null;
      if (!after.exists) {
        const current = await tx.get(member.ref);
        if (!current.exists) removedUser = await tx.get(db.collection("users").doc(member.id));
      }
      notice(tx, communityRef, member, kind, after.exists ? member.createTime : admin.firestore.Timestamp.fromDate(new Date(event.time)));
      if (removedUser) cleanProfile(tx, removedUser, community.id);
    });
  }
  async function sweep() {
    const due = await db.collection("communityEliminationQueue").where("deadlineAt", "<=", now()).limit(200).get();
    for (const task of due.docs) await expire(task.ref);
  }
  return {expire, leave, membershipChanged, sweep};
}
module.exports = {createLifecycle, noticeText, membershipEventId};
