const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const db = require('../db');
const authenticateToken = require('../middleware/auth'); // Εισαγωγή του middleware για ασφάλεια

// 🔒 Ενιαίο JWT Secret με ασφαλές fallback
const JWT_SECRET = process.env.JWT_SECRET || 'super_secret_school_jwt_key_2026';

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

module.exports = router;