// Emoji reactions on community messages. Run against a local demo Firestore emulator:
//   firebase emulators:exec --only firestore --project demo-torpille-reactions "node tools/reaction-rules-test.cjs"
// (the emulator port is read from FIRESTORE_EMULATOR_HOST when set, else 127.0.0.1:8080).
// Dependencies may be installed outside the app (RULE_TEST_PACKAGE, as for the other rules tests).
const {createRequire} = require('node:module');
const sdk = process.env.RULE_TEST_PACKAGE ? createRequire(process.env.RULE_TEST_PACKAGE) : require;
const {initializeTestEnvironment, assertFails, assertSucceeds} = sdk('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, deleteField, Timestamp} = sdk('firebase/firestore');
const fs = require('node:fs');

const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-torpille-reactions',
    firestore: {host, port: Number(port), rules: fs.readFileSync('firestore.rules', 'utf8')},
  });
  let checks = 0;
  const ok = async promise => { await assertSucceeds(promise); checks++; };
  const ko = async promise => { await assertFails(promise); checks++; };
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      for (const uid of ['admin', 'member', 'outsider']) {
        await setDoc(doc(db, `users/${uid}`), {uid, firstName: 'Test', lastName: 'Test', pseudo: uid,
          profileIcon: '🐟', communityIds: uid === 'outsider' ? [] : ['c1'],
          termsAcceptedAt: Timestamp.now(), moderationRulesAcceptedAt: Timestamp.now()});
      }
      for (const uid of ['admin', 'member']) {
        await setDoc(doc(db, `communities/c1/members/${uid}`), {uid, pseudo: uid, xpInCommunity: 0});
      }
      await setDoc(doc(db, 'communities/c1'), {id: 'c1', name: 'Test', adminUid: 'admin', createdAt: Timestamp.now(),
        isPublic: true, responseTimeSeconds: 3600});
      await setDoc(doc(db, 'communities/c1/messages/m1'), {id: 'm1', type: 'text', senderUid: 'admin', senderPseudo: 'admin',
        text: 'Salut', createdAt: Timestamp.now(), moderationStatus: 'visible', reportCount: 0});
      await setDoc(doc(db, 'communities/c1/messages/m2'), {id: 'm2', type: 'video', senderUid: 'admin', senderPseudo: 'admin',
        torpilleId: 'm2', taggedUid: 'member', taggedPseudo: 'member', createdAt: Timestamp.now(),
        moderationStatus: 'visible', reportCount: 0, reactions: {admin: '🔥'}});
    });

    const member = env.authenticatedContext('member', {email_verified: true}).firestore();
    const outsider = env.authenticatedContext('outsider', {email_verified: true}).firestore();
    const unverified = env.authenticatedContext('member', {email_verified: false}).firestore();
    const m1 = db => doc(db, 'communities/c1/messages/m1');
    const m2 = db => doc(db, 'communities/c1/messages/m2');

    // Own reaction: add, change, remove (dotted field path, as the iOS client writes it).
    await ok(updateDoc(m1(member), {'reactions.member': '👍'}));
    await ok(updateDoc(m1(member), {'reactions.member': '❤️'}));
    await ok(updateDoc(m1(member), {'reactions.member': deleteField()}));
    // Reacting to a torpille video message that already has someone else's reaction.
    await ok(updateDoc(m2(member), {'reactions.member': '😂'}));

    // Someone else's entry, unknown emoji, free text, non-string, extra fields.
    await ko(updateDoc(m2(member), {'reactions.admin': deleteField()}));
    await ko(updateDoc(m2(member), {'reactions.admin': '👍'}));
    await ko(updateDoc(m1(member), {'reactions.member': '🍆'}));
    await ko(updateDoc(m1(member), {'reactions.member': 'bonjour'}));
    await ko(updateDoc(m1(member), {'reactions.member': 1}));
    await ko(updateDoc(m1(member), {'reactions.member': '👍', text: 'modifié'}));
    // Replacing the whole map (would wipe others' reactions).
    await ko(updateDoc(m2(member), {reactions: {member: '👍'}}));
    await ko(updateDoc(m1(member), {reactions: 'x'}));

    // Non-members and unverified accounts.
    await ko(updateDoc(m1(outsider), {'reactions.outsider': '👍'}));
    await ko(updateDoc(m1(unverified), {'reactions.member': '👍'}));

    // Saving a message still works and is not mistaken for a reaction.
    await ok(updateDoc(m1(member), {savedAt: Timestamp.now(), savedByUid: 'member', savedByPseudo: 'member'}));

    console.log(`${checks} reaction authorization checks passed.`);
  } finally {
    await env.cleanup();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
