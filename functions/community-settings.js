const {validateSchedule, isRankingActive} = require('./community-schedule');
function createSettingsHandlers({db, admin, HttpsError}) {
  const communityId = request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Connexion requise.');
    const id = request.data?.communityId;
    if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw new HttpsError('invalid-argument', 'Communauté invalide.');
    return id;
  };
  return {
    updateCommunitySettings: async request => {
      const id = communityId(request), data = request.data;
      const hasEliminationMode = Object.prototype.hasOwnProperty.call(data, 'eliminationMode');
      const hasRankingSchedule = Object.prototype.hasOwnProperty.call(data, 'rankingSchedule');
      if (typeof data.isPublic !== 'boolean' || (hasEliminationMode && typeof data.eliminationMode !== 'boolean') ||
          !Number.isInteger(data.responseTimeSeconds) || data.responseTimeSeconds < 1 || data.responseTimeSeconds > 604800) {
        throw new HttpsError('invalid-argument', 'Paramètres invalides : délai de 1 seconde à 7 jours.');
      }
      let rankingSchedule;
      if (hasRankingSchedule) {
        try { rankingSchedule = validateSchedule(data.rankingSchedule); } catch (e) { throw new HttpsError('invalid-argument', e.message); }
      }
      const ref = db.collection('communities').doc(id);
      await db.runTransaction(async tx => {
        const snapshot = await tx.get(ref);
        if (!snapshot.exists || snapshot.data().adminUid !== request.auth.uid) throw new HttpsError('permission-denied', 'Seul l’administrateur peut modifier les paramètres.');
        // Older clients omit settings they do not understand. Preserve those
        // fields rather than rejecting the request or resetting newer choices.
        tx.update(ref, {isPublic: data.isPublic, responseTimeSeconds: data.responseTimeSeconds,
          ...(hasEliminationMode ? {eliminationMode: data.eliminationMode} : {}),
          ...(hasRankingSchedule ? {rankingSchedule} : {})});
      });
      return {updated: true};
    },
    applyExpiredTorpillePenalty: async request => {
      const id = communityId(request), uid = request.auth.uid;
      const ref = db.collection('communities').doc(id), memberRef = ref.collection('members').doc(uid);
      return db.runTransaction(async tx => {
        const [community, member] = await Promise.all([tx.get(ref), tx.get(memberRef)]);
        if (!community.exists || !member.exists) throw new HttpsError('permission-denied', 'Adhésion requise.');
        if (!isRankingActive(community.data().rankingSchedule)) return {applied: false};
        const pendingId = member.data().pendingTorpilleId;
        if (!pendingId) return {applied: false};
        const torpRef = ref.collection('torpilles').doc(pendingId), torp = await tx.get(torpRef);
        const t = torp.data();
        if (!t || t.toUid !== uid || t.responseRequired === false || t.responded || t.penaltyApplied ||
            !t.deadlineAt || t.deadlineAt.toMillis() > Date.now()) return {applied: false};
        if (t.targetMembershipCreatedAt && !member.createTime.isEqual(t.targetMembershipCreatedAt)) return {applied: false};
        tx.update(torpRef, {penaltyApplied: true});
        tx.update(memberRef, {xpInCommunity: admin.firestore.FieldValue.increment(-10)});
        return {applied: true};
      });
    },
  };
}
module.exports = {createSettingsHandlers};
