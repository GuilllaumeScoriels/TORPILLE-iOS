const {test} = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");

function server(directRecipientMode) {
  const sent = [];
  const written = [];
  const members = ["sender", "default", "all", "only-me"];
  function ref(path) {
    return {
      collection: name => ref(`${path}/${name}`), doc: id => ref(`${path}/${id}`),
      async set(value) { written.push({path, value}); },
      async get() {
        if (path === "communities/c1") return {data: () => ({name: "Communauté"})};
        if (path === "communities/c1/members") return {docs: members.map(id => ({id, data: () => ({uid: id})}))};
        const parts = path.split("/");
        if (parts[0] === "users" && parts.length === 2) return {data: () => ({fcmTokens: [`${parts[1]}-android`, `${parts[1]}-ios`]})};
        if (parts[2] === "notificationPreferences" && directRecipientMode !== undefined) return {data: () => ({mode: directRecipientMode})};
        if (parts[2] === "notificationPreferences") return {data: () => parts[1] === "default" ? {} : {mode: parts[1] === "only-me" ? "mentionsOnly" : "all"}};
        throw new Error(`Unexpected database read: ${path}`);
      },
    };
  }
  const wrap = (_, handler) => handler;
  const modules = {
    "node:crypto": require("node:crypto"),
    "./community-schedule": require("./community-schedule"),
    "./community-settings": require("./community-settings"),
    "./contact-discovery": require("./contact-discovery"),
    "./community-lifecycle": require("./community-lifecycle"),
    "./push-policy": require("./push-policy"),
    "./community-invitations": require("./community-invitations"),
    "firebase-admin": {
      initializeApp() {}, auth: () => ({}), firestore: Object.assign(() => ({collection: name => ref(name)}), {Timestamp: {fromDate: value => value}}), storage: () => ({}),
      messaging: () => ({async sendEachForMulticast(payload) {
        sent.push(payload); return {successCount: payload.tokens.length, failureCount: 0, responses: payload.tokens.map(() => ({success: true}))};
      }}),
    },
    "firebase-functions/v2/https": {onCall: wrap},
    "firebase-functions/v2/firestore": {onDocumentCreated: wrap, onDocumentWritten: wrap, onDocumentWrittenWithAuthContext: wrap},
    "firebase-functions/v2/scheduler": {onSchedule: wrap},
    "firebase-functions/params": {defineSecret: () => ({})},
    "firebase-functions/v1": {region: () => ({auth: {user: () => ({onDelete() {}, onCreate() {}})}})},
    nodemailer: {},
  };
  const context = {exports: {}, require: name => {
    if (!(name in modules)) throw new Error(`Unexpected module: ${name}`);
    return modules[name];
  }, process: {env: {}}, console: {log() {}, error() {}}};
  vm.runInNewContext(fs.readFileSync(require.resolve("./index.js"), "utf8"), context);
  return {handlers: context.exports, sent, written, ref};
}

for (const type of ["text", "image", "audio", "video", "file"]) {
  test(`${type}: alerts both devices of all/default members, excludes sender and only-me`, async () => {
    const {handlers, sent} = server();
    await handlers.notifyOnMessageCreated({params: {communityId: "c1", messageId: "m1"}, data: {data: () => ({senderUid: "sender", senderPseudo: "Alice", type})}});
    assert.deepEqual(sent.flatMap(p => p.tokens).sort(), ["all-android", "all-ios", "default-android", "default-ios"]);
    assert.ok(sent.every(p => p.data.communityId === "c1" && p.android.priority === "high"));
  });
}

test("only-me receives direct torpille once, not its mirrored discussion message", async () => {
  const {handlers, sent} = server();
  const params = {communityId: "c1", messageId: "m1", torpilleId: "t1"};
  await handlers.notifyOnTorpilleCreated({params, data: {data: () => ({fromUid: "sender", toUid: "only-me", fromPseudo: "Alice"})}});
  await handlers.notifyOnMessageCreated({params, data: {data: () => ({senderUid: "sender", taggedUid: "only-me", torpilleId: "t1", type: "video"})}});
  assert.equal(sent.filter(p => p.tokens.includes("only-me-ios")).length, 1);
  assert.equal(sent[0].data.type, "torpille");
});


test("membership system notices stay in the discussion without a media push", async () => {
  const {handlers, sent} = server();
  await handlers.notifyOnMessageCreated({params: {communityId: "c1", messageId: "m1"}, data: {data: () => ({type: "system", senderUid: "__system__"})}});
  assert.equal(sent.length, 0);
});

test("settings changes notify every member regardless of discussion preference and leave a notice", async () => {
  const {handlers, sent, written, ref} = server();
  await handlers.notifyOnCommunitySettingsChanged({id: "event-1", time: "2026-10-14T10:00:00Z", params: {communityId: "c1"}, data: {
    before: {exists: true, data: () => ({name: "Communauté", responseTimeSeconds: 3600})},
    after: {exists: true, ref: ref("communities/c1"), data: () => ({name: "Communauté", responseTimeSeconds: 7200})},
  }});
  assert.equal(sent.length, 4);
  assert.ok(sent.some(push => push.tokens.includes("only-me-android")));
  assert.equal(written.length, 1);
  assert.equal(written[0].value.systemEvent, "settingsChanged");
  assert.match(written[0].value.text, /délai de réponse/);
});

for (const mode of ["all", "mentionsOnly", "none"]) {
  test(`direct torpille alerts every recipient device with preference ${mode}`, async () => {
    const {handlers, sent} = server(mode);
    await handlers.notifyOnTorpilleCreated({params: {communityId: "c1", torpilleId: "t1"}, data: {data: () => ({fromUid: "sender", toUid: "only-me"})}});
    assert.equal(sent.length, 1);
    assert.deepEqual(Array.from(sent[0].tokens).sort(), ["only-me-android", "only-me-ios"]);
    assert.equal(sent[0].apns.headers["apns-push-type"], "alert");
    assert.equal(sent[0].apns.payload.aps.sound, "default");
    assert.equal(sent[0].data.torpilleId, "t1");
  });
}
