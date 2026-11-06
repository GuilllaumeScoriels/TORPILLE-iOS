// Run only with Auth and Firestore emulators; never against production.
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Local emulators required');
const assert = require('node:assert/strict');
process.env.GCLOUD_PROJECT = 'demo-torpille-elimination';
const admin = require('../functions/node_modules/firebase-admin');
const handlers = require('../functions/index');
const db = admin.firestore();
const {HttpsError} = require('node:module').createRequire(require.resolve('../functions/package.json'))('firebase-functions/v2/https');
const {createLifecycle} = require('../functions/community-lifecycle');
const lifecycle = createLifecycle({db, admin, HttpsError});
const Timestamp = admin.firestore.Timestamp;
let checks = 0;
const passed = name => { checks++; console.log('PASS '+name); };
async function member(community, uid) {
  await db.doc(`users/${uid}`).set({pseudo:uid, photoUrl:'https://example.com/p.png', termsAcceptedAt:Timestamp.now(), moderationRulesAcceptedAt:Timestamp.now(), communityIds:[community.id],pinnedCommunityIds:[community.id],communityXP:{[community.id]:25},xpTotal:25});
  const ref=community.collection('members').doc(uid);await ref.set({uid,pseudo:uid,xpInCommunity:25});return ref.get();
}
async function community(id, adminUid='admin', isPublic=true) {
  const ref=db.collection('communities').doc(id);await ref.set({id,name:id,adminUid,isPublic,eliminationMode:true,responseTimeSeconds:60,createdAt:Timestamp.now()});return ref;
}
async function task(c, m, id, extra={}) {
  const deadlineAt=Timestamp.fromMillis(Date.now()-10000);
  await c.collection('torpilles').doc(id).set({toUid:m.id,eliminationMode:true,responded:false,deadlineAt,targetMembershipCreatedAt:m.createTime,...extra});
  const q=db.collection('communityEliminationQueue').doc(id);await q.set({communityId:c.id,torpilleId:id,deadlineAt});return q;
}
(async()=>{
  const c=await community('ordinary');await member(c,'admin');const alice=await member(c,'alice');
  let q=await task(c,alice,'expired');assert.equal(await lifecycle.expire(q),'eliminated');
  assert.equal((await alice.ref.get()).exists,false);assert.equal((await c.collection('banned').doc('alice').get()).exists,false);
  let profile=(await db.doc('users/alice').get()).data();assert.deepEqual(profile.communityIds,[]);assert.deepEqual(profile.pinnedCommunityIds,[]);assert.equal(profile.xpTotal,0);
  let messages=await c.collection('messages').get();assert.equal(messages.size,1);assert.equal(messages.docs[0].data().type,'system');assert.match(messages.docs[0].data().text,/délai/);passed('expiration removes membership, clears profile and creates compact system event without a ban');
  assert.equal(await lifecycle.expire(q),'not-due');assert.equal((await c.collection('messages').get()).size,1);passed('retry is idempotent');
  const auth={uid:'alice',token:{email_verified:true}};
  assert.equal((await handlers.requestCommunityMembership.run({auth,data:{communityId:c.id}})).status,'joined');passed('public rejoin after elimination');
  const old=(await alice.ref.get());q=await task(c,old,'old-session');await old.ref.delete();await member(c,'alice');
  assert.equal(await lifecycle.expire(q),'membership-changed');assert.equal((await alice.ref.get()).exists,true);passed('old torpille cannot expel a new membership');
  q=await task(c,await alice.ref.get(),'answered',{responded:true});assert.equal(await lifecycle.expire(q),'cancelled');passed('timely response prevents elimination');
  q=await task(c,await alice.ref.get(),'disabled');await c.update({eliminationMode:false});assert.equal(await lifecycle.expire(q),'cancelled');passed('disabled mode cancels elimination');
  const privateC=await community('private','private-admin',false);await member(privateC,'private-admin');const b=await member(privateC,'bravo');
  q=await task(privateC,b,'private-expired');await lifecycle.expire(q);
  const request=await handlers.requestCommunityMembership.run({auth:{uid:'bravo',token:{email_verified:true}},data:{communityId:privateC.id}});
  assert.equal(request.status,'pending');assert.equal((await b.ref.get()).exists,false);
  await handlers.resolveCommunityJoinRequest.run({auth:{uid:'private-admin'},data:{requestId:'private_bravo',decision:'accepted'}});
  assert.equal((await b.ref.get()).exists,true);passed('private rejoin requires fresh administrator approval');
  const transfer=await community('transfer','captain');const captain=await member(transfer,'captain');await member(transfer,'successor');
  await db.doc('communityJoinRequests/pending-transfer').set({communityId:transfer.id,adminUid:'captain',status:'pending'});
  q=await task(transfer,captain,'admin-expired');assert.equal(await lifecycle.expire(q),'eliminated');
  assert.equal((await transfer.get()).data().adminUid,'successor');assert.equal((await db.doc('communityJoinRequests/pending-transfer').get()).data().adminUid,'successor');passed('administrator transfer includes pending private requests');
  const solo=await community('solo','solo-user');const sm=await member(solo,'solo-user');q=await task(solo,sm,'solo-expired');
  assert.equal(await lifecycle.expire(q),'sole-admin-protected');assert.equal((await solo.get()).data().eliminationMode,false);assert.equal((await sm.ref.get()).exists,true);passed('sole administrator is retained and mode disabled');
  await lifecycle.leave({auth:{uid:'alice'},data:{communityId:c.id}});assert.equal((await alice.ref.get()).exists,false);
  messages=await c.collection('messages').get();assert.ok(messages.docs.some(d=>d.data().systemEvent==='left'));passed('voluntary leave creates a distinct system notice');
  const eventC=await community('events');const em=await member(eventC,'event-user');
  const missing={exists:false};await lifecycle.membershipChanged({data:{before:missing,after:em},time:new Date().toISOString()});await lifecycle.membershipChanged({data:{before:missing,after:em},time:new Date().toISOString()});
  assert.equal((await eventC.collection('messages').get()).size,1);await em.ref.delete();
  await lifecycle.membershipChanged({data:{before:em,after:missing},authId:'admin',time:new Date().toISOString()});
  assert.equal((await eventC.collection('messages').get()).size,2);passed('join and manual expulsion triggers are deduplicated');
  // Only Storage is stubbed: these transaction tests use the real Firestore emulator.
  const storage=admin.storage();storage.bucket=()=>({name:'demo-bucket',file:()=>({exists:async()=>[true]})});
  const responseC=await community('response','respondent');const respondent=await member(responseC,'respondent');await member(responseC,'target');
  await task(responseC,respondent,'on-time',{deadlineAt:Timestamp.fromMillis(Date.now()+60000)});
  const data={communityId:responseC.id,senderPseudo:'respondent',taggedUid:'target',taggedPseudo:'target',videoPath:'communities/response/videos/reply.mp4',videoBucket:'demo-bucket',respondingTo:'on-time'};
  await handlers.createVideoTorpille.run({auth:{uid:'respondent'},data});assert.equal((await responseC.collection('torpilles').doc('on-time').get()).data().responded,true);passed('reply and next torpille are committed atomically');
  await task(responseC,respondent,'too-late');const count=(await responseC.collection('torpilles').get()).size;
  await assert.rejects(()=>handlers.createVideoTorpille.run({auth:{uid:'respondent'},data:{...data,respondingTo:'too-late'}}),e=>e.code==='deadline-exceeded');
  assert.equal((await responseC.collection('torpilles').get()).size,count);assert.equal((await responseC.collection('torpilles').doc('too-late').get()).data().responded,false);passed('late reply cannot escape elimination or create another torpille');
  const ruleUser=await admin.auth().createUser({email:'rules@example.invalid',password:'EmulatorOnly123!',emailVerified:true});
  const ruleC=await community('rules-community','other-admin');await member(ruleC,ruleUser.uid);
  await db.doc(`users/${ruleUser.uid}`).update({firstName:'Rule',lastName:'User'});
  const tokenResponse=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'rules@example.invalid',password:'EmulatorOnly123!',returnSecureToken:true})});
  const {idToken}=await tokenResponse.json();assert.ok(idToken);
  const root=`http://127.0.0.1:8086/v1/projects/demo-torpille-elimination/databases/(default)/documents`;
  async function patch(path,fields){return fetch(root+path+'?'+Object.keys(fields).map(k=>'updateMask.fieldPaths='+k).join('&'),{method:'PATCH',headers:{'Content-Type':'application/json',Authorization:`Bearer ${idToken}`},body:JSON.stringify({fields})});}
  const rm=await ruleC.collection('members').doc(ruleUser.uid).get();await task(ruleC,rm,'protected-torpille');
  assert.equal((await patch('/communities/rules-community/torpilles/protected-torpille',{responded:{booleanValue:true}})).status,403);
  assert.equal((await patch('/communities/rules-community/torpilles/protected-torpille',{eliminationMode:{booleanValue:false}})).status,403);
  assert.equal((await patch('/communities/rules-community',{eliminationMode:{booleanValue:false}})).status,403);
  assert.equal((await patch('/communities/rules-community/messages/fake-system',{id:{stringValue:'fake-system'},senderUid:{stringValue:ruleUser.uid},type:{stringValue:'system'},text:{stringValue:'fake departure'}})).status,403);
  // Positive control ensures failures above are not merely a broken authenticated test session.
  assert.equal((await patch('/communities/rules-community/torpilles/protected-torpille',{penaltyApplied:{booleanValue:true}})).status,403);
  assert.equal((await patch('/communities/rules-community/members/'+ruleUser.uid,{lastSeenMessageAt:{timestampValue:new Date().toISOString()}})).status,200);
  passed('rules forbid client response spoofing, changing elimination mode, and forging system notices');
  console.log(`${checks} lifecycle integration checks passed. No production data touched.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
