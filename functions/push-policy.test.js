const {test} = require("node:test");
const assert = require("node:assert/strict");
const {notificationMode, shouldNotify, pushPayload} = require("./push-policy");

test("no saved choice enables all community content", () => {
  assert.equal(notificationMode(undefined), "all");
  for (const kind of ["text", "image", "audio", "video", "other"]) {
    assert.equal(shouldNotify(notificationMode(undefined), false), true, kind);
  }
});
test("only me remains respected but delivers direct torpilles", () => {
  assert.equal(notificationMode("mentionsOnly"), "mentionsOnly");
  assert.equal(shouldNotify("mentionsOnly", false), false);
  assert.equal(shouldNotify("mentionsOnly", true), true);
});
test("alert payload requests immediate transport on both platforms", () => {
  const result = pushPayload(["android-device", "apple-device"], {
    title: "Communauté", body: "Nouveau contenu", data: {communityId: "c1", type: "message", count: 1},
  }, "com.torpille.ios");
  assert.equal(result.android.priority, "high");
  assert.equal(result.android.notification.channelId, "torpille_alerts");
  assert.equal(result.apns.headers["apns-priority"], "10");
  assert.equal(result.apns.headers["apns-push-type"], "alert");
  assert.equal(result.apns.payload.aps.sound, "default");
  assert.equal(result.data.communityId, "c1");
  assert.equal(result.data.count, "1");
  assert.deepEqual(result.tokens, ["android-device", "apple-device"]);
  assert.equal(result.notification.body, "Nouveau contenu");
});
