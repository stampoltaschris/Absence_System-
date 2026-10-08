const express = require('express');
const router = express.Router();
const nodemailer = require('nodemailer');
const db = require('../db');
const authenticateToken = require('../middleware/auth'); // Προσθήκη για ασφάλεια

// ==========================================
// 1. GET /api/settings/schedule
// (Προστατευμένο - Μόνο Συνδεδεμένοι)
// ==========================================
router.get('/schedule', authenticateToken, async (req, res) => {
  try {
    const result = await db.query('SELECT * FROM schedule_settings WHERE id = 1');

    if (result.rows.length === 0) {
      return res.json({}); // Επιστρέφει κενό αν δεν έχουν αποθηκευτεί ακόμα ρυθμίσεις
    }

    const data = result.rows[0];
    res.json({
      activeDays: typeof data.active_days === 'string' ? JSON.parse(data.active_days) : data.active_days,
      forceTestMode: Boolean(data.force_test_mode),
      teachingHours: typeof data.teaching_hours === 'string' ? JSON.parse(data.teaching_hours) : data.teaching_hours,
      breakDurations: typeof data.break_durations === 'string' ? JSON.parse(data.break_durations) : data.break_durations,
      calculatedBreaks: typeof data.calculated_breaks === 'string' ? JSON.parse(data.calculated_breaks) : data.calculated_breaks,
    });
  } catch (error) {
    console.error('❌ Σφάλμα κατά τη λήψη ρυθμίσεων ωραρίου:', error.message);
    res.status(500).json({ success: false, message: 'Σφάλμα διακομιστή κατά τη λήψη ωραρίου.' });
  }
});

// ==========================================
// 2. POST /api/settings/schedule
// (Προστατευμένο - Μόνο Admin)
// ==========================================
router.post('/schedule', authenticateToken, async (req, res) => {
  // 🔍 DEBUG LOGS: Έλεγχος των στοιχείων του χρήστη από το JWT Token
  console.log("----------------------------------------");
  console.log("👤 [CHECK USER] Αίτημα αποθήκευσης ωραρίου από χρήστη:");
  console.log("   - User Object:", req.user);

  if (!req.user || req.user.role !== 'admin') {
    console.log("⛔ [403 FORBIDDEN] Απορρίφθηκε: Ο χρήστης δεν έχει δικαιώματα admin!");
    console.log("----------------------------------------");
    return res.status(403).json({ message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  try {
    const { activeDays, forceTestMode, teachingHours, breakDurations, calculatedBreaks } = req.body;

    const query = `
      INSERT INTO schedule_settings (id, active_days, force_test_mode, teaching_hours, break_durations, calculated_breaks)
      VALUES (1, $1::jsonb, $2, $3::jsonb, $4::jsonb, $5::jsonb)
      ON CONFLICT (id) DO UPDATE SET
        active_days = EXCLUDED.active_days,
        force_test_mode = EXCLUDED.force_test_mode,
        teaching_hours = EXCLUDED.teaching_hours,
        break_durations = EXCLUDED.break_durations,
        calculated_breaks = EXCLUDED.calculated_breaks,
        updated_at = CURRENT_TIMESTAMP;
    `;

    await db.query(query, [
      JSON.stringify(activeDays || {}),
      Boolean(forceTestMode),
      JSON.stringify(teachingHours || []),
      JSON.stringify(breakDurations || []),
      JSON.stringify(calculatedBreaks || []),
    ]);

    console.log('✓ Οι ρυθμίσεις ωραρίου αποθηκεύτηκαν επιτυχώς στη βάση.');
    console.log("----------------------------------------");
    res.json({ success: true, message: 'Οι ρυθμίσεις αποθηκεύτηκαν επιτυχώς!' });
  } catch (error) {
    console.error('❌ Σφάλμα κατά την αποθήκευση ρυθμίσεων ωραρίου:', error.message);
    console.log("----------------------------------------");
    res.status(500).json({ success: false, message: 'Σφάλμα κατά την αποθήκευση στη βάση δεδομένων.' });
  }
});

// Κλειδιά που περιέχουν μυστικά / SMTP — μόνο admin
const SENSITIVE_SETTING_KEYS = new Set([
  'smtp_email',
  'smtp_password',
  'server_email',
  'server_password',
]);

function isSensitiveSettingKey(key) {
  if (!key) return false;
  const k = String(key).toLowerCase();
  if (SENSITIVE_SETTING_KEYS.has(k)) return true;
  return k.includes('password') || k.includes('secret') || k.includes('token');
}

function requireAdmin(req, res) {
  if (!req.user || req.user.role !== 'admin') {
    res.status(403).json({
      message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.',
    });
    return false;
  }
  return true;
}

async function readSettingValue(keys) {
  const result = await db.query(
    `SELECT key, value FROM settings WHERE key = ANY($1::text[])`,
    [keys]
  );
  const map = Object.fromEntries(result.rows.map((r) => [r.key, r.value]));
  for (const key of keys) {
    if (map[key]) return map[key];
  }
  return '';
}

async function upsertSetting(key, value) {
  await db.query(
    `INSERT INTO settings (key, value) VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [key, value !== undefined && value !== null ? value : '']
  );
}

// ==========================================
// 3. GET /api/settings/smtp  — Μόνο Admin
// ==========================================
router.get('/smtp', authenticateToken, async (req, res) => {
  if (!requireAdmin(req, res)) return;

  try {
    const smtpEmail = await readSettingValue(['smtp_email', 'server_email']);
    const smtpPassword = await readSettingValue([
      'smtp_password',
      'server_password',
    ]);
    res.json({
      smtp_email: smtpEmail,
      smtp_password: smtpPassword,
      has_password: Boolean(smtpPassword),
    });
  } catch (err) {
    console.error('❌ Σφάλμα λήψης SMTP ρυθμίσεων:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ==========================================
// 4. POST /api/settings/smtp  — Μόνο Admin
// ==========================================
router.post('/smtp', authenticateToken, async (req, res) => {
  if (!requireAdmin(req, res)) return;

  try {
    const email = (req.body.smtp_email || req.body.email || '').trim();
    const password = (req.body.smtp_password || req.body.password || '').trim();

    if (!email || !password) {
      return res.status(400).json({
        message: 'Το SMTP email και ο κωδικός εφαρμογής είναι υποχρεωτικά.',
      });
    }

    await upsertSetting('smtp_email', email);
    await upsertSetting('smtp_password', password);
    // Συμβατότητα με παλιά κλειδιά που διαβάζει το attendance
    await upsertSetting('server_email', email);
    await upsertSetting('server_password', password);

    console.log('✓ Οι ρυθμίσεις SMTP αποθηκεύτηκαν (admin only).');
    res.json({ success: true, message: 'Οι ρυθμίσεις SMTP αποθηκεύτηκαν.' });
  } catch (err) {
    console.error('❌ Σφάλμα αποθήκευσης SMTP:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ==========================================
// 5. POST /api/settings/send-test-email — Μόνο Admin
// ==========================================
router.post('/send-test-email', authenticateToken, async (req, res) => {
  if (!requireAdmin(req, res)) return;

  console.log('----------------------------------------');
  console.log('📩 Ελήφθη αίτημα για αποστολή Test Email');

  let transporter = null;
  try {
    const recipient = req.body.recipient || req.body.recipientEmail;
    console.log('-> Παραλήπτης:', recipient);

    if (!recipient) {
      return res.status(400).json({ error: 'Δεν ορίστηκε διεύθυνση παραλήπτη.' });
    }

    const userEmail = await readSettingValue(['smtp_email', 'server_email']);
    const userPass = await readSettingValue([
      'smtp_password',
      'server_password',
    ]);

    console.log('-> Email Αποστολέα:', userEmail);
    console.log('-> App Password υπάρχει;', userPass ? 'ΝΑΙ' : 'ΟΧΙ (ΚΕΝΟ!)');

    if (!userEmail || !userPass) {
      console.error('❌ Λείπουν τα διαπιστευτήρια SMTP από τη βάση!');
      return res
        .status(400)
        .json({ error: 'Δεν έχουν οριστεί διαπιστευτήρια email.' });
    }

    transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: { user: userEmail, pass: userPass },
    });

    const info = await transporter.sendMail({
      from: `"Σύστημα Απουσιών" <${userEmail}>`,
      to: recipient,
      subject: 'Δοκιμαστικό Email - Σύστημα Απουσιών',
      text: 'Το παρόν είναι ένα δοκιμαστικό email. Οι ρυθμίσεις του Email Server λειτουργούν επιτυχώς!',
    });

    console.log('✓ ΤΟ EMAIL ΣΤΑΛΘΗΚΕ ΕΠΙΤΥΧΩΣ! Message ID:', info.messageId);
    console.log('----------------------------------------');

    transporter.close();
    res.json({ message: 'Το δοκιμαστικό email στάλθηκε με επιτυχία!' });
  } catch (err) {
    if (transporter) transporter.close();
    console.error('❌ ΑΝΑΛΥΤΙΚΟ ΣΦΑΛΜΑ NODEMAILER:', err);
    console.log('----------------------------------------');
    res.status(500).json({ error: 'Αποτυχία αποστολής: ' + err.message });
  }
});

// ==========================================
// 6. GET /api/settings/:key
// Ευαίσθητα κλειδιά → μόνο Admin. Άλλα → οποιοσδήποτε συνδεδεμένος.
// ==========================================
router.get('/:key', authenticateToken, async (req, res) => {
  const key = req.params.key;

  if (isSensitiveSettingKey(key) && !requireAdmin(req, res)) {
    return;
  }

  try {
    const result = await db.query('SELECT value FROM settings WHERE key = $1', [
      key,
    ]);
    if (result.rows.length > 0) {
      res.json({ value: result.rows[0].value });
    } else {
      res.json({ value: '' });
    }
  } catch (err) {
    console.error('❌ Σφάλμα κατά την ανάκτηση ρύθμισης:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ==========================================
// 7. POST /api/settings — Μόνο Admin
// ==========================================
router.post('/', authenticateToken, async (req, res) => {
  if (!requireAdmin(req, res)) return;

  const { key, value } = req.body;
  if (!key) {
    return res
      .status(400)
      .json({ message: 'Το κλειδί της ρύθμισης είναι υποχρεωτικό.' });
  }

  try {
    await upsertSetting(key, value);
    console.log(`✓ Η ρύθμιση [${key}] αποθηκεύτηκε επιτυχώς.`);
    res.json({ message: 'Η ρύθμιση αποθηκεύτηκε.' });
  } catch (err) {
    console.error(
      `❌ Σφάλμα κατά την αποθήκευση της ρύθμισης [${key}]:`,
      err.message
    );
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;