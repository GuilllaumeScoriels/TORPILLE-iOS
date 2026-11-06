const {randomBytes} = require("node:crypto");
const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function normalizeCode(value) {
  return typeof value === "string" ? value.replace(/[\s-]/g, "").toUpperCase() : "";
}
function newCode() {
  // 32 symbols divide the 256 possible byte values evenly.
  return Array.from(randomBytes(8), byte => alphabet[byte % alphabet.length]).join("");
}

function createInvitationHandlers(db, HttpsError, generate = newCode) {
  function authenticated(request) {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Connecte-toi pour utiliser une invitation.");
    if (request.auth.token?.email_verified !== true) throw new HttpsError("failed-precondition", "Vérifie ton adresse e-mail avant de continuer.");
    return request.auth.uid;
  }
  return {
    async getCommunityInvitationCode(request) {
      const uid = authenticated(request);
      const id = request.data?.communityId;
      if (typeof id !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw new HttpsError("invalid-argument", "Communauté invalide.");
      const community = db.collection("communities").doc(id);
      const invitation = db.collection("communityInvitations").doc(id);
      for (let attempt = 0; attempt < 5; attempt++) {
        const code = generate();
        const result = await db.runTransaction(async transaction => {
          const [group, member, saved] = await Promise.all([
            transaction.get(community), transaction.get(community.collection("members").doc(uid)), transaction.get(invitation),
          ]);
          if (!group.exists) throw new HttpsError("not-found", "Cette communauté n’existe plus.");
          if (!member.exists && group.data().adminUid !== uid) throw new HttpsError("permission-denied", "Tu dois appartenir à cette communauté.");
          if (saved.exists) return {code: saved.data().code};
          const mapping = db.collection("communityInvitationCodes").doc(code);
          if ((await transaction.get(mapping)).exists) return null;
          transaction.create(mapping, {communityId: id});
          transaction.create(invitation, {code});
          return {code};
        });
        if (result) return result;
      }
      throw new HttpsError("unavailable", "Impossible de générer le code. Réessaie.");
    },
    async resolveCommunityInvitationCode(request) {
      const uid = authenticated(request);
      const code = normalizeCode(request.data?.code);
      if (!/^[A-Z0-9]{8}$/.test(code)) throw new HttpsError("invalid-argument", "Saisis le code de 8 caractères de la communauté.");
      const mapping = await db.collection("communityInvitationCodes").doc(code).get();
      if (!mapping.exists) throw new HttpsError("not-found", "Code d’invitation introuvable.");
      const id = mapping.data().communityId;
      const group = db.collection("communities").doc(id);
      const [community, banned] = await Promise.all([group.get(), group.collection("banned").doc(uid).get()]);
      if (!community.exists) throw new HttpsError("not-found", "Cette communauté n’existe plus.");
      if (banned.exists) throw new HttpsError("permission-denied", "Tu ne peux pas rejoindre cette communauté.");
      // Joining still goes through requestCommunityMembership (private approval, profile, bans).
      return {communityId: id};
    },
  };
}
module.exports = {createInvitationHandlers, normalizeCode, newCode};
