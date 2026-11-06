// Backward compatibility of firestore.rules with clients that predate server-side torpilles
// (Android, iOS < 1.0.6): they create/answer torpilles and adjust XP directly in Firestore.
// Run against a local demo Firestore emulator (FIRESTORE_EMULATOR_HOST, default 127.0.0.1:8080).
const {createRequire} = require('node:module');
const sdk = process.env.RULE_TEST_PACKAGE ? createRequire(process.env.RULE_TEST_PACKAGE) : require;
const {initializeTestEnvironment, assertFails, assertSucceeds} = sdk('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, writeBatch, runTransaction, deleteField, increment, Timestamp} = sdk('firebase/firestore');
const fs = require('node:fs');

const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-torpille-legacy',
    firestore: {host, port: Number(port), rules: fs.readFileSync('firestore.rules', 'utf8')},
  });
  let checks = 0;
  const ok = async promise => { await assertSucceeds(promise); checks++; };
  const ko = async promise => { await assertFails(promise); checks++; };
  try {
    const deadline = Timestamp.fromMillis(Date.now() - 60_000);
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      for (const uid of ['admin', 'member', 'third', 'outsider']) {
        await setDoc(doc(db, `users/${uid}`), {uid, firstName: 'Test', lastName: 'Test', pseudo: uid,
          profileIcon: '🐟', communityIds: ['c1', 'elim'], termsAcceptedAt: Timestamp.now(), moderationRulesAcceptedAt: Timestamp.now()});
        if (uid === 'outsider') continue;
        for (const c of ['c1', 'elim']) {
          await setDoc(doc(db, `communities/${c}/members/${uid}`), {uid, pseudo: uid, xpInCommunity: 50});
        }
      }
      await setDoc(doc(db, 'communities/c1'), {id: 'c1', name: 'Classique', adminUid: 'admin', createdAt: Timestamp.now(),
        isPublic: true, responseTimeSeconds: 3600});
      await setDoc(doc(db, 'communities/elim'), {id: 'elim', name: 'Élimination', adminUid: 'admin', createdAt: Timestamp.now(),
        isPublic: true, responseTimeSeconds: 3600, eliminationMode: true});
      await setDoc(doc(db, 'communities/c1/torpilles/t1'), {id: 't1', communityId: 'c1', fromUid: 'admin', toUid: 'member',
        taggedPseudo: 'member', responded: false, deadlineAt: deadline, createdAt: Timestamp.now()});
      await setDoc(doc(db, 'communities/c1/members/member'), {uid: 'member', pseudo: 'member', xpInCommunity: 50,
        pendingTorpilleId: 't1', pendingDeadlineAt: deadline, pendingFromPseudo: 'admin'});
    });

    const member = env.authenticatedContext('member', {email_verified: true}).firestore();
    const admin = env.authenticatedContext('admin', {email_verified: true}).firestore();

    // 1. Legacy reply pre-batch (iOS 1.0.5 respondWithVideo): torpille + own member, atomically.
    const batch = writeBatch(member);
    batch.update(doc(member, 'communities/c1/torpilles/t1'), {responded: true, respondedAt: Timestamp.now(), nextToUid: 'third'});
    batch.update(doc(member, 'communities/c1/members/member'), {pendingTorpilleId: deleteField(), pendingDeadlineAt: deleteField(),
      pendingFromPseudo: deleteField(), lastRespondedAt: Timestamp.now(), xpInCommunity: increment(5)});
    await ok(batch.commit());

    // 2. Legacy expired-penalty transaction.
    await ok(runTransaction(member, async tx => {
      const torp = doc(member, 'communities/c1/torpilles/t1');
      await tx.get(torp);
      tx.update(torp, {penaltyApplied: true});
      tx.update(doc(member, 'communities/c1/members/member'), {xpInCommunity: increment(-10)});
    }));

    // 3. Legacy client-side torpille creation + marking the target as pending.
    const torpille = {id: 't2', fromUid: 'member', fromPseudo: 'member', toUid: 'third', communityId: 'c1', taggedPseudo: 'third',
      videoPath: 'communities/c1/videos/x.mov', tagX: 0.5, tagY: 0.2, responded: false, moderationStatus: 'visible', reportCount: 0,
      createdAt: Timestamp.now(), deadlineAt: Timestamp.fromMillis(Date.now() + 3600_000)};
    await ok(setDoc(doc(member, 'communities/c1/torpilles/t2'), torpille));
    await ok(updateDoc(doc(member, 'communities/c1/members/third'), {pendingTorpilleId: 't2', pendingFromPseudo: 'member', lastTorpilledAt: Timestamp.now()}));

    // 4. Elimination communities stay server-only (new feature, not used by legacy clients).
    await ko(setDoc(doc(member, 'communities/elim/torpilles/t3'), {...torpille, id: 't3', communityId: 'elim'}));
    // Torpilles still cannot be forged in someone else's name.
    await ko(setDoc(doc(member, 'communities/c1/torpilles/t4'), {...torpille, id: 't4', fromUid: 'third'}));

    // 5. Legacy community settings write (admin) still works; schedules only via the server.
    await ok(updateDoc(doc(admin, 'communities/c1'), {isPublic: false, responseTimeSeconds: 7200}));
    await ko(updateDoc(doc(admin, 'communities/c1'), {rankingSchedule: {fullTime: true}}));
    await ko(updateDoc(doc(member, 'communities/c1'), {isPublic: true}));

    // A complete verified profile is insufficient without an actual community membership.
    const outsider = env.authenticatedContext('outsider', {email_verified: true}).firestore();
    await ko(updateDoc(doc(outsider, 'communities/c1/torpilles/t1'), {responded: false}));
    await ko(setDoc(doc(outsider, 'communities/c1/torpilles/outsider-new'), {...torpille,
      id: 'outsider-new', fromUid: 'outsider'}));

    console.log(`${checks} legacy compatibility checks passed.`);
  } finally {
    await env.cleanup();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
