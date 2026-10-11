const express = require('express');
const router = express.Router();
const db = require('../db');
const nodemailer = require('nodemailer');
const { getAthensParts, getAthensDateString } = require('../utils/athens_time');
const { teacherCanAccessClass } = require('../utils/teacher_assignments');

const DEFAULT_ACTIVE_DAYS = {
  'Δευτέρα': true,
  'Τρίτη': true,
  'Τετάρτη': true,
  'Πέμπτη': true,
  'Παρασκευή': true,
  'Σάββατο': false,
  'Κυριακή': false,
};

const DEFAULT_TEACHING_HOURS = [
  { name: '1η ώρα', start: '08:15', end: '09:00' },
  { name: '2η ώρα', start: '09:05', end: '09:50' },
  { name: '3η ώρα', start: '10:00', end: '10:45' },
  { name: '4η ώρα', start: '10:55', end: '11:40' },
  { name: '5η ώρα', start: '11:50', end: '12:35' },
  { name: '6η ώρα', start: '12:40', end: '13:20' },
  { name: '7η ώρα', start: '13:25', end: '14:10' },
];

const GREEK_DAYS_BY_JS = [
  'Κυριακή',
  'Δευτέρα',
  'Τρίτη',
  'Τετάρτη',
  'Πέμπτη',
  'Παρασκευή',
  'Σάββατο',
];

function parseJsonField(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch (_) {
      return fallback;
    }
  }
  return value;
}

function parseTimeToMinutes(value) {
  if (!value || typeof value !== 'string') return null;
  const parts = value.trim().split(':');
  if (parts.length < 2) return null;
  const hours = parseInt(parts[0], 10);
  const minutes = parseInt(parts[1], 10);
  if (Number.isNaN(hours) || Number.isNaN(minutes)) return null;
  return hours * 60 + minutes;
}

/**
 * Έλεγχος σχολικού ωραρίου από schedule_settings (με defaults).
 * Ώρα πάντα Europe/Athens.
 */
async function checkSchoolSchedule() {
  const athens = getAthensParts();
  const dayName = GREEK_DAYS_BY_JS[athens.jsDay];
  const currentMinutes = athens.minutesOfDay;

  let forceTestMode = false;
  let activeDays = { ...DEFAULT_ACTIVE_DAYS };
  let teachingHours = DEFAULT_TEACHING_HOURS;

  try {
    const result = await db.query('SELECT * FROM schedule_settings WHERE id = 1');
    if (result.rows.length > 0) {
      const row = result.rows[0];
      forceTestMode = Boolean(row.force_test_mode);
      activeDays = parseJsonField(row.active_days, activeDays) || activeDays;
      const loadedHours = parseJsonField(row.teaching_hours, null);
      if (Array.isArray(loadedHours) && loadedHours.length > 0) {
        teachingHours = loadedHours;
      }
    }
  } catch (err) {
    console.error('⚠️ [SCHEDULE] Αποτυχία φόρτωσης ρυθμίσεων ωραρίου, χρήση defaults:', err.message);
  }

  const dayActive = activeDays[dayName] === true;

  let firstStart = Infinity;
  let lastEnd = -Infinity;
  for (const hour of teachingHours) {
    const start = parseTimeToMinutes(hour.start);
    const end = parseTimeToMinutes(hour.end);
    if (start != null) firstStart = Math.min(firstStart, start);
    if (end != null) lastEnd = Math.max(lastEnd, end);
  }

  if (!Number.isFinite(firstStart) || !Number.isFinite(lastEnd)) {
    firstStart = 8 * 60 + 15;
    lastEnd = 14 * 60 + 10;
  }

  const beforeOpen = currentMinutes < firstStart;
  const afterClose = currentMinutes >= lastEnd;
  const isOffHours = !dayActive || beforeOpen || afterClose;

  let reason = 'Εντός σχολικού ωραρίου';
  if (!dayActive) {
    reason = `Μη ενεργή ημέρα (${dayName})`;
  } else if (beforeOpen) {
    reason = 'Πριν την έναρξη του σχολικού ωραρίου';
  } else if (afterClose) {
    reason = 'Εκτός σχολικού ωραρίου (μετά το τέλος των μαθημάτων)';
  }

  return { isOffHours, reason, forceTestMode };
}

// ==========================================
// POST /api/attendance/submit
// Μαζική Υποβολή Απουσιών (με Transaction)
// ==========================================
router.post('/submit', async (req, res) => {
  // isTestMode από client ΔΕΝ γίνεται αποδεκτό — μόνο admin ή force_test_mode στη βάση
  const {
    attendanceList,
    userRole,
    className,
    period,
    absences,
    scheduleChangeConfirmed,
  } = req.body;
  
  // Υποστήριξη και για τις δύο μορφές δεδομένων
  let listToProcess = attendanceList;
  let targetClassName = className;
  let targetPeriod = period;
  let targetDate = getAthensDateString();

  if (!listToProcess && absences && Array.isArray(absences)) {
    listToProcess = absences.map(abs => {
      const isExcused = abs.isExcused === true || abs.is_excused === true || false;
      const isHourly =
        abs.isHourlyRemoval === true || abs.is_hourly_removal === true || false;
      const markedAbsent =
        abs.absent === true || abs.isAbsent === true || abs.is_absent === 1;
      // Δέσμευση από άλλον καθηγητή: ΔΕΝ καταχωρείται ως απουσία
      const isAbsent = isHourly ? 1 : (isExcused ? 0 : (markedAbsent ? 1 : 0));
      return {
        student_id: abs.studentId || abs.student_id,
        class_name: className,
        hour: period,
        is_absent: isAbsent,
        is_excused: isExcused && !isHourly,
        is_hourly_removal: isHourly,
        excused_by_teacher_id: abs.excusedByTeacherId || abs.excused_by_teacher_id || null,
        excuse_reason: abs.excuseReason || abs.excuse_reason || null,
        date: targetDate
      };
    });
  }

  if (listToProcess && listToProcess.length > 0) {
    targetClassName = listToProcess[0].class_name || listToProcess[0].className || targetClassName;
    targetPeriod = listToProcess[0].hour || listToProcess[0].school_hour || listToProcess[0].schoolHour || targetPeriod;
    targetDate = listToProcess[0].date || targetDate;
  }

  if (!listToProcess || listToProcess.length === 0) {
    return res.status(400).json({ message: 'Δεν δόθηκαν δεδομένα απουσιών.' });
  }

  const firstRecord = listToProcess[0];
  const rawTeacherId = req.user?.id || firstRecord?.teacher_id || firstRecord?.teacherId || req.body.teacherId;
  const targetTeacherId = parseInt(rawTeacherId, 10);

  if (isNaN(targetTeacherId)) {
    console.error("❌ [ATTENDANCE SUBMIT ERROR] Απουσιάζει το ID του εκπαιδευτικού.");
    return res.status(400).json({ message: 'Δεν βρέθηκε έγκυρο αναγνωριστικό εκπαιδευτικού.' });
  }

  const currentUsername = req.user?.username || 'teacher';
  const currentUserRole = req.user?.role || userRole;

  // Εκπαιδευτικός: μόνο δικά του τμήματα · άλλη ώρα μόνο με επιβεβαίωση αλλαγής προγράμματος
  if (currentUserRole !== 'admin') {
    const { getAthensWeekdayName } = require('../utils/athens_time');
    const allowed = await teacherCanAccessClass(req.user, targetClassName, {
      weekday: getAthensWeekdayName(),
      schoolHour: targetPeriod,
      scheduleChangeConfirmed: scheduleChangeConfirmed === true,
    });
    if (!allowed) {
      return res.status(403).json({
        message:
          `Δεν έχετε ανάθεση στο τμήμα ${targetClassName} ` +
          `για ${getAthensWeekdayName()} / ${targetPeriod}. ` +
          `Ξένα τμήματα δεν επιτρέπονται· για άλλη ώρα επιβεβαιώστε αλλαγή προγράμματος.`,
      });
    }
  }

  // Έλεγχος Ωραρίου & Δικαιωμάτων (από schedule_settings)
  const schedule = await checkSchoolSchedule();

  if (schedule.isOffHours) {
    let allowed =
      currentUserRole === 'admin' || schedule.forceTestMode === true;

    if (!allowed && targetTeacherId) {
      const userQuery = await db.query('SELECT role FROM users WHERE id = $1', [targetTeacherId]);
      if (userQuery.rows.length > 0 && userQuery.rows[0].role === 'admin') {
        allowed = true;
      }
    }

    if (!allowed) {
      return res.status(403).json({
        message:
          `Η υποβολή απουσιών δεν επιτρέπεται (${schedule.reason}). ` +
          `Δικαίωμα δοκιμαστικής υποβολής έχει ο Διαχειριστής ή ενεργό Test Mode στις ρυθμίσεις ωραρίου.`,
      });
    }
    console.log(
      `🧪 [TEST MODE] Υποβολή εκτός ωραρίου επιτρέπεται (${schedule.reason}` +
        `${schedule.forceTestMode ? ', forceTestMode=ON' : ', admin'}).`
    );
  }

  // 3. ΔΙΟΡΘΩΣΗ: Ασφαλής δέσμευση του Client (ώστε το server να μην κρασάρει αν είναι offline η DB)
  let client;
  try {
    client = await db.getClient();
    await client.query('BEGIN');

    // 0Α. Έλεγχος Διπλής υποβολής
    const existingClassCheck = await client.query(
      `SELECT id FROM attendance WHERE class_name = $1 AND date = $2 AND hour = $3 LIMIT 1`,
      [targetClassName, targetDate, targetPeriod]
    );

    if (existingClassCheck.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: `Έχουν ήδη υποβληθεί απουσίες για το τμήμα ${targetClassName} (${targetPeriod}) σήμερα!` });
    }

    // 0Β. Έλεγχος: Ο καθηγητής έχει ήδη υποβάλει απουσίες σε άλλο τμήμα την ίδια ώρα
    if (currentUserRole !== 'admin') {
      const existingTeacherCheck = await client.query(
        `SELECT DISTINCT class_name FROM attendance WHERE teacher_id = $1 AND date = $2 AND hour = $3 LIMIT 1`,
        [targetTeacherId, targetDate, targetPeriod]
      );

      if (existingTeacherCheck.rows.length > 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ 
          message: `Έχεις ήδη υποβάλει απουσίες για το τμήμα ${existingTeacherCheck.rows[0].class_name} αυτή την ώρα (${targetPeriod})!` 
        });
      }
    }

    // Ανάκτηση Ρυθμίσεων SMTP
    const emailRes = await client.query("SELECT value FROM settings WHERE key IN ('smtp_email', 'server_email') ORDER BY key DESC");
    const passRes = await client.query("SELECT value FROM settings WHERE key IN ('smtp_password', 'server_password') ORDER BY key DESC");
    const smtpUser = emailRes.rows[0]?.value || '';
    const smtpPass = passRes.rows[0]?.value || '';

    let transporter = null;
    if (smtpUser && smtpPass) {
      transporter = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 587,
        secure: false,
        auth: { user: smtpUser, pass: smtpPass },
        tls: { rejectUnauthorized: false }
      });
    }

    const emailTasks = [];
    const recordsToInsert = [];

    // Επεξεργασία Λίστας Απουσιών
    for (let record of listToProcess) {
      const studentId = parseInt(record.student_id || record.studentId || record.id, 10);
      const clsName = record.class_name || record.className || targetClassName || 'Αγνώστου Τμήματος';
      const date = record.date || targetDate;
      const hour = record.hour || record.school_hour || record.schoolHour || targetPeriod || '1η ώρα';
      
      const isAbsentRaw = record.is_absent !== undefined ? record.is_absent : (record.isAbsent !== undefined ? record.isAbsent : record.absent);
      let isAbsent = (isAbsentRaw === true || isAbsentRaw === 1 || isAbsentRaw === 'true') ? 1 : 0;
      const wantsHourly =
        record.is_hourly_removal === true || record.isHourlyRemoval === true;
      const wantsExcused =
        record.is_excused === true || record.isExcused === true;

      // Ωριαία απομάκρυνση: απών, χωρίς email
      const isHourlyRemoval = wantsHourly && !wantsExcused;
      // Δέσμευση από άλλον καθηγητή: σημείωση στη βάση, ΟΧΙ απουσία, ΟΧΙ email
      const isExcusedBool = wantsExcused && !isHourlyRemoval;

      if (isHourlyRemoval) {
        isAbsent = 1;
      } else if (isExcusedBool) {
        isAbsent = 0;
      }
      
      let excusedByTeacherId = null;
      if (isExcusedBool) {
        let rawTId = record.excused_by_teacher_id || record.excusedByTeacherId;
        excusedByTeacherId = parseInt(rawTId, 10) || targetTeacherId;
      }

      const excuseReason = isHourlyRemoval
        ? 'Ωριαία απομάκρυνση'
        : (isExcusedBool ? (record.excuse_reason || record.excuseReason || 'Δεσμευμένος') : null);
      let emailStatus = 'PRESENT';

      if (isHourlyRemoval) {
        emailStatus = 'HOURLY_SKIPPED';
      } else if (isExcusedBool) {
        // Καταχωρείται μόνο η δέσμευση — όχι απουσία, όχι email
        emailStatus = 'RESERVED_NO_ABSENCE';
      } else if (isAbsent === 1) {
        if (!transporter) {
          emailStatus = 'FAILED';
        } else {
          const studentQuery = await client.query('SELECT name, email FROM students WHERE id = $1', [studentId]);
          const student = studentQuery.rows[0];

          if (student && student.email) {
            const mailPromise = transporter.sendMail({
              from: `"Σύστημα Απουσιών" <${smtpUser}>`,
              to: student.email,
              subject: `Ενημέρωση Απουσίας ${schedule.isOffHours ? '[ΔΟΚΙΜΑΣΤΙΚΗ]' : ''} - ${student.name}`,
              text: `Αγαπητέ κηδεμόνα,\n\nΣας ενημερώνουμε ότι ο/η μαθητής/τρια ${student.name} καταχωρήθηκε ως απών/ούσα την ημερομηνία ${date}, την ${hour} διδακτική ώρα στο τμήμα ${clsName}.\n\nΜε εκτίμηση,\nΗ Διεύθυνση του Σχολείου`,
            }).then(() => ({ studentId, status: 'SENT' }))
              .catch(err => {
                console.error(`⚠️ Αποτυχία αποστολής email για ID ${studentId}:`, err.message);
                return { studentId, status: 'FAILED' };
              });

            emailTasks.push(mailPromise);
            emailStatus = 'SENT';
          } else {
            emailStatus = 'FAILED';
          }
        }
      }

      recordsToInsert.push({
        studentId,
        teacherId: targetTeacherId,
        className: clsName,
        date,
        hour,
        isAbsent,
        isExcused: isExcusedBool,
        isHourlyRemoval,
        excusedByTeacherId,
        excuseReason,
        emailStatus,
      });
    }

    // 2. Εγγραφή όλων των Μαθητών στη Βάση
    for (let item of recordsToInsert) {
      await client.query(
        `INSERT INTO attendance (
          student_id, teacher_id, class_name, date, hour,
          is_absent, is_excused, is_hourly_removal,
          excused_by_teacher_id, excuse_reason, email_status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [
          item.studentId,
          item.teacherId,
          item.className,
          item.date,
          item.hour,
          item.isAbsent,
          item.isExcused,
          item.isHourlyRemoval,
          item.excusedByTeacherId,
          item.excuseReason,
          item.emailStatus,
        ]
      );
    }

    // 3. Εγγραφή στο Submitted Attendance
    await client.query(
      `INSERT INTO submitted_attendance (class_name, school_hour, date, username) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
      [targetClassName, targetPeriod, targetDate, currentUsername]
    );

    // ✅ ΟΡΙΣΤΙΚΟΠΟΙΗΣΗ TRANSACTION
    await client.query('COMMIT');

    // 4. Αυτόματη Αποδέσμευση Τμήματος (Ασφαλές Try-Catch)
    try {
      await db.query(
        'DELETE FROM class_locks WHERE class_name = $1 AND school_hour = $2',
        [targetClassName, targetPeriod]
      );
    } catch (e) {
      console.error('Warning: unlock after submit failed:', e.message);
    }

    // 2. ΔΙΟΡΘΩΣΗ: Σωστό κλείσιμο του transporter για αποφυγή Memory Leaks (Socket Exhaustion)
    if (emailTasks.length > 0) {
      Promise.allSettled(emailTasks).then(() => {
        if (transporter) transporter.close();
      }).catch(err => {
        console.error("⚠️ Σφάλμα background email:", err.message);
        if (transporter) transporter.close();
      });
    } else {
      if (transporter) transporter.close();
    }

    const responseMsg = schedule.isOffHours 
      ? '⚠️ [ΔΟΚΙΜΑΣΤΙΚΗ ΛΕΙΤΟΥΡΓΙΑ] Οι απουσίες καταχωρίστηκαν επιτυχώς!'
      : 'Οι απουσίες καταχωρίστηκαν και τα email αποστέλλονται!';

    res.json({ success: true, message: responseMsg, isTestMode: schedule.isOffHours });

  } catch (err) {
    if (client) await client.query('ROLLBACK');
    console.error("❌ [SUBMIT ERROR]:", err.message);
    res.status(500).json({ message: `Σφάλμα Βάσης: ${err.message}` });
  } finally {
    if (client) client.release();
  }
});

// ==========================================
// GET /api/attendance/records
// Υπάρχουσες καταχωρίσεις τμήματος (για ωριαία απομάκρυνση)
// ==========================================
router.get('/records', async (req, res) => {
  const className = req.query.className;
  const period = req.query.period || req.query.hour;
  const date = req.query.date || getAthensDateString();

  if (!className || !period) {
    return res.status(400).json({ message: 'Απαιτούνται className και period.' });
  }

  if (req.user?.role !== 'admin') {
    const { getAthensWeekdayName } = require('../utils/athens_time');
    const confirmed =
      req.query.scheduleChangeConfirmed === 'true' ||
      req.query.scheduleChangeConfirmed === '1';
    const allowed = await teacherCanAccessClass(req.user, className, {
      weekday: getAthensWeekdayName(),
      schoolHour: period,
      scheduleChangeConfirmed: confirmed,
    });
    if (!allowed) {
      return res.status(403).json({
        message:
          `Δεν έχετε ανάθεση στο τμήμα ${className} ` +
          `για ${getAthensWeekdayName()} / ${period}.`,
      });
    }
  }

  try {
    const result = await db.query(
      `SELECT a.student_id, a.teacher_id, a.is_absent, a.is_excused, a.is_hourly_removal,
              a.excuse_reason, a.email_status, s.name AS student_name, s.email AS student_email
       FROM attendance a
       JOIN students s ON s.id = a.student_id
       WHERE a.class_name = $1 AND a.date = $2 AND a.hour = $3
       ORDER BY s.name ASC`,
      [className, date, period]
    );

    res.json({
      success: true,
      className,
      date,
      period,
      records: result.rows.map((row) => ({
        studentId: row.student_id,
        studentName: row.student_name,
        guardianEmail: row.student_email || '',
        teacherId: row.teacher_id,
        isAbsent: row.is_absent === true || row.is_absent === 1,
        isExcused: row.is_excused === true,
        isHourlyRemoval: row.is_hourly_removal === true,
        excuseReason: row.excuse_reason,
        emailStatus: row.email_status,
      })),
    });
  } catch (err) {
    console.error('❌ Σφάλμα λήψης records attendance:', err.message);
    res.status(500).json({ message: err.message });
  }
});

// ==========================================
// POST /api/attendance/hourly-removal
// Μόνο ωριαίες απομακρύνσεις σε ήδη υποβληθέν τμήμα (χωρίς email)
// ==========================================
router.post('/hourly-removal', async (req, res) => {
  const { className, period, studentIds } = req.body;
  const targetDate = getAthensDateString();
  const targetTeacherId = parseInt(req.user?.id, 10);
  const currentUserRole = req.user?.role;

  if (!className || !period) {
    return res.status(400).json({
      success: false,
      message: 'Απαιτούνται όνομα τμήματος και διδακτική ώρα.',
    });
  }

  const ids = Array.isArray(studentIds)
    ? studentIds.map((id) => parseInt(id, 10)).filter((id) => !Number.isNaN(id))
    : [];

  if (ids.length === 0) {
    return res.status(400).json({
      success: false,
      message: 'Επιλέξτε τουλάχιστον έναν μαθητή για ωριαία απομάκρυνση.',
    });
  }

  if (Number.isNaN(targetTeacherId)) {
    return res.status(401).json({ success: false, message: 'Μη έγκυρος χρήστης.' });
  }

  if (currentUserRole !== 'admin') {
    const { getAthensWeekdayName } = require('../utils/athens_time');
    const allowed = await teacherCanAccessClass(req.user, className, {
      weekday: getAthensWeekdayName(),
      schoolHour: period,
      scheduleChangeConfirmed: req.body?.scheduleChangeConfirmed === true,
    });
    if (!allowed) {
      return res.status(403).json({
        success: false,
        message:
          `Δεν έχετε ανάθεση στο τμήμα ${className} ` +
          `για ${getAthensWeekdayName()} / ${period}.`,
      });
    }
  }

  let client;
  try {
    client = await db.getClient();
    await client.query('BEGIN');

    const existing = await client.query(
      `SELECT teacher_id FROM attendance
       WHERE class_name = $1 AND date = $2 AND hour = $3
       LIMIT 1`,
      [className, targetDate, period]
    );

    if (existing.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: 'Δεν έχουν υποβληθεί ακόμα απουσίες για αυτό το τμήμα. Κάντε πρώτα κανονική υποβολή.',
      });
    }

    const originalTeacherId = existing.rows[0].teacher_id;
    if (currentUserRole !== 'admin' && originalTeacherId !== targetTeacherId) {
      await client.query('ROLLBACK');
      return res.status(403).json({
        success: false,
        message: 'Μόνο ο εκπαιδευτικός που υπέβαλε τις απουσίες (ή admin) μπορεί να καταχωρήσει ωριαία απομάκρυνση.',
      });
    }

    let updatedCount = 0;
    const skipped = [];

    for (const studentId of ids) {
      const rowRes = await client.query(
        `SELECT is_absent, is_excused, is_hourly_removal
         FROM attendance
         WHERE student_id = $1 AND class_name = $2 AND date = $3 AND hour = $4`,
        [studentId, className, targetDate, period]
      );

      if (rowRes.rows.length === 0) {
        skipped.push(studentId);
        continue;
      }

      const row = rowRes.rows[0];
      const wasAbsent = row.is_absent === true || row.is_absent === 1;
      const wasHourly = row.is_hourly_removal === true;
      const wasExcused = row.is_excused === true;

      // Επιτρέπεται μόνο σε παρόντες (όχι ήδη απόντες / δεσμευμένους)
      if (wasHourly) {
        updatedCount++; // ήδη καταχωρημένο
        continue;
      }
      if (wasAbsent || wasExcused) {
        skipped.push(studentId);
        continue;
      }

      await client.query(
        `UPDATE attendance SET
           is_absent = 1,
           is_hourly_removal = TRUE,
           is_excused = FALSE,
           excused_by_teacher_id = NULL,
           excuse_reason = 'Ωριαία απομάκρυνση',
           email_status = 'HOURLY_SKIPPED'
         WHERE student_id = $1 AND class_name = $2 AND date = $3 AND hour = $4`,
        [studentId, className, targetDate, period]
      );
      updatedCount++;
    }

    await client.query('COMMIT');

    try {
      await db.query(
        'DELETE FROM class_locks WHERE class_name = $1 AND school_hour = $2',
        [className, period]
      );
    } catch (_) {}

    res.json({
      success: true,
      message:
        updatedCount > 0
          ? `Καταχωρήθηκαν ${updatedCount} ωριαίες απομακρύνσεις (χωρίς email).`
          : 'Δεν έγινε καμία νέα καταχώριση.',
      updatedCount,
      skippedCount: skipped.length,
    });
  } catch (err) {
    if (client) await client.query('ROLLBACK');
    console.error('❌ [HOURLY REMOVAL ERROR]:', err.message);
    res.status(500).json({ success: false, message: err.message });
  } finally {
    if (client) client.release();
  }
});

// ==========================================
// GET /api/attendance/submitted
// Λήψη Υποβληθέντων Τμημάτων (Live Monitor)
// ==========================================
router.get('/submitted', async (req, res) => {
  const { date, schoolHour } = req.query;
  try {
    const result = await db.query(
      'SELECT class_name FROM submitted_attendance WHERE date = $1 AND school_hour = $2',
      [date, schoolHour]
    );
    const classNames = result.rows.map(r => r.class_name);
    res.json(classNames);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ==========================================
// GET /api/attendance/daily-summary
// Συγκεντρωτική Αναφορά Ημέρας (Live Monitor)
// ==========================================
router.get('/daily-summary', async (req, res) => {
  const targetDate = req.query.date || getAthensDateString();

  try {
    const query = `
      SELECT a.class_name, a.hour, u.name AS teacher_name, s.name AS student_name,
             a.is_absent, a.is_excused, a.is_hourly_removal, a.excuse_reason
      FROM attendance a
      LEFT JOIN users u ON a.teacher_id = u.id
      LEFT JOIN students s ON a.student_id = s.id
      WHERE a.date = $1
      ORDER BY a.class_name ASC, a.hour ASC, s.name ASC
    `;

    const result = await db.query(query, [targetDate]);
    const summaryMap = {};

    result.rows.forEach(row => {
      const key = `${row.class_name}_${row.hour}`;
      if (!summaryMap[key]) {
        summaryMap[key] = {
          className: row.class_name,
          hour: row.hour,
          teacherName: row.teacher_name || 'Άγνωστος Εκπαιδευτικός',
          absentStudents: [],
          reservedStudents: [],
          totalStudents: 0
        };
      }
      summaryMap[key].totalStudents += 1;
      if (row.is_excused && !(row.is_absent === 1 || row.is_absent === true)) {
        summaryMap[key].reservedStudents.push(
          `${row.student_name}${row.excuse_reason ? ' (' + row.excuse_reason + ')' : ''}`
        );
      } else if (row.is_absent === 1 || row.is_absent === true) {
        let studentText = row.student_name;
        if (row.is_hourly_removal) {
          studentText += ' (Ωριαία απομάκρυνση)';
        }
        summaryMap[key].absentStudents.push(studentText);
      }
    });

    res.json(Object.values(summaryMap));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;