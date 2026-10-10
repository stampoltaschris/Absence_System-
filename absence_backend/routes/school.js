const express = require('express');
const router = express.Router();
const multer = require('multer');
const xlsx = require('xlsx');
const db = require('../db');
const authenticateToken = require('../middleware/auth'); // Προσθήκη για ασφάλεια
const { getAthensDateString } = require('../utils/athens_time');
const {
  getClassesForUser,
  teacherCanAccessClass,
} = require('../utils/teacher_assignments');

// Ρύθμιση του multer για προσωρινή αποθήκευση του αρχείου στη μνήμη (RAM) με όριο 5MB
const upload = multer({ 
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 } // Όριο 5MB για τα αρχεία Excel
});

// ==========================================
// 1. ΤΜΗΜΑΤΑ (CLASSES)
// ==========================================

// Παλιά locks (π.χ. tablet που έκλεισε απότομα) λήγουν μετά από 45 λεπτά
const LOCK_TTL = "INTERVAL '45 minutes'";

async function purgeStaleLocks() {
  await db.query(`DELETE FROM class_locks WHERE locked_at < NOW() - ${LOCK_TTL}`);
}

// GET /api/school/classes
// Λήψη όλων των τμημάτων (Προστατευμένο)
router.get('/classes', authenticateToken, async (req, res) => {
  const currentHour = req.query.currentHour || '1η ώρα';
  const today = getAthensDateString();

  try {
    await purgeStaleLocks();

    // Εκπαιδευτικός: μόνο τα τμήματα που του έχουν ανατεθεί · Admin: όλα
    const classes = await getClassesForUser(req.user);

    const submittedRes = await db.query(
      'SELECT class_name FROM submitted_attendance WHERE date = $1 AND school_hour = $2',
      [today, currentHour]
    );
    const submittedSet = new Set(submittedRes.rows.map(r => r.class_name));

    // Ποιος υπέβαλε τις απουσίες (για δικαίωμα ωριαίας απομάκρυνσης μετά)
    const submitterRes = await db.query(
      `SELECT DISTINCT ON (class_name) class_name, teacher_id
       FROM attendance
       WHERE date = $1 AND hour = $2
       ORDER BY class_name, id ASC`,
      [today, currentHour]
    );
    const submitterByClass = new Map(
      submitterRes.rows.map((row) => [row.class_name, row.teacher_id])
    );

    const locksRes = await db.query(
      'SELECT class_name, user_id, user_name FROM class_locks WHERE school_hour = $1',
      [currentHour]
    );
    const lockByClass = new Map(
      locksRes.rows.map((row) => [
        row.class_name,
        { userId: row.user_id, userName: row.user_name },
      ])
    );

    const result = classes.map(cls => {
      const lock = lockByClass.get(cls.name) || null;

      return {
        id: cls.id,
        name: cls.name,
        isSubmitted: submittedSet.has(cls.name),
        submittedByTeacherId: submitterByClass.get(cls.name) || null,
        isLocked: !!lock,
        lockedBy: lock ? lock.userName : null,
        lockedByUserId: lock ? lock.userId : null,
      };
    });

    res.json(result);
  } catch (err) {
    console.error("❌ Σφάλμα λήψης τμημάτων:", err.message);
    res.status(500).json({ message: err.message });
  }
});

// POST /api/school/classes (Μόνο Admin)
router.post('/classes', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { name } = req.body;
  if (!name) {
    return res.status(400).json({ message: 'Το όνομα του τμήματος είναι υποχρεωτικό.' });
  }

  try {
    const result = await db.query(
      'INSERT INTO classes (name) VALUES ($1) RETURNING *',
      [name.trim()]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(400).json({ message: 'Το τμήμα υπάρχει ήδη.' });
    }
    console.error("❌ Σφάλμα προσθήκης τμήματος:", err.message);
    res.status(500).json({ message: err.message });
  }
});

// POST /api/school/classes/delete-all (Μόνο Admin)
// Διαγράφει όλα τα τμήματα (+ μαθητές/απουσίες μέσω CASCADE) και σχετικά locks/αναθέσεις
router.post('/classes/delete-all', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({
      success: false,
      message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.',
    });
  }

  try {
    const countRes = await db.query(
      `SELECT COUNT(*)::int AS n FROM classes`
    );
    const toDelete = countRes.rows[0]?.n ?? 0;

    if (toDelete === 0) {
      return res.json({
        success: true,
        message: 'Δεν υπάρχουν τμήματα προς διαγραφή.',
        deleted: 0,
      });
    }

    await db.query('DELETE FROM teacher_class_assignments');
    await db.query('DELETE FROM class_locks');
    await db.query('DELETE FROM submitted_attendance');

    // students → ON DELETE CASCADE από classes · attendance → CASCADE από students
    const del = await db.query(
      `DELETE FROM classes RETURNING id, name`
    );

    console.log(
      `🗑️ [ADMIN] Διαγραφή όλων των τμημάτων: ${del.rowCount} (από ${req.user.username})`
    );

    res.json({
      success: true,
      message:
        `Διαγράφηκαν ${del.rowCount} τμήματα ` +
        `(μαζί με μαθητές, απουσίες και αναθέσεις τμημάτων).`,
      deleted: del.rowCount,
    });
  } catch (err) {
    console.error('❌ [DELETE ALL CLASSES]:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

// DELETE /api/school/classes/:id (Μόνο Admin)
router.delete('/classes/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { id } = req.params;
  try {
    const cls = await db.query('SELECT name FROM classes WHERE id = $1', [id]);
    const className = cls.rows[0]?.name;

    if (className) {
      await db.query(
        'DELETE FROM teacher_class_assignments WHERE class_name = $1',
        [className]
      );
      await db.query('DELETE FROM class_locks WHERE class_name = $1', [
        className,
      ]);
      await db.query(
        'DELETE FROM submitted_attendance WHERE class_name = $1',
        [className]
      );
    }

    await db.query('DELETE FROM classes WHERE id = $1', [id]);
    res.json({ success: true, message: 'Το τμήμα διαγράφηκε επιτυχώς.' });
  } catch (err) {
    console.error("❌ Σφάλμα διαγραφής τμήματος:", err.message);
    res.status(500).json({ message: err.message });
  }
});

// ==========================================
// 2. ΔΕΣΜΕΥΣΗ / ΑΠΟΔΕΣΜΕΥΣΗ ΤΜΗΜΑΤΩΝ (LOCKING) — PostgreSQL
// ==========================================

router.post('/lock-class', authenticateToken, async (req, res) => {
  const { className, currentHour } = req.body;
  const userId = req.user?.id;
  const userName =
    req.user?.username ||
    req.body.userName ||
    'Εκπαιδευτικός';

  if (!className || !currentHour) {
    return res.status(400).json({
      success: false,
      message: 'Απαιτούνται όνομα τμήματος και διδακτική ώρα.',
    });
  }

  if (!userId) {
    return res.status(401).json({
      success: false,
      message: 'Μη έγκυρος χρήστης για δέσμευση τμήματος.',
    });
  }

  try {
    await purgeStaleLocks();

    const myId = parseInt(userId, 10);
    const isAdmin = req.user?.role === 'admin';

    if (!isAdmin) {
      const allowed = await teacherCanAccessClass(req.user, className);
      if (!allowed) {
        return res.status(403).json({
          success: false,
          message:
            `Δεν έχετε ανάθεση στο τμήμα ${className}. ` +
            'Επιτρέπονται μόνο τα τμήματα που σας έχουν ανατεθεί.',
        });
      }
    }

    const existing = await db.query(
      'SELECT user_id, user_name FROM class_locks WHERE class_name = $1 AND school_hour = $2',
      [className, currentHour]
    );

    if (existing.rows.length > 0) {
      const holderId = parseInt(existing.rows[0].user_id, 10);
      // Ίδιος χρήστης: επιτρέπεται επανείσοδος (π.χ. μετά από hot restart)
      // Admin: μπορεί να αναλάβει ξένο lock
      if (holderId !== myId && !isAdmin) {
        return res.status(400).json({
          success: false,
          message: `Το τμήμα ${className} το επεξεργάζεται ο/η ${existing.rows[0].user_name}.`,
        });
      }
    }

    await db.query(
      `INSERT INTO class_locks (class_name, school_hour, user_id, user_name, locked_at)
       VALUES ($1, $2, $3, $4, NOW())
       ON CONFLICT (class_name, school_hour) DO UPDATE SET
         user_id = EXCLUDED.user_id,
         user_name = EXCLUDED.user_name,
         locked_at = NOW()`,
      [className, currentHour, userId, userName]
    );

    res.json({ success: true, message: 'Το τμήμα δεσμεύτηκε επιτυχώς.' });
  } catch (err) {
    console.error('❌ Σφάλμα δέσμευσης τμήματος:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

router.post('/unlock-class', authenticateToken, async (req, res) => {
  const { className, currentHour } = req.body;
  const userId = req.user?.id;
  const isAdmin = req.user?.role === 'admin';

  if (!className) {
    return res.status(400).json({
      success: false,
      message: 'Απαιτείται όνομα τμήματος.',
    });
  }

  try {
    if (currentHour) {
      if (isAdmin) {
        await db.query(
          'DELETE FROM class_locks WHERE class_name = $1 AND school_hour = $2',
          [className, currentHour]
        );
      } else {
        await db.query(
          'DELETE FROM class_locks WHERE class_name = $1 AND school_hour = $2 AND user_id = $3',
          [className, currentHour, userId]
        );
      }
    } else if (isAdmin) {
      await db.query('DELETE FROM class_locks WHERE class_name = $1', [className]);
    } else {
      await db.query(
        'DELETE FROM class_locks WHERE class_name = $1 AND user_id = $2',
        [className, userId]
      );
    }

    res.json({ success: true, message: 'Το τμήμα αποδεσμεύτηκε.' });
  } catch (err) {
    console.error('❌ Σφάλμα αποδέσμευσης τμήματος:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ==========================================
// 3. ΜΑΘΗΤΕΣ (STUDENTS)
// ==========================================

router.get('/students/class/:classId', authenticateToken, async (req, res) => {
  const { classId } = req.params;
  try {
    const result = await db.query(
      'SELECT * FROM students WHERE class_id = $1 ORDER BY name ASC',
      [classId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error("❌ Σφάλμα λήψης μαθητών:", err.message);
    res.status(500).json({ message: err.message });
  }
});

router.post('/students', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { name, email, classId } = req.body;

  if (!name || !classId) {
    return res.status(400).json({ message: 'Το όνομα και το τμήμα είναι υποχρεωτικά.' });
  }

  try {
    const result = await db.query(
      'INSERT INTO students (name, email, class_id) VALUES ($1, $2, $3) RETURNING *',
      [name.trim(), email ? email.trim() : '', classId]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("❌ Σφάλμα προσθήκης μαθητή:", err.message);
    res.status(500).json({ message: err.message });
  }
});

router.put('/students/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { id } = req.params;
  const { name, email } = req.body;

  if (!name) {
    return res.status(400).json({ message: 'Το ονοματεπώνυμο είναι υποχρεωτικό.' });
  }

  try {
    const result = await db.query(
      'UPDATE students SET name = $1, email = $2 WHERE id = $3 RETURNING *',
      [name.trim(), email ? email.trim() : '', id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Ο μαθητής δεν βρέθηκε.' });
    }

    res.json({ success: true, student: result.rows[0], message: 'Τα στοιχεία ενημερώθηκαν επιτυχώς!' });
  } catch (err) {
    console.error("❌ Σφάλμα ενημέρωσης μαθητή:", err.message);
    res.status(500).json({ message: err.message });
  }
});

router.delete('/students/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { id } = req.params;
  try {
    await db.query('DELETE FROM students WHERE id = $1', [id]);
    res.json({ success: true, message: 'Ο μαθητής διαγράφηκε επιτυχώς.' });
  } catch (err) {
    console.error("❌ Σφάλμα διαγραφής μαθητή:", err.message);
    res.status(500).json({ message: err.message });
  }
});

// ==========================================
// 4. ΜΑΖΙΚΗ ΕΙΣΑΓΩΓΗ ΜΑΘΗΤΩΝ ΑΠΟ EXCEL (Με Transaction)
// ==========================================
router.post('/students/import-excel', authenticateToken, upload.single('file'), async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  let client;
  try {
    const { classId } = req.body;

    if (!classId) {
      return res.status(400).json({ message: 'Δεν ορίστηκε αναγνωριστικό τμήματος (classId).' });
    }

    if (!req.file) {
      return res.status(400).json({ message: 'Δεν απεστάλη αρχείο Excel.' });
    }

    const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
    const firstSheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[firstSheetName];
    const rows = xlsx.utils.sheet_to_json(worksheet, { header: 1 });

    if (!rows || rows.length <= 1) {
      return res.status(400).json({ message: 'Το αρχείο είναι άδειο ή δεν περιέχει δεδομένα.' });
    }

    const studentsToInsert = [];
    for (let i = 1; i < rows.length; i++) {
      const row = rows[i];
      if (!row || row.length === 0) continue;

      const name = row[0] ? String(row[0]).trim() : '';
      const email = row[1] ? String(row[1]).trim() : '';

      if (name.length > 0) {
        studentsToInsert.push({ name, email, classId: parseInt(classId, 10) });
      }
    }

    if (studentsToInsert.length === 0) {
      return res.status(400).json({ message: 'Δεν βρέθηκαν έγκυροι μαθητές στο αρχείο.' });
    }

    // 🚀 Έναρξη Transaction για ασφαλή μαζική εισαγωγή
    client = await db.getClient();
    await client.query('BEGIN');

    for (const student of studentsToInsert) {
      await client.query(
        'INSERT INTO students (name, email, class_id) VALUES ($1, $2, $3)',
        [student.name, student.email, student.classId]
      );
    }

    await client.query('COMMIT');

    console.log(`✓ Εισήχθησαν επιτυχώς ${studentsToInsert.length} μαθητές στο τμήμα ID: ${classId}`);
    res.json({
      success: true,
      message: `Εισήχθησαν επιτυχώς ${studentsToInsert.length} μαθητές!`,
      count: studentsToInsert.length
    });

  } catch (err) {
    if (client) await client.query('ROLLBACK');
    console.error("❌ Σφάλμα επεξεργασίας Excel (Rolled Back):", err.message);
    res.status(500).json({ message: `Σφάλμα επεξεργασίας: ${err.message}` });
  } finally {
    if (client) client.release();
  }
});

// ==========================================
// ΑΝΑΘΕΣΕΙΣ ΤΜΗΜΑΤΩΝ ΣΕ ΕΚΠΑΙΔΕΥΤΙΚΟΥΣ
// ==========================================

// GET /api/school/teacher-assignments
router.get('/teacher-assignments', authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      `SELECT u.id AS teacher_id, u.name, u.username,
              COALESCE(
                array_agg(a.class_name ORDER BY a.class_name)
                  FILTER (WHERE a.class_name IS NOT NULL),
                '{}'
              ) AS classes
       FROM users u
       LEFT JOIN teacher_class_assignments a ON a.teacher_id = u.id
       WHERE u.role = 'teacher'
       GROUP BY u.id, u.name, u.username
       HAVING COUNT(a.id) > 0
       ORDER BY u.name ASC`
    );

    res.json({
      success: true,
      assignments: result.rows.map((row) => ({
        teacherId: row.teacher_id,
        name: row.name,
        username: row.username,
        classes: row.classes || [],
      })),
    });
  } catch (err) {
    console.error('❌ [GET TEACHER ASSIGNMENTS]:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

// DELETE /api/school/teacher-assignments
// Ήπιος καθαρισμός: ΜΟΝΟ αναθέσεις (όχι τμήματα, όχι λογαριασμοί)
router.delete('/teacher-assignments', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({
      success: false,
      message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.',
    });
  }

  try {
    const assignDel = await db.query('DELETE FROM teacher_class_assignments');

    console.log(
      `🗑️ [ADMIN] Καθαρισμός αναθέσεων: ${assignDel.rowCount} ` +
        `(από ${req.user.username})`
    );

    res.json({
      success: true,
      message:
        `Διαγράφηκαν ${assignDel.rowCount} αναθέσεις τμημάτων. ` +
        `Τμήματα και λογαριασμοί εκπαιδευτικών παρέμειναν.`,
      deleted: assignDel.rowCount,
    });
  } catch (err) {
    console.error('❌ [DELETE TEACHER ASSIGNMENTS]:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;