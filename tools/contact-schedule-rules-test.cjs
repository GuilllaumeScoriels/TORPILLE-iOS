// Run against a local demo Firestore emulator. Dependencies may be installed outside the app.
const {createRequire} = require('node:module');
const sdk = process.env.RULE_TEST_PACKAGE ? createRequire(process.env.RULE_TEST_PACKAGE) : require;
const {initializeTestEnvironment, assertFails, assertSucceeds} = sdk('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, Timestamp} = sdk('firebase/firestore');
const fs = require('node:fs');
(async () => {
  const env = await initializeTestEnvironment({projectId: 'demo-torpille-schedule', firestore: {host: '127.0.0.1', port: 8186, rules: fs.readFileSync('firestore.rules', 'utf8')}});
  try {
    await env.withSecurityRulesDisabled(async context => {
      const db = context.firestore();
      for (const uid of ['admin', 'member']) {
        await setDoc(doc(db, `users/${uid}`), {uid, firstName: 'Test', lastName: 'Test', pseudo: uid,
          profileIcon: '🐟', communityIds: ['c1'], termsAcceptedAt: Timestamp.now(), moderationRulesAcceptedAt: Timestamp.now()});
        await setDoc(doc(db, `communities/c1/members/${uid}`), {uid, pseudo: uid, xpInCommunity: 0});
      }
      await setDoc(doc(db, 'communities/c1'), {id: 'c1', name: 'Test', adminUid: 'admin', createdAt: Timestamp.now(), isPublic: true, responseTimeSeconds: 3600,
        rankingSchedule: {fullTime: false, timeZone: 'UTC', weekly: [{day: 1, startMinute: 540, endMinute: 600}], dates: []}});
      await setDoc(doc(db, 'communities/c1/torpilles/t1'), {id: 't1', fromUid: 'admin', toUid: 'member', responded: true, responseRequired: false, isPublished: false});
      await setDoc(doc(db, 'contactDiscovery/member'), {phoneHash: 'private'});
      await setDoc(doc(db, 'contactDiscoveryLimits/member'), {day: '2026-10-14', used: 1});
    });
    const member = env.authenticatedContext('member', {email_verified: true}).firestore();
    const admin = env.authenticatedContext('admin', {email_verified: true}).firestore();
    await assertFails(getDoc(doc(member, 'contactDiscovery/member')));
    await assertFails(setDoc(doc(member, 'contactDiscovery/member'), {phoneHash: 'fake'}));
    await assertFails(getDoc(doc(member, 'contactDiscoveryLimits/member')));
    await assertFails(setDoc(doc(member, 'contactDiscoveryLimits/member'), {used: 0}));
    await assertFails(setDoc(doc(member, 'communities/c1/torpilles/new'), {id: 'new', fromUid: 'member', toUid: 'admin'}));
    // Compatibility with Android / iOS < 1.0.6 (see firestore.rules): member fields stay client-writable.
    await assertSucceeds(updateDoc(doc(member, 'communities/c1/members/member'), {xpInCommunity: 100}));
    await assertSucceeds(updateDoc(doc(member, 'communities/c1/members/admin'), {pendingTorpilleId: 'legacy'}));
    await assertSucceeds(updateDoc(doc(member, 'communities/c1/members/member'), {lastSeenMessageAt: Timestamp.now()}));
    await assertFails(updateDoc(doc(admin, 'communities/c1'), {rankingSchedule: {fullTime: true}}));
    await assertFails(updateDoc(doc(admin, 'communities/c1'), {adminUid: 'member', rankingSchedule: {fullTime: true}}));
    await assertSucceeds(updateDoc(doc(admin, 'communities/c1'), {isPublic: false}));
    // Compatibility: legacy clients answer torpilles and apply penalties directly.
    await assertSucceeds(updateDoc(doc(member, 'communities/c1/torpilles/t1'), {responded: true, respondedAt: Timestamp.now(), nextToUid: 'admin'}));
    await assertSucceeds(updateDoc(doc(member, 'communities/c1/torpilles/t1'), {penaltyApplied: true}));
    await assertSucceeds(getDoc(doc(member, 'communities/c1')));
    await assertSucceeds(updateDoc(doc(admin, 'communities/c1/torpilles/t1'), {isPublished: true, publishedAt: Timestamp.now(), publishedByUid: 'admin', publishedByPseudo: 'Admin', communityName: 'Test'}));
    await assertSucceeds(updateDoc(doc(member, 'communities/c1/torpilles/t1'), {isPublished: false}));
    console.log('16 Firestore authorization checks passed.');
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
