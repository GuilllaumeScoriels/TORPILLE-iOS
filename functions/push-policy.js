// Shared policy for every device, including users without saved preferences.
function notificationMode(value) {
  return typeof value === "string" && value ? value : "all";
}

function shouldNotify(mode, directlyTargeted) {
  return mode === "all" || (mode === "mentionsOnly" && directlyTargeted);
}

function pushPayload(tokens, {title, body, data}, bundleId) {
  return {
    tokens,
    notification: {title, body},
    data: Object.fromEntries(Object.entries(data || {}).map(([key, value]) => [key, String(value)])),
    android: {
      priority: "high",
      notification: {channelId: "torpille_alerts", sound: "default", defaultVibrateTimings: true},
    },
    apns: {
      headers: {"apns-push-type": "alert", "apns-priority": "10", "apns-topic": bundleId},
      payload: {aps: {sound: "default", badge: 1}},
    },
  };
}

module.exports = {notificationMode, shouldNotify, pushPayload};
