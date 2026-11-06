// Run with the local Firestore emulator; all profiles and tokens below are fictitious.
const {createRequire}=require('node:module');
const sdk=process.env.RULE_TEST_PACKAGE ? createRequire(process.env.RULE_TEST_PACKAGE) : require;
const {initializeTestEnvironment,assertSucceeds,assertFails}=sdk('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc,Timestamp}=sdk('firebase/firestore');const fs=require('node:fs');
(async()=>{const env=await initializeTestEnvironment({projectId:'demo-torpille-push',firestore:{host:'127.0.0.1',port:8192,rules:fs.readFileSync(process.env.PUSH_RULES_PATH || 'firestore.rules','utf8')}});
try{
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  function restore(value){if(value&&value.__timestamp)return Timestamp.now();if(Array.isArray(value))return value.map(restore);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,restore(v)]));return value;}
  const fixture=restore({"isLanguagePublic": true, "lastName": "placeholder", "city": "placeholder", "bio": "placeholder", "pseudoKey": "placeholder", "moderationRulesAcceptedAt": {"__timestamp": true}, "firstName": "placeholder", "photoUrl": "placeholder", "uid": "fullschema", "pseudo": "placeholder", "termsAcceptedAt": {"__timestamp": true}, "email": "test@example.com", "isLeaderboardPublic": true, "pinnedCommunityIds": [], "xpTotal": 0, "communityXP": {"c1": 0, "c2": 0, "c3": 0}, "xptotal": 0, "lastLocationUpdatedAt": {"__timestamp": true}, "lastLongitude": 0, "lastLatitude": 0, "fcmTokens": [], "communityIds": ["placeholder", "placeholder", "placeholder", "placeholder"], "updatedAt": {"__timestamp": true}});
  await setDoc(doc(db,'users/fullschema'),fixture);
  for(const uid of ['normal','legacy','full']){const value={firstName:'Test',lastName:'Test',pseudo:uid,legacyExtra:'unchanged',fcmTokens:uid==='full'?Array.from({length:10},(_,i)=>'old-'+i):[],updatedAt:Timestamp.now()};if(uid!=='legacy')value.uid=uid;await setDoc(doc(db,'users/'+uid),value);}
 });
 for(const uid of ['normal','legacy','full','fullschema']){
  const db=env.authenticatedContext(uid,{email_verified:true,email:'test@example.com'}).firestore();
  const payload={uid,fcmToken:'new-device',fcmTokens:['new-device'],updatedAt:Timestamp.now()};
  await assertSucceeds(updateDoc(doc(db,'users/'+uid),payload));console.log('PASS own bounded push registration: '+uid);
 }
 const other=env.authenticatedContext('other',{email_verified:true}).firestore();
 await assertFails(updateDoc(doc(other,'users/normal'),{fcmToken:'stolen',fcmTokens:['stolen'],updatedAt:Timestamp.now()}));console.log('PASS other account cannot alter tokens');
 const db=env.authenticatedContext('normal',{email_verified:true}).firestore();
 await assertFails(updateDoc(doc(db,'users/normal'),{fcmTokens:Array.from({length:11},(_,i)=>'device-'+i)}));console.log('PASS token limit remains enforced');
 await assertFails(updateDoc(doc(db,'users/normal'),{fcmToken:'other',unexpectedPrivilege:true}));console.log('PASS push write cannot add unrelated fields');
 await assertFails(updateDoc(doc(db,'users/normal'),{uid:'another-user',fcmToken:'other'}));console.log('PASS push write cannot change account identity');
 const anonymous=env.unauthenticatedContext().firestore();
 await assertFails(updateDoc(doc(anonymous,'users/normal'),{fcmToken:'other'}));console.log('PASS signed-out client cannot register a device');
}finally{await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1});
