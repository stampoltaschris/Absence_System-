const db = require('../db');

/**
 * Ελέγχει αν ο εκπαιδευτικός έχει ανάθεση στο τμήμα.
 * Admin → πάντα true.
 */
async function teacherCanAccessClass(user, className) {
  if (!user) return false;
  if (user.role === 'admin') return true;
  if (!className || !user.id) return false;

  const result = await db.query(
    `SELECT 1
     FROM teacher_class_assignments
     WHERE teacher_id = $1 AND class_name = $2
     LIMIT 1`,
    [user.id, String(className).trim()]
  );
  return result.rows.length > 0;
}

/**
 * Τμήματα που έχουν ανατεθεί στον εκπαιδευτικό (με join στο classes).
 * Admin → όλα τα τμήματα.
 */
async function getClassesForUser(user) {
  if (user?.role === 'admin') {
    const all = await db.query('SELECT * FROM classes ORDER BY name ASC');
    return all.rows;
  }

  const assigned = await db.query(
    `SELECT c.*
     FROM classes c
     INNER JOIN teacher_class_assignments a ON a.class_name = c.name
     WHERE a.teacher_id = $1
     ORDER BY c.name ASC`,
    [user.id]
  );
  return assigned.rows;
}

module.exports = {
  teacherCanAccessClass,
  getClassesForUser,
};
