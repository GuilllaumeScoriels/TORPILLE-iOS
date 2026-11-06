const {parsePhoneNumberFromString, isSupportedCountry} = require('libphonenumber-js/max');
const {createHash} = require('node:crypto');

function normalizePhone(value, country) {
  if (typeof value !== 'string' || value.length > 80) return null;
  const clean = value.trim().replace(/^00/, '+');
  const phone = parsePhoneNumberFromString(clean, {defaultCountry: country, extract: false});
  return phone && !phone.ext && phone.isValid() ? phone.number : null;
}
const digest = (phone) => createHash('sha256').update(phone).digest('hex');
function createContactHandlers(db, auth, HttpsError) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  async function identity(request) {
    if (!request.auth) fail('unauthenticated', 'Connecte-toi pour retrouver tes contacts.');
    const user = await auth.getUser(request.auth.uid);
    if (user.disabled) fail('permission-denied', 'Compte indisponible.');
    return user;
  }
  const preference = (uid) => db.collection('contactDiscovery').doc(uid);
  async function state(user) {
    const snapshot = await preference(user.uid).get();
    return {phoneNumber: user.phoneNumber || '', discoverable: !!user.phoneNumber && snapshot.data()?.phoneHash === digest(user.phoneNumber)};
  }
  return {
    getContactDiscoverySettings: async (request) => state(await identity(request)),
    setContactDiscoverySettings: async (request) => {
      const user = await identity(request);
      if (typeof request.data?.discoverable !== 'boolean') fail('invalid-argument', 'Choisis une préférence de visibilité.');
      if (!request.data.discoverable) {
        await preference(user.uid).delete();
      } else {
        if (!user.phoneNumber) fail('failed-precondition', 'Vérifie ton numéro par SMS avant de devenir visible.');
        await preference(user.uid).set({phoneHash: digest(user.phoneNumber)});
      }
      return state(user);
    },
    findPhoneContacts: async (request) => {
      const me = await identity(request);
      if (!me.phoneNumber) fail('failed-precondition', 'Vérifie ton numéro par SMS avant de rechercher des contacts.');
      const {numbers, country} = request.data || {};
      if (!Array.isArray(numbers) || numbers.length < 1 || numbers.length > 100 || numbers.some(n => typeof n !== 'string' || n.length > 80)) {
        fail('invalid-argument', 'Envoie entre 1 et 100 numéros.');
      }
      if (typeof country !== 'string' || !isSupportedCountry(country)) fail('invalid-argument', 'Choisis le pays des numéros locaux (BE, FR, SE…).');
      // Count submitted numbers, including invalid/duplicate inputs, without retaining them.
      const quota = db.collection('contactDiscoveryLimits').doc(me.uid);
      const day = new Date().toISOString().slice(0, 10);
      await db.runTransaction(async tx => {
        const old = (await tx.get(quota)).data();
        const used = old?.day === day ? old.used : 0;
        if (used + numbers.length > 2000) fail('resource-exhausted', 'Limite quotidienne atteinte. Réessaie demain.');
        tx.set(quota, {day, used: used + numbers.length});
      });
      const phones = [...new Set(numbers.map(n => normalizePhone(n, country)).filter(Boolean))];
      if (!phones.length) return {profiles: []};
      const found = await auth.getUsers(phones.map(phoneNumber => ({phoneNumber})));
      const profiles = [];
      for (const user of found.users) {
        if (user.uid === me.uid || user.disabled || !user.phoneNumber) continue;
        const [consent, profile, blocked, blockedBy] = await db.getAll(
          preference(user.uid), db.doc(`users/${user.uid}`),
          db.doc(`users/${me.uid}/blockedUsers/${user.uid}`), db.doc(`users/${user.uid}/blockedUsers/${me.uid}`));
        if (consent.data()?.phoneHash !== digest(user.phoneNumber) || !profile.exists || blocked.exists || blockedBy.exists) continue;
        const p = profile.data();
        // Only public identity is returned; never echo phone numbers or private profile fields.
        if (!p.pseudo) continue;
        profiles.push({uid: user.uid, pseudo: p.pseudo, photoUrl: p.photoUrl || null,
          profileIcon: p.profileIcon || null, friendsCount: p.friendsCount || 0});
      }
      return {profiles};
    },
  };
}
module.exports = {normalizePhone, digest, createContactHandlers};
