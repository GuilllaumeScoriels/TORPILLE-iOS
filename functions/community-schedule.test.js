const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateSchedule, isRankingActive, changedSettings} = require('./community-schedule');
const at = value => new Date(value);
const weekly = (day, startMinute, endMinute, timeZone = 'Europe/Brussels') => ({fullTime: false, timeZone, weekly: [{day, startMinute, endMinute}], dates: []});
test('legacy and full-time communities stay active', () => {
  assert.equal(isRankingActive(null), true); assert.equal(isRankingActive({fullTime: true}), true);
});
test('weekly windows use the community zone and an exclusive end', () => {
  const s = weekly(1, 9 * 60, 18 * 60);
  assert.equal(isRankingActive(s, at('2026-10-12T06:59:59Z')), false);
  assert.equal(isRankingActive(s, at('2026-10-12T07:00:00Z')), true);
  assert.equal(isRankingActive(s, at('2026-10-12T15:59:59Z')), true);
  assert.equal(isRankingActive(s, at('2026-10-12T16:00:00Z')), false);
  assert.equal(isRankingActive(s, at('2026-10-13T10:00:00Z')), false);
});
test('overnight Sunday wraps to Monday without activating all of Monday', () => {
  const s = weekly(7, 22 * 60, 2 * 60);
  assert.equal(isRankingActive(s, at('2026-10-11T20:00:00Z')), true);
  assert.equal(isRankingActive(s, at('2026-10-11T23:59:59Z')), true);
  assert.equal(isRankingActive(s, at('2026-10-12T00:00:00Z')), false);
  assert.equal(isRankingActive(s, at('2026-10-12T20:00:00Z')), false);
});
test('handles summer/winter time and repeated DST hours in the selected zone', () => {
  const s = weekly(7, 120, 180);
  assert.equal(isRankingActive(s, at('2026-10-25T00:30:00Z')), true);
  assert.equal(isRankingActive(s, at('2026-10-25T01:30:00Z')), true);
  assert.equal(isRankingActive(s, at('2026-10-25T02:00:00Z')), false);
  assert.equal(isRankingActive(weekly(1, 540, 600), at('2026-12-07T08:30:00Z')), true);
});
test('dated windows and weekly windows form a union, with exact boundaries', () => {
  const startMs = Date.parse('2026-10-14T10:00:00Z'), endMs = startMs + 3600000;
  const s = {...weekly(1, 540, 1080), dates: [{startMs, endMs}]};
  assert.equal(isRankingActive(s, new Date(startMs)), true);
  assert.equal(isRankingActive(s, new Date(startMs - 1)), false);
  assert.equal(isRankingActive(s, new Date(endMs)), false);
});
test('invalid schedules fail closed and cannot be saved', () => {
  for (const s of [{fullTime: false, timeZone: 'UTC'}, weekly(0, 1, 2), weekly(1, 10, 10), weekly(1, 20, 1441), weekly(1, 10, 20, 'Mars/Nowhere'),
    {fullTime: false, timeZone: 'UTC', dates: [{startMs: 100, endMs: 50}]}]) {
    assert.throws(() => validateSchedule(s)); assert.equal(isRankingActive(s), false);
  }
});
test('settings notices exclude activity-only writes and include every configurable setting', () => {
  assert.deepEqual(changedSettings({name: 'A'}, {name: 'A', lastMessageAt: 10}), []);
  assert.equal(changedSettings({}, {name: 'A', isPublic: true, responseTimeSeconds: 20, eliminationMode: true, rankingSchedule: weekly(1, 2, 3), adminUid: 'new'}).length, 6);
});
