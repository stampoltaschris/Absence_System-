const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const multer = require('multer');
const xlsx = require('xlsx');
const db = require('../db');
const authenticateToken = require('../middleware/auth'); // Εισαγωγή του middleware για ασφάλεια

// 🔒 Ενιαίο JWT Secret με ασφαλές fallback
const JWT_SECRET = process.env.JWT_SECRET || 'super_secret_school_jwt_key_2026';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

/** Μετατροπή ελληνικών (και digraphs) σε λατινικούς χαρακτήρες για username. */
function transliterateGreek(input) {
  if (!input) return '';
  let s = String(input).normalize('NFC').trim().toLowerCase();

  const digraphs = [
    ['αι', 'ai'], ['ει', 'ei'], ['οι', 'oi'], ['ου', 'ou'],
    ['αυ', 'av'], ['ευ', 'ev'], ['ηυ', 'iv'],
    ['μπ', 'b'], ['ντ', 'd'], ['γκ', 'g'], ['γγ', 'ng'],
    ['τσ', 'ts'], ['τζ', 'tz'], ['θ', 'th'], ['χ', 'ch'], ['ψ', 'ps'],
  ];
  for (const [gr, lat] of digraphs) {
    s = s.split(gr).join(lat);
  }

  const map = {
    α: 'a', ά: 'a', β: 'v', γ: 'g', δ: 'd', ε: 'e', έ: 'e', ζ: 'z',
    η: 'i', ή: 'i', ι: 'i', ί: 'i', ϊ: 'i', ΐ: 'i', κ: 'k', λ: 'l',
    μ: 'm', ν: 'n', ξ: 'x', ο: 'o', ό: 'o', π: 'p', ρ: 'r', σ: 's',
    ς: 's', τ: 't', υ: 'y', ύ: 'y', ϋ: 'y', ΰ: 'y', φ: 'f', ω: 'o', ώ: 'o',
  };

  let out = '';
  for (const ch of s) {
    if (map[ch]) out += map[ch];
    else if (/[a-z0-9]/.test(ch)) out += ch;
    else if (ch === ' ' || ch === '-' || ch === '_') out += '';
    // αγνοούμε λοιπά σύμβολα
  }
  return out;
}

function buildBaseUsername(firstName, lastName) {
  const last = transliterateGreek(lastName);
  const first = transliterateGreek(firstName);
  const initial = first.charAt(0) || '';
  let base = `${initial}${last}`.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (!base) base = `teacher${Date.now().toString().slice(-4)}`;
  if (base.length > 24) base = base.slice(0, 24);
  return base;
}

function generatePassword(username) {
  const n = Math.floor(100 + Math.random() * 900); // 100-999
  return `${username}${n}`;
}

function looksLikeHeader(surname, firstname) {
  const a = String(surname || '').toLowerCase();
  const b = String(firstname || '').toLowerCase();
  const headerWords = ['επώνυμο', 'επιθετο', 'επίθετο', 'surname', 'lastname', 'όνομα', 'ονομα', 'firstname', 'name'];
  return headerWords.some((w) => a.includes(w) || b.includes(w));
}

// ==========================================
// POST /api/auth/login
// ==========================================
router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  
  if (!username || !password) {
    return res.status(400).json({ message: 'Συμπληρώστε username και password.' });
  }

  try {
    const result = await db.query(
      'SELECT * FROM users WHERE username = $1',
      [username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ message: 'Λανθασμένο username ή password.' });
    }

    const user = result.rows[0];
    let isPasswordValid = false;

    const isHashed = user.password.startsWith('$2a$') || user.password.startsWith('$2b$');

    if (isHashed) {
      isPasswordValid = await bcrypt.compare(password, user.password);
    } else {
      isPasswordValid = (user.password === password);

      if (isPasswordValid) {
        const hashedPassword = await bcrypt.hash(password, 10);
        await db.query('UPDATE users SET password = $1 WHERE id = $2', [hashedPassword, user.id]);
        console.log(`🔒 [SECURITY] Ο κωδικός του χρήστη ${username} αναβαθμίστηκε αυτόματα σε bcrypt hash.`);
      }
    }

    if (!isPasswordValid) {
      return res.status(401).json({ message: 'Λανθασμένο username ή password.' });
    }

    const token = jwt.sign(
      { id: user.id, username: user.username, role: user.role },
      JWT_SECRET,
      { expiresIn: '12h' }
    );

    res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        username: user.username,
        role: user.role,
        is_first_login: user.is_first_login ?? false,
      },
    });
  } catch (err) {
    console.error("❌ [LOGIN ERROR]:", err.message);
    res.status(500).json({ message: 'Σφάλμα διακομιστή κατά τη σύνδεση.' });
  }
});

// ==========================================
// POST /api/auth/change-password
// (Προστατευμένο με JWT - Απαιτείται έγκυρο Token)
// ==========================================
router.post('/change-password', authenticateToken, async (req, res) => {
  const { oldPassword, newPassword } = req.body;
  
  // 🛡️ ΑΣΦΑΛΕΙΑ: Παίρνουμε το userId αποκλειστικά από το Token του authenticated χρήστη
  const userId = req.user?.id;

  try {
    if (!oldPassword || !newPassword) {
      return res.status(400).json({ 
        message: 'Απαιτούνται τόσο ο τρέχων όσο και ο νέος κωδικός πρόσβασης.' 
      });
    }

    if (!userId) {
      return res.status(401).json({ message: 'Μη εξουσιοδοτημένη πρόσβαση.' });
    }

    const userRes = await db.query('SELECT password FROM users WHERE id = $1', [userId]);

    if (userRes.rows.length === 0) {
      return res.status(404).json({ message: 'Ο χρήστης δεν βρέθηκε.' });
    }

    const currentDbPassword = userRes.rows[0].password;

    const isHashed = currentDbPassword.startsWith('$2a$') || currentDbPassword.startsWith('$2b$');
    const isMatch = isHashed 
      ? await bcrypt.compare(oldPassword, currentDbPassword)
      : (currentDbPassword === oldPassword);

    if (!isMatch) {
      return res.status(400).json({ message: 'Ο τρέχων κωδικός είναι λανθασμένος.' });
    }

    const hashedNewPassword = await bcrypt.hash(newPassword, 10);

    await db.query(
      'UPDATE users SET password = $1, is_first_login = false WHERE id = $2',
      [hashedNewPassword, userId]
    );

    console.log(`✅ [CHANGE PASSWORD] Ο κωδικός ενημερώθηκε επιτυχώς για το userId: ${userId}`);
    res.json({ message: 'Ο κωδικός άλλαξε επιτυχώς!' });

  } catch (err) {
    console.error("❌ [CHANGE PASSWORD ERROR]:", err.message);
    res.status(500).json({ message: err.message });
  }
});

// ==========================================
// GET /api/auth/users
// (Προστατευμένο - Μόνο Admin)
// Query: ?role=teacher (προαιρετικό φίλτρο)
// ==========================================
router.get('/users', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  try {
    const roleFilter = (req.query.role || '').toString().trim().toLowerCase();
    let result;
    if (roleFilter === 'teacher' || roleFilter === 'admin') {
      result = await db.query(
        'SELECT id, name, username, role, is_first_login FROM users WHERE role = $1 ORDER BY name ASC',
        [roleFilter]
      );
    } else {
      result = await db.query(
        'SELECT id, name, username, role, is_first_login FROM users ORDER BY name ASC'
      );
    }
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ==========================================
// POST /api/auth/users
// (Προστατευμένο - Μόνο Admin)
// ==========================================
router.post('/users', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { name, username, password, role } = req.body;

  if (!name || !username || !password || !role) {
    return res.status(400).json({ message: 'Συμπληρώστε όλα τα απαραίτητα πεδία για τον χρήστη.' });
  }

  const normalizedRole = String(role).toLowerCase();
  if (normalizedRole !== 'teacher' && normalizedRole !== 'admin') {
    return res.status(400).json({ message: 'Μη έγκυρος ρόλος χρήστη.' });
  }

  try {
    const hashedPassword = await bcrypt.hash(password, 10);

    const result = await db.query(
      'INSERT INTO users (name, username, password, role, is_first_login) VALUES ($1, $2, $3, $4, TRUE) RETURNING id, name, username, role, is_first_login',
      [name.trim(), username.trim().toLowerCase(), hashedPassword, normalizedRole]
    );
    
    console.log(`👤 [ADMIN] Δημιουργήθηκε νέος χρήστης: ${username} (${normalizedRole})`);
    res.json({ success: true, user: result.rows[0], message: 'Ο λογαριασμός δημιουργήθηκε.' });
  } catch (err) {
    if (err.code === '23505') { // PostgreSQL unique violation error code
      return res.status(400).json({ success: false, message: 'Το username χρησιμοποιείται ήδη.' });
    }
    res.status(500).json({ success: false, message: err.message });
  }
});

// ==========================================
// POST /api/auth/users/import-excel
// Excel: στήλη A = Επώνυμο, στήλη B = Όνομα
// Δημιουργεί teachers με username (ελληνικά→λατινικά) και προσωρινό password
// ==========================================
router.post(
  '/users/import-excel',
  authenticateToken,
  upload.single('file'),
  async (req, res) => {
    if (req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.',
      });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Δεν απεστάλη αρχείο Excel.' });
    }

    let client;
    try {
      const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
      const sheetName = workbook.SheetNames[0];
      const worksheet = workbook.Sheets[sheetName];
      const rows = xlsx.utils.sheet_to_json(worksheet, { header: 1, defval: '' });

      if (!rows || rows.length === 0) {
        return res.status(400).json({ success: false, message: 'Το αρχείο είναι άδειο.' });
      }

      const existingRes = await db.query('SELECT username FROM users');
      const usedUsernames = new Set(
        existingRes.rows.map((r) => String(r.username).toLowerCase())
      );

      const created = [];
      const skipped = [];

      client = await db.getClient();
      await client.query('BEGIN');

      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row || row.length === 0) continue;

        const surname = row[0] != null ? String(row[0]).trim() : '';
        const firstname = row[1] != null ? String(row[1]).trim() : '';
        if (!surname && !firstname) continue;
        if (i === 0 && looksLikeHeader(surname, firstname)) continue;
        if (!surname || !firstname) {
          skipped.push({
            row: i + 1,
            reason: 'Λείπει επώνυμο ή όνομα',
            surname,
            firstname,
          });
          continue;
        }

        const fullName = `${surname} ${firstname}`.replace(/\s+/g, ' ').trim();
        let base = buildBaseUsername(firstname, surname);
        let username = base;
        let suffix = 2;
        while (usedUsernames.has(username)) {
          username = `${base}${suffix}`;
          suffix += 1;
          if (suffix > 99) {
            username = `${base}${Date.now().toString().slice(-3)}`;
            break;
          }
        }

        const plainPassword = generatePassword(username);
        const hashedPassword = await bcrypt.hash(plainPassword, 10);

        const result = await client.query(
          `INSERT INTO users (name, username, password, role, is_first_login)
           VALUES ($1, $2, $3, 'teacher', TRUE)
           RETURNING id, name, username, role`,
          [fullName, username, hashedPassword]
        );

        usedUsernames.add(username);
        created.push({
          id: result.rows[0].id,
          name: fullName,
          username,
          password: plainPassword,
        });
      }

      if (created.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message: 'Δεν δημιουργήθηκαν λογαριασμοί. Ελέγξτε ότι το Excel έχει Επώνυμο | Όνομα.',
          skipped,
        });
      }

      await client.query('COMMIT');
      console.log(`👤 [ADMIN] Excel import: ${created.length} εκπαιδευτικοί`);

      res.json({
        success: true,
        message: `Δημιουργήθηκαν ${created.length} λογαριασμοί εκπαιδευτικών.`,
        count: created.length,
        credentials: created,
        skipped,
      });
    } catch (err) {
      if (client) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {
          /* ignore */
        }
      }
      console.error('❌ [TEACHERS EXCEL IMPORT]:', err.message);
      res.status(500).json({ success: false, message: `Σφάλμα επεξεργασίας: ${err.message}` });
    } finally {
      if (client) client.release();
    }
  }
);

// ==========================================
// PUT /api/auth/users/:id
// Ενημέρωση εκπαιδευτικού (όνομα / username / προαιρετικά κωδικός)
// ==========================================
router.put('/users/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ success: false, message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const userId = parseInt(req.params.id, 10);
  const { name, username, password } = req.body;

  if (isNaN(userId)) {
    return res.status(400).json({ success: false, message: 'Μη έγκυρο ID χρήστη.' });
  }
  if (!name || !username) {
    return res.status(400).json({ success: false, message: 'Απαιτούνται ονοματεπώνυμο και username.' });
  }

  try {
    const existing = await db.query('SELECT id, role FROM users WHERE id = $1', [userId]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Ο χρήστης δεν βρέθηκε.' });
    }

    // Από αυτό το CRUD επιτρέπουμε επεξεργασία μόνο εκπαιδευτικών
    if (existing.rows[0].role !== 'teacher') {
      return res.status(403).json({
        success: false,
        message: 'Από εδώ επεξεργάζονται μόνο λογαριασμοί εκπαιδευτικών.',
      });
    }

    const cleanName = String(name).trim();
    const cleanUsername = String(username).trim().toLowerCase();
    const newPassword = password != null ? String(password).trim() : '';

    let result;
    if (newPassword.length > 0) {
      const hashedPassword = await bcrypt.hash(newPassword, 10);
      result = await db.query(
        `UPDATE users
         SET name = $1, username = $2, password = $3, is_first_login = TRUE
         WHERE id = $4 AND role = 'teacher'
         RETURNING id, name, username, role, is_first_login`,
        [cleanName, cleanUsername, hashedPassword, userId]
      );
    } else {
      result = await db.query(
        `UPDATE users
         SET name = $1, username = $2
         WHERE id = $3 AND role = 'teacher'
         RETURNING id, name, username, role, is_first_login`,
        [cleanName, cleanUsername, userId]
      );
    }

    console.log(`✏️ [ADMIN] Ενημερώθηκε εκπαιδευτικός id=${userId} (${cleanUsername})`);
    res.json({ success: true, user: result.rows[0], message: 'Ο εκπαιδευτικός ενημερώθηκε.' });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(400).json({ success: false, message: 'Το username χρησιμοποιείται ήδη.' });
    }
    res.status(500).json({ success: false, message: err.message });
  }
});

// ==========================================
// POST /api/auth/users/delete-all-teachers
// Διαγραφή ΟΛΩΝ των εκπαιδευτικών — διατηρούνται οι admin
// ==========================================
router.post('/users/delete-all-teachers', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({
      success: false,
      message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.',
    });
  }

  try {
    const countRes = await db.query(
      `SELECT COUNT(*)::int AS n FROM users WHERE role = 'teacher'`
    );
    const toDelete = countRes.rows[0]?.n ?? 0;

    if (toDelete === 0) {
      return res.json({
        success: true,
        message: 'Δεν υπάρχουν λογαριασμοί εκπαιδευτικών προς διαγραφή.',
        deleted: 0,
      });
    }

    // Αναθέσεις τμημάτων (ρητά, πριν τη διαγραφή χρηστών)
    const assignDel = await db.query(
      `DELETE FROM teacher_class_assignments
       WHERE teacher_id IN (SELECT id FROM users WHERE role = 'teacher')`
    );

    // Locks εκπαιδευτικών
    await db.query(
      `DELETE FROM class_locks
       WHERE user_id IN (SELECT id FROM users WHERE role = 'teacher')`
    );

    // attendance.teacher_id → ON DELETE CASCADE
    const del = await db.query(
      `DELETE FROM users WHERE role = 'teacher' RETURNING id, username`
    );

    console.log(
      `🗑️ [ADMIN] Μαζική διαγραφή εκπαιδευτικών: ${del.rowCount}, ` +
        `αναθέσεις: ${assignDel.rowCount} (από ${req.user.username})`
    );

    res.json({
      success: true,
      message:
        `Διαγράφηκαν ${del.rowCount} λογαριασμοί εκπαιδευτικών ` +
        `και ${assignDel.rowCount} αναθέσεις τμημάτων. Ο διαχειριστής παρέμεινε.`,
      deleted: del.rowCount,
      assignmentsDeleted: assignDel.rowCount,
    });
  } catch (err) {
    console.error('❌ [DELETE ALL TEACHERS]:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ==========================================
// DELETE /api/auth/users/:id
// Διαγραφή εκπαιδευτικού (όχι admin / όχι τον εαυτό σου)
// ==========================================
router.delete('/users/:id', authenticateToken, async (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ success: false, message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const userId = parseInt(req.params.id, 10);
  if (isNaN(userId)) {
    return res.status(400).json({ success: false, message: 'Μη έγκυρο ID χρήστη.' });
  }

  if (req.user.id === userId) {
    return res.status(400).json({ success: false, message: 'Δεν μπορείτε να διαγράψετε τον δικό σας λογαριασμό.' });
  }

  try {
    const existing = await db.query(
      'SELECT id, name, username, role FROM users WHERE id = $1',
      [userId]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Ο χρήστης δεν βρέθηκε.' });
    }

    const target = existing.rows[0];
    if (target.role !== 'teacher') {
      return res.status(403).json({
        success: false,
        message: 'Δεν επιτρέπεται η διαγραφή λογαριασμού διαχειριστή από εδώ.',
      });
    }

    // Καθαρισμός τυχόν ενεργών locks του εκπαιδευτικού
    await db.query('DELETE FROM class_locks WHERE user_id = $1', [userId]);

    // attendance.teacher_id έχει ON DELETE CASCADE
    await db.query(`DELETE FROM users WHERE id = $1 AND role = 'teacher'`, [userId]);

    console.log(`🗑️ [ADMIN] Διαγράφηκε εκπαιδευτικός: ${target.username} (id=${userId})`);
    res.json({
      success: true,
      message: `Ο εκπαιδευτικός "${target.name}" διαγράφηκε.`,
    });
  } catch (err) {
    console.error('❌ [DELETE USER ERROR]:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

function looksLikeAssignmentsHeader(colA, colB) {
  const a = String(colA || '').toLowerCase();
  const b = String(colB || '').toLowerCase();
  const words = [
    'ονοματεπωνυμο',
    'ονοματεπώνυμο',
    'ονομα',
    'όνομα',
    'name',
    'τμημα',
    'τμήμα',
    'τμηματα',
    'τμήματα',
    'class',
    'classes',
  ];
  return words.some((w) => a.includes(w) || b.includes(w));
}

function splitFullName(fullName) {
  const parts = String(fullName || '')
    .trim()
    .replace(/\s+/g, ' ')
    .split(' ')
    .filter(Boolean);
  if (parts.length === 0) return { surname: '', firstname: '' };
  if (parts.length === 1) return { surname: parts[0], firstname: parts[0] };
  return {
    surname: parts.slice(0, -1).join(' '),
    firstname: parts[parts.length - 1],
  };
}

function parseClassList(raw) {
  return String(raw || '')
    .split(/[,;|/\n·•]+/)
    .map((s) => s.trim().replace(/\s+/g, ''))
    .filter(Boolean)
    .map((s) => s.toLocaleUpperCase('el-GR'));
}

// ==========================================
// POST /api/auth/users/import-assignments-excel
// Excel: στήλη A = Ονοματεπώνυμο, στήλη B = Τμήματα (π.χ. Α1, Α3, ΒΘΣ1)
// Δημιουργεί λογαριασμούς (ίδια λογική username/password) + αποθηκεύει αναθέσεις
// ==========================================
router.post(
  '/users/import-assignments-excel',
  authenticateToken,
  upload.single('file'),
  async (req, res) => {
    if (req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.',
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'Δεν απεστάλη αρχείο Excel.',
      });
    }

    let client;
    try {
      const workbook = xlsx.read(req.file.buffer, { type: 'buffer' });
      const sheetName = workbook.SheetNames[0];
      const worksheet = workbook.Sheets[sheetName];
      const rows = xlsx.utils.sheet_to_json(worksheet, {
        header: 1,
        defval: '',
      });

      if (!rows || rows.length === 0) {
        return res.status(400).json({
          success: false,
          message: 'Το αρχείο είναι άδειο.',
        });
      }

      const existingRes = await db.query(
        `SELECT id, name, username FROM users WHERE role = 'teacher'`
      );
      const teachersByName = new Map(
        existingRes.rows.map((r) => [
          String(r.name).trim().toLocaleLowerCase('el-GR'),
          r,
        ])
      );

      const allUsersRes = await db.query('SELECT username FROM users');
      const usedUsernames = new Set(
        allUsersRes.rows.map((r) => String(r.username).toLowerCase())
      );

      const createdCredentials = [];
      const reused = [];
      const assignments = [];
      const skipped = [];
      const classesEnsured = new Set();

      client = await db.getClient();
      await client.query('BEGIN');

      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        if (!row || row.length === 0) continue;

        const fullNameRaw = row[0] != null ? String(row[0]).trim() : '';
        const classesRaw = row[1] != null ? String(row[1]).trim() : '';

        if (!fullNameRaw && !classesRaw) continue;
        if (i === 0 && looksLikeAssignmentsHeader(fullNameRaw, classesRaw)) {
          continue;
        }

        if (!fullNameRaw) {
          skipped.push({ row: i + 1, reason: 'Λείπει ονοματεπώνυμο' });
          continue;
        }

        const classNames = parseClassList(classesRaw);
        if (classNames.length === 0) {
          skipped.push({
            row: i + 1,
            reason: 'Λείπουν τμήματα',
            name: fullNameRaw,
          });
          continue;
        }

        const fullName = fullNameRaw.replace(/\s+/g, ' ').trim();
        const nameKey = fullName.toLocaleLowerCase('el-GR');
        let teacher = teachersByName.get(nameKey);
        let isNew = false;

        if (!teacher) {
          const { surname, firstname } = splitFullName(fullName);
          let base = buildBaseUsername(firstname, surname);
          let username = base;
          let suffix = 2;
          while (usedUsernames.has(username)) {
            username = `${base}${suffix}`;
            suffix += 1;
            if (suffix > 99) {
              username = `${base}${Date.now().toString().slice(-3)}`;
              break;
            }
          }

          const plainPassword = generatePassword(username);
          const hashedPassword = await bcrypt.hash(plainPassword, 10);

          const result = await client.query(
            `INSERT INTO users (name, username, password, role, is_first_login)
             VALUES ($1, $2, $3, 'teacher', TRUE)
             RETURNING id, name, username, role`,
            [fullName, username, hashedPassword]
          );

          teacher = result.rows[0];
          usedUsernames.add(username);
          teachersByName.set(nameKey, teacher);
          isNew = true;
          createdCredentials.push({
            id: teacher.id,
            name: fullName,
            username,
            password: plainPassword,
          });
        } else {
          reused.push({
            id: teacher.id,
            name: teacher.name,
            username: teacher.username,
          });
        }

        // Αντικατάσταση αναθέσεων για αυτόν τον εκπαιδευτικό
        await client.query(
          `DELETE FROM teacher_class_assignments WHERE teacher_id = $1`,
          [teacher.id]
        );

        const teacherClasses = [];
        for (const className of classNames) {
          if (!classesEnsured.has(className)) {
            await client.query(
              `INSERT INTO classes (name) VALUES ($1)
               ON CONFLICT (name) DO NOTHING`,
              [className]
            );
            classesEnsured.add(className);
          }

          await client.query(
            `INSERT INTO teacher_class_assignments (teacher_id, class_name)
             VALUES ($1, $2)
             ON CONFLICT (teacher_id, class_name) DO NOTHING`,
            [teacher.id, className]
          );
          teacherClasses.push(className);
        }

        assignments.push({
          teacherId: teacher.id,
          name: fullName,
          username: teacher.username,
          classes: teacherClasses,
          createdAccount: isNew,
        });
      }

      if (assignments.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({
          success: false,
          message:
            'Δεν δημιουργήθηκαν αναθέσεις. Ελέγξτε ότι το Excel έχει Ονοματεπώνυμο | Τμήματα.',
          skipped,
        });
      }

      await client.query('COMMIT');

      console.log(
        `👤 [ADMIN] Assignments import: ${assignments.length} εκπαιδευτικοί, ` +
          `${createdCredentials.length} νέοι λογαριασμοί, ` +
          `${classesEnsured.size} τμήματα`
      );

      res.json({
        success: true,
        message:
          `Ανατέθηκαν τμήματα σε ${assignments.length} εκπαιδευτικούς. ` +
          `Νέοι λογαριασμοί: ${createdCredentials.length}. ` +
          `Υπάρχοντες: ${reused.length}.`,
        count: assignments.length,
        createdCount: createdCredentials.length,
        reusedCount: reused.length,
        credentials: createdCredentials,
        assignments,
        skipped,
      });
    } catch (err) {
      if (client) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {
          /* ignore */
        }
      }
      console.error('❌ [IMPORT ASSIGNMENTS]:', err.message);
      res.status(500).json({ success: false, message: err.message });
    } finally {
      if (client) client.release();
    }
  }
);

module.exports = router;