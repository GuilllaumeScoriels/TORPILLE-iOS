// Local-only Firebase Auth integration checks. Run with the Auth emulator on port 9198.
const assert = require('node:assert/strict');
const base = 'http://127.0.0.1:9198';
const project = process.env.AUTH_EMULATOR_PROJECT || 'demo-torpille-auth-audit';
const identity = '/identitytoolkit.googleapis.com/v1/';
const email = `auth-audit-${crypto.randomUUID()}@example.invalid`;
const password = '  emulator password  ';
let checks = 0;
async function call(path, body) {
  const response = await fetch(base + path, body ? {
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
  } : {signal: AbortSignal.timeout(10000)});
  return {ok: response.ok, status: response.status, body: await response.json()};
}
async function api(method, body) { return call(identity + method + '?key=fake-api-key', body); }
const passed = text => { checks++; console.log('PASS ' + text); };
(async () => {
  const created = await api('accounts:signUp', {email, password, returnSecureToken: true});
  assert.equal(created.ok, true);
  const uid = created.body.localId;
  let token = created.body.idToken;
  try {
    const account = await api('accounts:lookup', {idToken: token});
    assert.equal(account.body.users[0].emailVerified, false);
    passed('new accounts start unverified');
    const duplicate = await api('accounts:signUp', {email, password, returnSecureToken: true});
    assert.equal(duplicate.ok, false);
    assert.equal(duplicate.body.error.message, 'EMAIL_EXISTS');
    passed('duplicate registration is rejected');
    const sent = await api('accounts:sendOobCode', {requestType: 'VERIFY_EMAIL', idToken: token});
    assert.equal(sent.ok, true);
    const codes = await call(`/emulator/v1/projects/${project}/oobCodes`);
    const code = codes.body.oobCodes.findLast(c => c.email === email && c.requestType === 'VERIFY_EMAIL');
    assert.ok(code);
    assert.equal((await api('accounts:update', {oobCode: code.oobCode})).ok, true);
    passed('verification email code activates the account');
    const rejected = await api('accounts:signInWithPassword', {email, password: password.trim(), returnSecureToken: true});
    assert.equal(rejected.ok, false);
    passed('trimming a password changes it and must not occur in registration');
    const signedIn = await api('accounts:signInWithPassword', {email, password, returnSecureToken: true});
    assert.equal(signedIn.ok, true);
    assert.equal(signedIn.body.localId, uid);
    token = signedIn.body.idToken;
    const verified = await api('accounts:lookup', {idToken: token});
    assert.equal(verified.body.users[0].emailVerified, true);
    passed('original password signs into the same verified account');
    const reset = await api('accounts:sendOobCode', {requestType: 'PASSWORD_RESET', email});
    assert.equal(reset.ok, true);
    const resetCodes = await call(`/emulator/v1/projects/${project}/oobCodes`);
    const resetCode = resetCodes.body.oobCodes.findLast(c => c.email === email && c.requestType === 'PASSWORD_RESET');
    assert.ok(resetCode);
    const newPassword = 'new emulator password';
    assert.equal((await api('accounts:resetPassword', {oobCode: resetCode.oobCode, newPassword})).ok, true);
    assert.equal((await api('accounts:signInWithPassword', {email, password, returnSecureToken: true})).ok, false);
    const resetSignIn = await api('accounts:signInWithPassword', {email, password: newPassword, returnSecureToken: true});
    assert.equal(resetSignIn.ok, true);
    token = resetSignIn.body.idToken;
    passed('password reset invalidates the old password and accepts the new one');
    console.log(JSON.stringify({checks, failed: 0, environment: 'local Auth emulator'}));
  } finally {
    const removed = await api('accounts:delete', {idToken: token});
    assert.equal(removed.ok, true, 'local test account cleanup');
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
