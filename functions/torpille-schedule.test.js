const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const NOW = Date.parse('2026-10-12T10:00:00Z');
const stamp = ms => ({toMillis: () => ms, toDate: () => new Date(ms), isEqual: other => other?.toMillis() === ms});
function setup({active = true, replying = false, eliminationMode = false} = {}) {
  const records = new Map();
  const mutations = [];
  let newId = 0;
  const ref = path => ({path, id: path.split('/').at(-1), collection: name => ref(`${path}/${name}`), doc: id => ref(`${path}/${id || 'new-' + ++newId}`)});
  const snapshot = r => ({ref: r, exists: records.has(r.path), createTime: stamp(1), data: () => records.get(r.path)});
  const db = {collection: name => ref(name), runTransaction: async block => {
    let writing = false;
    const writes = [];
    const result = await block({get: async r => { assert.equal(writing, false, 'all reads must precede writes'); return snapshot(r); },
      update: (r, value) => { writing = true; writes.push({path: r.path, value}); },
      set: (r, value) => { writing = true; writes.push({path: r.path, value}); }});
    mutations.push(...writes); return result;
  }};
  const admin = {initializeApp() {}, auth: () => ({}), storage: () => ({bucket: () => ({name: 'bucket', file: () => ({exists: async () => [true]})})}),
    firestore: Object.assign(() => db, {Timestamp: {now: () => stamp(NOW), fromMillis: stamp}, FieldValue: {delete: () => 'DELETE', increment: n => ({increment: n})}})};
  const wrap = (_, handler) => handler;
  const modules = {'firebase-admin': admin, 'firebase-functions/v2/https': {onCall: wrap, HttpsError},
    'firebase-functions/v2/firestore': {onDocumentCreated: wrap, onDocumentWritten: wrap, onDocumentWrittenWithAuthContext: wrap},
    'firebase-functions/v2/scheduler': {onSchedule: wrap}, 'firebase-functions/params': {defineSecret: () => ({})},
    'firebase-functions/v1': {region: () => ({auth: {user: () => ({onDelete() {}, onCreate() {}})}})}, nodemailer: {}};
  const exports = {};
  vm.runInNewContext(fs.readFileSync(require.resolve('./index.js'), 'utf8'), {exports, require: name => modules[name] || require(name), process: {env: {}}, console});
  const base = 'communities/c1';
  records.set(base, {responseTimeSeconds: 3600, eliminationMode,
    rankingSchedule: active ? {fullTime: true} : {fullTime: false, timeZone: 'UTC', weekly: [{day: 7, startMinute: 540, endMinute: 600}]}});
  records.set(`${base}/members/sender`, {pendingTorpilleId: replying ? 'previous' : null});
  records.set(`${base}/members/target`, {pendingTorpilleId: 'unrelated'});
  if (replying) records.set(`${base}/torpilles/previous`, {toUid: 'sender', responded: false, deadlineAt: stamp(NOW + 1000), eliminationMode, targetMembershipCreatedAt: stamp(1)});
  const request = {auth: {uid: 'sender'}, data: {communityId: 'c1', taggedUid: 'target', senderPseudo: 'sender', taggedPseudo: 'target', videoBucket: 'bucket', videoPath: 'communities/c1/videos/file.mp4', ...(replying ? {respondingTo: 'previous'} : {})}};
  return {call: () => exports.createVideoTorpille(request), records, mutations, base, exports, request};
}
test('active torpilles award XP and create a target obligation', async () => {
  const s = setup(); await s.call();
  assert.ok(s.mutations.some(w => w.path.endsWith('/members/sender') && w.value.xpInCommunity?.increment === 20));
  assert.ok(s.mutations.some(w => w.path.endsWith('/members/target') && w.value.pendingTorpilleId));
});
test('closed hours refuse new torpilles before any writes', async () => {
  const s = setup({active: false}); await assert.rejects(s.call(), {code: 'failed-precondition'}); assert.equal(s.mutations.length, 0);
});
test('outside-hours reply closes original without XP, target obligation, penalty or elimination queue', async () => {
  const s = setup({active: false, replying: true, eliminationMode: true}); await s.call();
  assert.ok(s.mutations.some(w => w.path.endsWith('/torpilles/previous') && w.value.responded));
  const next = s.mutations.find(w => w.path.includes('/torpilles/new-')).value;
  assert.equal(next.responseRequired, false); assert.equal(next.responded, true); assert.equal(next.eliminationMode, false);
  assert.equal(s.mutations.some(w => w.path.endsWith('/members/target')), false);
  assert.equal(s.mutations.some(w => w.value.xpInCommunity), false);
  assert.equal(s.mutations.some(w => w.path.startsWith('communityEliminationQueue')), false);
});
test('outside-hours reply is allowed after the original deadline; no recovery points', async () => {
  const s = setup({active: false, replying: true, eliminationMode: true});
  s.records.get(`${s.base}/torpilles/previous`).deadlineAt = stamp(NOW - 1000); await s.call();
  assert.equal(s.mutations.some(w => w.value.xpInCommunity), false);
});
test('fabricated, already answered and response-exempt torpilles cannot grant a reply exception', async () => {
  for (const modify of [s => s.records.delete(`${s.base}/torpilles/previous`), s => s.records.get(`${s.base}/torpilles/previous`).responded = true,
    s => s.records.get(`${s.base}/torpilles/previous`).responseRequired = false, s => s.records.get(`${s.base}/torpilles/previous`).toUid = 'someone-else']) {
    const s = setup({active: false, replying: true}); modify(s); await assert.rejects(s.call(), {code: 'failed-precondition'}); assert.equal(s.mutations.length, 0);
  }
});
test('blocked recipient still cannot be targeted outside hours', async () => {
  const s = setup({active: false, replying: true}); s.records.set('users/target/blockedUsers/sender', {});
  await assert.rejects(s.call(), {code: 'permission-denied'});
});
test('answering an older torpille does not erase a newer pending obligation', async () => {
  const s = setup({active: false, replying: true});
  s.records.get(`${s.base}/members/sender`).pendingTorpilleId = 'newer';
  await s.call();
  assert.equal(s.mutations.some(w => w.path.endsWith('/members/sender') && 'pendingTorpilleId' in w.value), false);
});
test('only an administrator may change schedules', async () => {
  const s = setup();
  const request = {auth: {uid: 'sender'}, data: {communityId: 'c1', isPublic: true, eliminationMode: false, responseTimeSeconds: 3600,
    rankingSchedule: {fullTime: false, timeZone: 'UTC', weekly: [{day: 1, startMinute: 540, endMinute: 600}], dates: []}}};
  await assert.rejects(s.exports.updateCommunitySettings(request), {code: 'permission-denied'});
  s.records.get(s.base).adminUid = 'sender';
  await s.exports.updateCommunitySettings(request);
  assert.ok(s.mutations.some(w => w.value.rankingSchedule?.fullTime === false));
});
test('expired penalties do not change XP outside scheduled hours', async () => {
  const s = setup({active: false, replying: true});
  // No dates or weekly windows active on any weekday: one historic dated window.
  s.records.get(s.base).rankingSchedule = {fullTime: false, timeZone: 'UTC', weekly: [], dates: [{startMs: 1, endMs: 2}]};
  const result = await s.exports.applyExpiredTorpillePenalty({auth: {uid: 'sender'}, data: {communityId: 'c1'}});
  assert.equal(result.applied, false); assert.equal(s.mutations.length, 0);
});
test('response-exempt torpilles can never be penalized on reopening', async () => {
  const s = setup({replying: true});
  Object.assign(s.records.get(`${s.base}/torpilles/previous`), {responseRequired: false, responded: false, deadlineAt: stamp(1)});
  const result = await s.exports.applyExpiredTorpillePenalty({auth: {uid: 'sender'}, data: {communityId: 'c1'}});
  assert.equal(result.applied, false); assert.equal(s.mutations.length, 0);
});
test('a reply at the exact deadline cannot bypass elimination', async () => {
  const s = setup({replying: true, eliminationMode: true});
  s.records.get(`${s.base}/torpilles/previous`).deadlineAt = stamp(NOW);
  await assert.rejects(s.call(), {code: 'deadline-exceeded'});
  assert.equal(s.mutations.length, 0);
});
test('older settings requests preserve schedules and elimination mode', async () => {
  const s = setup({eliminationMode: true});
  s.records.get(s.base).adminUid = 'sender';
  await s.exports.updateCommunitySettings({auth: {uid: 'sender'}, data: {
    communityId: 'c1', isPublic: false, responseTimeSeconds: 120,
  }});
  assert.equal(s.mutations.length, 1);
  assert.deepEqual(s.mutations[0].value, {isPublic: false, responseTimeSeconds: 120});
});
test('elimination replies remain allowed just before the deadline and rejected after it', async () => {
  for (const offset of [1, -1]) {
    const s = setup({replying: true, eliminationMode: true});
    s.records.get(`${s.base}/torpilles/previous`).deadlineAt = stamp(NOW + offset);
    if (offset > 0) await s.call();
    else {
      await assert.rejects(s.call(), {code: 'deadline-exceeded'});
      assert.equal(s.mutations.length, 0);
    }
  }
});
test('optional settings still reject explicit invalid values without writes', async () => {
  for (const extra of [{eliminationMode: null}, {eliminationMode: 'false'}, {rankingSchedule: null}, {rankingSchedule: {fullTime: false}}]) {
    const s = setup();
    s.records.get(s.base).adminUid = 'sender';
    await assert.rejects(s.exports.updateCommunitySettings({auth: {uid: 'sender'}, data: {
      communityId: 'c1', isPublic: true, responseTimeSeconds: 60, ...extra,
    }}), {code: 'invalid-argument'});
    assert.equal(s.mutations.length, 0);
  }
});
test('legacy settings request still requires the community administrator', async () => {
  const s = setup();
  await assert.rejects(s.exports.updateCommunitySettings({auth: {uid: 'sender'}, data: {
    communityId: 'c1', isPublic: false, responseTimeSeconds: 60,
  }}), {code: 'permission-denied'});
  assert.equal(s.mutations.length, 0);
});
test('legacy communities and pending torpilles without new fields can still receive a reply', async () => {
  const s = setup({replying: true});
  delete s.records.get(s.base).rankingSchedule;
  delete s.records.get(s.base).eliminationMode;
  const previous = s.records.get(`${s.base}/torpilles/previous`);
  delete previous.eliminationMode;
  delete previous.targetMembershipCreatedAt;
  await s.call();
  assert.ok(s.mutations.some(w => w.path.endsWith('/torpilles/previous') && w.value.responded === true));
  assert.ok(s.mutations.some(w => w.path.endsWith('/members/target') && w.value.pendingTorpilleId));
});
