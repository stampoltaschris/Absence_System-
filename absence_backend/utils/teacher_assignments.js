const db = require('../db');
const { getAthensWeekdayName } = require('./athens_time');

const WEEKDAYS = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή'];

function isTeachingHourName(hourStatus) {
  if (!hourStatus || typeof hourStatus !== 'string') return false;
  return hourStatus.includes('ώρα') && !hourStatus.includes('Διάλειμμα');
}

function normalizeWeekday(raw) {
  const s = String(raw || '')
    .trim()
    .toLocaleLowerCase('el-GR')
    .normalize('NFC');
  const map = {
    δευτερα: 'Δευτέρα',
    δευτέρα: 'Δευτέρα',
    monday: 'Δευτέρα',
    mon: 'Δευτέρα',
    τριτη: 'Τρίτη',
    τρίτη: 'Τρίτη',
    tuesday: 'Τρίτη',
    tue: 'Τρίτη',
    τεταρτη: 'Τετάρτη',
    τετάρτη: 'Τετάρτη',
    wednesday: 'Τετάρτη',
    wed: 'Τετάρτη',
    πεμπτη: 'Πέμπτη',
    πέμπτη: 'Πέμπτη',
    thursday: 'Πέμπτη',
    thu: 'Πέμπτη',
    παρασκευη: 'Παρασκευή',
    παρασκευή: 'Παρασκευή',
    friday: 'Παρασκευή',
    fri: 'Παρασκευή',
  };
  if (map[s]) return map[s];
  for (const d of WEEKDAYS) {
    if (d.toLocaleLowerCase('el-GR') === s) return d;
  }
  return null;
}

function normalizeSchoolHour(raw) {
  const s = String(raw || '')
    .trim()
    .toLocaleLowerCase('el-GR');
  const m = s.match(/(\d{1,2})/);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  if (n < 1 || n > 7) return null;
  return `${n}η ώρα`;
}

function normalizeClassName(raw) {
  let s = String(raw || '')
    .trim()
    .replace(/\s+/g, '');
  if (!s) return '';
  const latinToGreek = {
    A: 'Α',
    B: 'Β',
    E: 'Ε',
    Z: 'Ζ',
    H: 'Η',
    I: 'Ι',
    K: 'Κ',
    M: 'Μ',
    N: 'Ν',
    O: 'Ο',
    P: 'Ρ',
    T: 'Τ',
    Y: 'Υ',
    X: 'Χ',
  };
  s = s
    .toUpperCase()
    .split('')
    .map((ch) => latinToGreek[ch] || ch)
    .join('');
  return s.toLocaleUpperCase('el-GR');
}

async function isForceTestMode() {
  try {
    const result = await db.query(
      'SELECT force_test_mode FROM schedule_settings WHERE id = 1'
    );
    return Boolean(result.rows[0]?.force_test_mode);
  } catch (_) {
    return false;
  }
}

/** Τμήμα εμφανίζεται στο ωρολόγιο του καθηγητή οποιαδήποτε μέρα/ώρα. */
async function teacherOwnsClass(teacherId, className) {
  const cls = normalizeClassName(className);
  const result = await db.query(
    `SELECT 1
     FROM teacher_class_assignments
     WHERE teacher_id = $1 AND class_name = $2
     LIMIT 1`,
    [teacherId, cls]
  );
  return result.rows.length > 0;
}

/** Τμήμα στο ωρολόγιο του καθηγητή για συγκεκριμένη ημέρα (οποιαδήποτε ώρα). */
async function teacherOwnsClassOnWeekday(teacherId, className, weekday) {
  const cls = normalizeClassName(className);
  const result = await db.query(
    `SELECT 1
     FROM teacher_class_assignments
     WHERE teacher_id = $1 AND weekday = $2 AND class_name = $3
     LIMIT 1`,
    [teacherId, weekday, cls]
  );
  return result.rows.length > 0;
}

async function teacherHasExactSlot(teacherId, className, weekday, schoolHour) {
  const cls = normalizeClassName(className);
  const hour = normalizeSchoolHour(schoolHour) || schoolHour;
  const result = await db.query(
    `SELECT 1
     FROM teacher_class_assignments
     WHERE teacher_id = $1
       AND weekday = $2
       AND school_hour = $3
       AND class_name = $4
     LIMIT 1`,
    [teacherId, weekday, hour, cls]
  );
  return result.rows.length > 0;
}

/**
 * Πρόσβαση τμήματος:
 * - Admin → πάντα
 * - Ακριβές slot ημέρα+ώρα → ναι
 * - Δικό του τμήμα σήμερα, άλλη ώρα → μόνο με scheduleChangeConfirmed
 * - Εκτός διδακτικής ώρας + forceTestMode → οποιοδήποτε τμήμα του ωρολογίου του
 * - Ξένο τμήμα → ποτέ
 */
async function teacherCanAccessClass(user, className, context = {}) {
  if (!user) return false;
  if (user.role === 'admin') return true;
  if (!className || !user.id) return false;

  const schoolHour = context.schoolHour || context.currentHour || null;
  const weekday = context.weekday || getAthensWeekdayName();
  const confirmed = context.scheduleChangeConfirmed === true;

  if (isTeachingHourName(schoolHour)) {
    if (await teacherHasExactSlot(user.id, className, weekday, schoolHour)) {
      return true;
    }
    // Ελαστικότητα ώρας: μόνο δικό του τμήμα της ημέρας + ρητή επιβεβαίωση
    if (
      confirmed &&
      (await teacherOwnsClassOnWeekday(user.id, className, weekday))
    ) {
      return true;
    }
    return false;
  }

  if (await isForceTestMode()) {
    return teacherOwnsClass(user.id, className);
  }

  return false;
}

/**
 * Τμήματα ορατά:
 * - Admin: όλα
 * - Διδακτική ώρα: όλα τα τμήματα που διδάσκει σήμερα (οποιαδήποτε ώρα),
 *   με flag assignedThisHour για το UI
 * - Εκτός ώρας + test mode: όλα τα τμήματα του ωρολογίου του
 */
async function getClassesForUser(user, context = {}) {
  if (user?.role === 'admin') {
    const all = await db.query('SELECT * FROM classes ORDER BY name ASC');
    return all.rows.map((row) => ({ ...row, assignedThisHour: true }));
  }

  const schoolHour = context.schoolHour || context.currentHour || null;
  const weekday = context.weekday || getAthensWeekdayName();
  const hour = normalizeSchoolHour(schoolHour) || schoolHour;

  if (isTeachingHourName(schoolHour)) {
    const assigned = await db.query(
      `SELECT DISTINCT ON (c.id)
         c.*,
         EXISTS (
           SELECT 1
           FROM teacher_class_assignments a2
           WHERE a2.teacher_id = $1
             AND a2.weekday = $2
             AND a2.school_hour = $3
             AND a2.class_name = c.name
         ) AS assigned_this_hour
       FROM classes c
       INNER JOIN teacher_class_assignments a ON a.class_name = c.name
       WHERE a.teacher_id = $1
         AND a.weekday = $2
       ORDER BY c.id, c.name ASC`,
      [user.id, weekday, hour]
    );
    return assigned.rows
      .map((row) => ({
        ...row,
        assignedThisHour: Boolean(row.assigned_this_hour),
      }))
      .sort((a, b) => String(a.name).localeCompare(String(b.name), 'el'));
  }

  if (await isForceTestMode()) {
    const assigned = await db.query(
      `SELECT DISTINCT c.*
       FROM classes c
       INNER JOIN teacher_class_assignments a ON a.class_name = c.name
       WHERE a.teacher_id = $1
       ORDER BY c.name ASC`,
      [user.id]
    );
    return assigned.rows.map((row) => ({ ...row, assignedThisHour: false }));
  }

  return [];
}

module.exports = {
  WEEKDAYS,
  isTeachingHourName,
  normalizeWeekday,
  normalizeSchoolHour,
  normalizeClassName,
  isForceTestMode,
  teacherOwnsClass,
  teacherOwnsClassOnWeekday,
  teacherHasExactSlot,
  teacherCanAccessClass,
  getClassesForUser,
  getAthensWeekdayName,
};
