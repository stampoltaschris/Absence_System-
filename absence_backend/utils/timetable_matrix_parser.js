/**
 * Parser ωρολογίου σε μορφή πίνακα (aSc Timetables κ.λπ.):
 * στήλη A = όνομα εκπαιδευτικού,
 * στήλες = Δευτέρα…Παρασκευή × ώρες 1–7,
 * κελί = κωδικός τμήματος.
 */
const {
  normalizeWeekday,
  normalizeSchoolHour,
  normalizeClassName,
} = require('./teacher_assignments');

function cellStr(v) {
  if (v == null) return '';
  return String(v).trim();
}

function looksLikeJunkTeacherName(name) {
  const n = name.toLocaleLowerCase('el-GR');
  if (!n) return true;
  if (n.length < 3) return true;
  const junk = [
    'εκπαιδευτικ',
    'ονόματ',
    'ονομα',
    'ωρολογ',
    'συνολικο',
    'ισχυει',
    'δημιουργια',
    'γελο',
    'teacher',
    'name',
  ];
  return junk.some((w) => n.includes(w));
}

/**
 * Εντοπίζει αν το sheet μοιάζει με matrix ωρολόγιο.
 */
function detectMatrixLayout(rows) {
  let dayRowIdx = -1;
  let periodRowIdx = -1;
  let maxDayHits = 0;
  let maxPeriodHits = 0;

  const scan = Math.min(10, rows.length);
  for (let r = 0; r < scan; r++) {
    const row = rows[r] || [];
    let dayHits = 0;
    let periodHits = 0;
    for (const cell of row) {
      if (normalizeWeekday(cellStr(cell))) dayHits += 1;
      const raw = cellStr(cell);
      if (/^[1-7]$/.test(raw)) periodHits += 1;
      else if (normalizeSchoolHour(raw) && /^\d/.test(raw)) periodHits += 1;
    }
    if (dayHits >= 2 && dayHits > maxDayHits) {
      maxDayHits = dayHits;
      dayRowIdx = r;
    }
    if (periodHits >= 5 && periodHits > maxPeriodHits) {
      maxPeriodHits = periodHits;
      periodRowIdx = r;
    }
  }

  if (dayRowIdx < 0 || periodRowIdx < 0) return null;
  // Περίοδοι συνήθως αμέσως κάτω (ή στην ίδια περιοχή) από τις ημέρες
  if (Math.abs(periodRowIdx - dayRowIdx) > 4) return null;

  return { dayRowIdx, periodRowIdx };
}

/**
 * Χάρτης στήλης → { weekday, schoolHour }
 * Οι συγχωνευμένες κεφαλίδες ημερών γεμίζουν προς τα δεξιά (forward-fill).
 */
function buildColumnMeta(rows, dayRowIdx, periodRowIdx) {
  const dayRow = rows[dayRowIdx] || [];
  const periodRow = rows[periodRowIdx] || [];
  let maxCols = Math.max(dayRow.length, periodRow.length);
  for (let r = periodRowIdx + 1; r < Math.min(periodRowIdx + 5, rows.length); r++) {
    maxCols = Math.max(maxCols, (rows[r] || []).length);
  }

  let currentDay = null;
  const colMeta = new Array(maxCols).fill(null);

  for (let c = 0; c < maxCols; c++) {
    const dayHit = normalizeWeekday(cellStr(dayRow[c]));
    if (dayHit) currentDay = dayHit;

    const hour = normalizeSchoolHour(cellStr(periodRow[c]));
    // Στήλη 0 = ονόματα — αγνοείται
    if (c === 0) continue;
    if (currentDay && hour) {
      colMeta[c] = { weekday: currentDay, schoolHour: hour };
    }
  }

  const mapped = colMeta.filter(Boolean).length;
  return mapped >= 5 ? colMeta : null;
}

/**
 * @returns {Map<string, { fullName: string, slots: Array<{weekday, schoolHour, className}> }> | null}
 */
function parseTimetableMatrix(rows) {
  if (!rows || rows.length < 3) return null;

  const layout = detectMatrixLayout(rows);
  if (!layout) return null;

  const colMeta = buildColumnMeta(rows, layout.dayRowIdx, layout.periodRowIdx);
  if (!colMeta) return null;

  const pendingByTeacher = new Map();
  const dataStart = Math.max(layout.dayRowIdx, layout.periodRowIdx) + 1;

  for (let r = dataStart; r < rows.length; r++) {
    const row = rows[r] || [];
    const fullName = cellStr(row[0]).replace(/\s+/g, ' ');
    if (!fullName || looksLikeJunkTeacherName(fullName)) continue;

    // Αν η πρώτη στήλη είναι αριθμός ώρας, δεν είναι γραμμή καθηγητή
    if (/^[1-7]$/.test(fullName)) continue;
    if (normalizeWeekday(fullName)) continue;

    const nameKey = fullName.toLocaleLowerCase('el-GR');
    if (!pendingByTeacher.has(nameKey)) {
      pendingByTeacher.set(nameKey, { fullName, slots: [] });
    }
    const entry = pendingByTeacher.get(nameKey);

    for (let c = 1; c < Math.max(row.length, colMeta.length); c++) {
      const meta = colMeta[c];
      if (!meta) continue;
      const className = normalizeClassName(cellStr(row[c]));
      if (!className) continue;
      // Αγνόηση καθαρά αριθμητικών κελιών
      if (/^\d+$/.test(className)) continue;

      entry.slots.push({
        weekday: meta.weekday,
        schoolHour: meta.schoolHour,
        className,
      });
    }
  }

  // Χωρίς κανένα slot → δεν είναι έγκυρο matrix
  let totalSlots = 0;
  for (const v of pendingByTeacher.values()) totalSlots += v.slots.length;
  if (totalSlots === 0 || pendingByTeacher.size === 0) return null;

  return pendingByTeacher;
}

/**
 * Επίπεδη μορφή: Ονοματεπώνυμο | Ημέρα | Ώρα | Τμήμα
 * @returns {{ pendingByTeacher: Map, skipped: Array, format: string }}
 */
function parseLongFormatAssignments(rows) {
  const pendingByTeacher = new Map();
  const skipped = [];

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (!row || row.length === 0) continue;

    const fullNameRaw = cellStr(row[0]);
    const dayRaw = cellStr(row[1]);
    const hourRaw = cellStr(row[2]);
    const classRaw = cellStr(row[3]);

    if (!fullNameRaw && !dayRaw && !hourRaw && !classRaw) continue;

    if (i === 0) {
      const joined = [fullNameRaw, dayRaw, hourRaw, classRaw]
        .join(' ')
        .toLocaleLowerCase('el-GR');
      if (
        joined.includes('ονομα') ||
        joined.includes('ημερ') ||
        joined.includes('τμημα') ||
        joined.includes('name')
      ) {
        continue;
      }
    }

    if (!fullNameRaw) {
      skipped.push({ row: i + 1, reason: 'Λείπει ονοματεπώνυμο' });
      continue;
    }

    const weekday = normalizeWeekday(dayRaw);
    const schoolHour = normalizeSchoolHour(hourRaw);
    const className = normalizeClassName(classRaw);

    if (!weekday) {
      skipped.push({
        row: i + 1,
        reason: 'Μη έγκυρη ημέρα',
        name: fullNameRaw,
        day: dayRaw,
      });
      continue;
    }
    if (!schoolHour) {
      skipped.push({
        row: i + 1,
        reason: 'Μη έγκυρη ώρα (1η–7η)',
        name: fullNameRaw,
        hour: hourRaw,
      });
      continue;
    }
    if (!className) {
      skipped.push({
        row: i + 1,
        reason: 'Λείπει τμήμα',
        name: fullNameRaw,
      });
      continue;
    }

    const fullName = fullNameRaw.replace(/\s+/g, ' ');
    const nameKey = fullName.toLocaleLowerCase('el-GR');
    if (!pendingByTeacher.has(nameKey)) {
      pendingByTeacher.set(nameKey, { fullName, slots: [] });
    }
    pendingByTeacher.get(nameKey).slots.push({
      weekday,
      schoolHour,
      className,
    });
  }

  return { pendingByTeacher, skipped, format: 'long' };
}

/**
 * Αυτόματη αναγνώριση μορφής Excel.
 */
function parseAssignmentsWorkbook(rows) {
  const matrix = parseTimetableMatrix(rows);
  if (matrix) {
    return {
      pendingByTeacher: matrix,
      skipped: [],
      format: 'matrix',
    };
  }
  return parseLongFormatAssignments(rows);
}

module.exports = {
  detectMatrixLayout,
  parseTimetableMatrix,
  parseLongFormatAssignments,
  parseAssignmentsWorkbook,
};
