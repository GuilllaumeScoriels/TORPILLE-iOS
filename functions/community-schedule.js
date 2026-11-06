const WEEKDAYS = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7};
function validateSchedule(value) {
  if (!value || typeof value.fullTime !== 'boolean' || typeof value.timeZone !== 'string') throw new Error('Horaires invalides.');
  try { new Intl.DateTimeFormat('en', {timeZone: value.timeZone}).format(); } catch { throw new Error('Fuseau horaire invalide.'); }
  const weekly = value.weekly ?? [], dates = value.dates ?? [];
  if (!Array.isArray(weekly) || !Array.isArray(dates) || weekly.length > 28 || dates.length > 30) throw new Error('Trop de créneaux.');
  const normalized = {fullTime: value.fullTime, timeZone: value.timeZone,
    weekly: weekly.map(w => {
      if (!w || !Number.isInteger(w.day) || w.day < 1 || w.day > 7 ||
          !Number.isInteger(w.startMinute) || w.startMinute < 0 || w.startMinute > 1439 ||
          !Number.isInteger(w.endMinute) || w.endMinute < 0 || w.endMinute > 1440 || w.startMinute === w.endMinute) throw new Error('Créneau hebdomadaire invalide.');
      return {day: w.day, startMinute: w.startMinute, endMinute: w.endMinute};
    }),
    dates: dates.map(w => {
      if (!w || !Number.isSafeInteger(w.startMs) || !Number.isSafeInteger(w.endMs) || w.startMs < 0 || w.endMs <= w.startMs || w.endMs > 8640000000000000) throw new Error('Période datée invalide.');
      return {startMs: w.startMs, endMs: w.endMs};
    })};
  if (!normalized.fullTime && !weekly.length && !dates.length) throw new Error('Ajoute au moins un créneau ou une période.');
  return normalized;
}
function isRankingActive(schedule, date = new Date()) {
  if (!schedule || schedule.fullTime === true) return true;
  try {
    const s = validateSchedule(schedule);
    if (s.dates.some(w => date.getTime() >= w.startMs && date.getTime() < w.endMs)) return true;
    const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {timeZone: s.timeZone,
      weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23'}).formatToParts(date).map(p => [p.type, p.value]));
    const day = WEEKDAYS[parts.weekday], minute = Number(parts.hour) * 60 + Number(parts.minute);
    return s.weekly.some(w => w.startMinute < w.endMinute ?
      day === w.day && minute >= w.startMinute && minute < w.endMinute :
      (day === w.day && minute >= w.startMinute) || (day === w.day % 7 + 1 && minute < w.endMinute));
  } catch { return false; } // A malformed schedule never opens play accidentally.
}
const SETTINGS = {name: 'nom', isPublic: 'visibilité', responseTimeSeconds: 'délai de réponse', eliminationMode: 'mode éliminatoire', rankingSchedule: 'horaires du classement', adminUid: 'administrateur'};
function changedSettings(before, after) {
  return Object.entries(SETTINGS).filter(([key]) => JSON.stringify(before[key] ?? null) !== JSON.stringify(after[key] ?? null)).map(([, label]) => label);
}
module.exports = {validateSchedule, isRankingActive, changedSettings};
