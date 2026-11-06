const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createInvitationHandlers, normalizeCode, newCode} = require("./community-invitations");
class ErrorWithCode extends Error { constructor(code, message) { super(message); this.code = code; } }
const auth = {uid: "member", token: {email_verified: true}};
function setup() {
  const records = new Map([
    ["communities/existing-ios-community", {adminUid: "admin", isPublic: false}],
    ["communities/existing-ios-community/members/member", {}],
  ]);
  const ref = path => ({path, collection: name => ref(`${path}/${name}`), doc: id => ref(`${path}/${id}`),
    get: async () => ({exists: records.has(path), data: () => records.get(path)})});
  const db = {collection: name => ref(name), runTransaction: async callback => callback({
    get: r => r.get(), create: (r, value) => { assert.equal(records.has(r.path), false); records.set(r.path, value); },
  })};
  const handlers = createInvitationHandlers(db, ErrorWithCode);
  return {records, handlers, db};
}
test("existing private community gets one stable cross-platform code", async () => {
  const {handlers, records} = setup();
  const request = {auth, data: {communityId: "existing-ios-community"}};
  const first = await handlers.getCommunityInvitationCode(request);
  assert.match(first.code, /^[A-Z2-9]{8}$/);
  assert.deepEqual(await handlers.getCommunityInvitationCode(request), first);
  assert.deepEqual(await handlers.resolveCommunityInvitationCode({auth: {...auth, uid: "new-android-member"}, data: {code: first.code.toLowerCase()}}), {communityId: "existing-ios-community"});
  assert.equal(records.has("communities/existing-ios-community/members/new-android-member"), false);
});
test("normalization accepts pasted spaces and separators", () => {
  assert.equal(normalizeCode(" abcd-2345 \n"), "ABCD2345");
  for (let i = 0; i < 50; i++) assert.match(newCode(), /^[A-HJ-NP-Z2-9]{8}$/);
});
test("unknown and malformed codes have explicit errors", async () => {
  const {handlers} = setup();
  await assert.rejects(handlers.resolveCommunityInvitationCode({auth, data: {code: "ABCDEFGH"}}), {code: "not-found"});
  await assert.rejects(handlers.resolveCommunityInvitationCode({auth, data: {code: "abc"}}), {code: "invalid-argument"});
});
test("nonmembers cannot generate codes and anonymous clients cannot resolve", async () => {
  const {handlers} = setup();
  await assert.rejects(handlers.getCommunityInvitationCode({auth: {...auth, uid: "outsider"}, data: {communityId: "existing-ios-community"}}), {code: "permission-denied"});
  await assert.rejects(handlers.resolveCommunityInvitationCode({data: {code: "ABCDEFGH"}}), {code: "unauthenticated"});
  await assert.rejects(handlers.resolveCommunityInvitationCode({auth: {uid: "member", token: {}}, data: {code: "ABCDEFGH"}}), {code: "failed-precondition"});
});
test("bans and deleted communities cannot be bypassed with a code", async () => {
  const {handlers, records} = setup();
  const {code} = await handlers.getCommunityInvitationCode({auth, data: {communityId: "existing-ios-community"}});
  records.set("communities/existing-ios-community/banned/member", {});
  await assert.rejects(handlers.resolveCommunityInvitationCode({auth, data: {code}}), {code: "permission-denied"});
  records.delete("communities/existing-ios-community");
  await assert.rejects(handlers.resolveCommunityInvitationCode({auth, data: {code}}), {code: "not-found"});
});
test("code collision is retried without overwriting another invitation", async () => {
  const {db, records} = setup();
  records.set("communityInvitationCodes/ABCDEFGH", {communityId: "other"});
  let calls = 0;
  const handlers = createInvitationHandlers(db, ErrorWithCode, () => ++calls === 1 ? "ABCDEFGH" : "JKLM2345");
  assert.deepEqual(await handlers.getCommunityInvitationCode({auth, data: {communityId: "existing-ios-community"}}), {code: "JKLM2345"});
  assert.equal(records.get("communityInvitationCodes/ABCDEFGH").communityId, "other");
});
