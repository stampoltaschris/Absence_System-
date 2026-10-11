/**
 * Αξιόπιστη ώρα/ημερομηνία Europe/Athens
 * (αποφεύγει το bug: toLocaleString → new Date → toISOString που δίνει χθεσινή ημερομηνία 00:00–02:59)
 */

function getAthensParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Athens',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    weekday: 'short',
    hourCycle: 'h23',
  }).formatToParts(date);

  const map = {};
  for (const p of parts) {
    if (p.type !== 'literal') map[p.type] = p.value;
  }

  const year = map.year;
  const month = map.month;
  const day = map.day;
  const hour = parseInt(map.hour, 10);
  const minute = parseInt(map.minute, 10);
  const second = parseInt(map.second, 10);

  // weekday: Mon, Tue, ... (en-GB short)
  const weekdayMap = {
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
    Sun: 0,
  };
  const jsDay = weekdayMap[map.weekday] ?? 0;

  return {
    dateString: `${year}-${month}-${day}`,
    year: parseInt(year, 10),
    month: parseInt(month, 10),
    day: parseInt(day, 10),
    hour,
    minute,
    second,
    jsDay,
    minutesOfDay: hour * 60 + minute,
  };
}

function getAthensDateString(date = new Date()) {
  return getAthensParts(date).dateString;
}

/** Ελληνικό όνομα ημέρας (Δευτέρα…Κυριακή) σε ώρα Athens. */
function getAthensWeekdayName(date = new Date()) {
  const { jsDay } = getAthensParts(date);
  const names = [
    'Κυριακή',
    'Δευτέρα',
    'Τρίτη',
    'Τετάρτη',
    'Πέμπτη',
    'Παρασκευή',
    'Σάββατο',
  ];
  return names[jsDay] || 'Κυριακή';
}

module.exports = {
  getAthensParts,
  getAthensDateString,
  getAthensWeekdayName,
};
