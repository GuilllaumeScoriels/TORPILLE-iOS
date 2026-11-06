const {test} = require('node:test');
const assert = require('node:assert/strict');
const {normalizePhone, digest, createContactHandlers} = require('./contact-discovery');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
function setup() {
  const records = new Map();
  const users = new Map([
    ['me', {uid: 'me', phoneNumber: '+32470123456'}],
    ['friend', {uid: 'friend', phoneNumber: '+33612345678'}],
  ]);
  const snapshot = path => ({exists: records.has(path), data: () => records.get(path)});
  const doc = path => ({path, get: async () => snapshot(path), set: async value => records.set(path, value), delete: async () => records.delete(path)});
  const db = {doc, collection: name => ({doc: uid => doc(`${name}/${uid}`)}),
    getAll: async (...refs) => refs.map(ref => snapshot(ref.path)),
    runTransaction: async block => block({get: ref => ref.get(), set: (ref, value) => records.set(ref.path, value)})};
  const auth = {getUser: async uid => users.get(uid), getUsers: async ids => ({users: [...users.values()].filter(u => ids.some(id => id.phoneNumber === u.phoneNumber))})};
  const handlers = createContactHandlers(db, auth, HttpsError);
  records.set('users/friend', {pseudo: 'ami', email: 'private@example.com', firstName: 'Private', friendsCount: 4});
  records.set('contactDiscovery/friend', {phoneHash: digest(users.get('friend').phoneNumber)});
  const request = (data = {}) => ({auth: {uid: 'me'}, data});
  const search = () => handlers.findPhoneContacts(request({numbers: ['06 12 34 56 78'], country: 'FR'}));
  return {records, users, handlers, request, search};
}
test('normalizes national, international, punctuation and 00 prefixes', () => {
  assert.equal(normalizePhone('0470 12 34 56', 'BE'), '+32470123456');
  assert.equal(normalizePhone('06 12 34 56 78', 'FR'), '+33612345678');
  assert.equal(normalizePhone('0033 6 12 34 56 78', 'BE'), '+33612345678');
  assert.equal(normalizePhone('+33 (6) 12-34-56-78', 'SE'), '+33612345678');
  assert.equal(normalizePhone('070 123 45 67', 'SE'), '+46701234567');
});
test('rejects invalid numbers and extensions', () => {
  for (const input of ['112', 'abc', '', 'Call +33612345678', '+33123456789 ext. 42', null, '9'.repeat(81)]) assert.equal(normalizePhone(input, 'FR'), null);
});
test('requires authentication, including for preferences', async () => {
  const {handlers} = setup();
  for (const handler of Object.values(handlers)) await assert.rejects(handler({data: {}}), {code: 'unauthenticated'});
});
test('requires verified phone for lookup and opt-in, but allows opt-out', async () => {
  const {users, handlers, request, search} = setup(); users.get('me').phoneNumber = null;
  await assert.rejects(search(), {code: 'failed-precondition'});
  await assert.rejects(handlers.setContactDiscoverySettings(request({discoverable: true})), {code: 'failed-precondition'});
  assert.equal((await handlers.setContactDiscoverySettings(request({discoverable: false}))).discoverable, false);
});
test('new accounts default to hidden, explicit consent can be revoked', async () => {
  const {handlers, request, records} = setup();
  assert.equal((await handlers.getContactDiscoverySettings(request())).discoverable, false);
  assert.equal((await handlers.setContactDiscoverySettings(request({discoverable: true}))).discoverable, true);
  assert.equal((await handlers.setContactDiscoverySettings(request({discoverable: false}))).discoverable, false);
  assert.equal(records.has('contactDiscovery/me'), false);
});
test('matches only public identity and never returns or stores submitted phones', async () => {
  const {search, records} = setup(); const {profiles} = await search();
  assert.deepEqual(profiles, [{uid: 'friend', pseudo: 'ami', photoUrl: null, profileIcon: null, friendsCount: 4}]);
  assert.equal(JSON.stringify([...records.values()]).includes('0612345678'), false);
  assert.deepEqual(Object.keys(records.get('contactDiscoveryLimits/me')).sort(), ['day', 'used']);
});
test('hidden, disabled, deleted profiles and changed phone consent are excluded', async () => {
  for (const mutate of [s => s.records.delete('contactDiscovery/friend'), s => s.users.get('friend').disabled = true,
    s => s.records.delete('users/friend'), s => s.records.set('contactDiscovery/friend', {phoneHash: digest('+32470123456')})]) {
    const s = setup(); mutate(s); assert.deepEqual(await s.search(), {profiles: []});
  }
});
test('checks blocks in both directions without depending on reverse-index trigger', async () => {
  for (const path of ['users/me/blockedUsers/friend', 'users/friend/blockedUsers/me']) {
    const s = setup(); s.records.set(path, {}); assert.deepEqual(await s.search(), {profiles: []});
  }
});
test('self and duplicate results are excluded', async () => {
  const {handlers, request, records} = setup(); records.set('contactDiscovery/me', {phoneHash: digest('+32470123456')}); records.set('users/me', {pseudo: 'self'});
  const result = await handlers.findPhoneContacts(request({numbers: ['+32470123456', '+33612345678', '0612345678'], country: 'FR'}));
  assert.equal(result.profiles.length, 1); assert.equal(result.profiles[0].uid, 'friend');
});
test('rejects invalid country, batches and preference types', async () => {
  const {handlers, request} = setup();
  for (const numbers of [[], Array(101).fill('123'), [42], ['1'.repeat(81)]]) {
    await assert.rejects(handlers.findPhoneContacts(request({numbers, country: 'FR'})), {code: 'invalid-argument'});
  }
  await assert.rejects(handlers.findPhoneContacts(request({numbers: ['123'], country: 'XX'})), {code: 'invalid-argument'});
  await assert.rejects(handlers.setContactDiscoverySettings(request({discoverable: 'true'})), {code: 'invalid-argument'});
});
test('daily budget counts invalid inputs too and resets next day', async () => {
  const {records, search} = setup();
  records.set('contactDiscoveryLimits/me', {day: new Date().toISOString().slice(0, 10), used: 2000});
  await assert.rejects(search(), {code: 'resource-exhausted'});
  records.set('contactDiscoveryLimits/me', {day: '2000-01-01', used: 2000});
  assert.equal((await search()).profiles.length, 1);
  assert.equal(records.get('contactDiscoveryLimits/me').used, 1);
});
test('changing phone requires renewing discoverability', async () => {
  const {handlers, request, users} = setup();
  await handlers.setContactDiscoverySettings(request({discoverable: true}));
  users.get('me').phoneNumber = '+46701234567';
  assert.equal((await handlers.getContactDiscoverySettings(request())).discoverable, false);
});
