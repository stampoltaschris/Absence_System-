const authenticateToken = require('./middleware/auth');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcrypt'); // 1. Διορθώθηκε: Χρήση του native bcrypt
const jwt = require('jsonwebtoken'); // Προσθήκη για την έκδοση νέου token μετά το reset
require('dotenv').config();
const db = require('./db');

const app = express();
const PORT = process.env.PORT || 5000;

// 🔒 Ενιαίο JWT Secret Key
const JWT_SECRET = process.env.JWT_SECRET || 'fallback_school_attendance_jwt_secret_key_2026';

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' })); // 2. Διορθώθηκε: Αύξηση ορίου για μεγάλα payloads (π.χ. Excel)

// --- SANITIZED LOGGER MIDDLEWARE (Ασφαλής καταγραφή χωρίς κωδικούς) ---
app.use((req, res, next) => {
  const timestamp = new Date().toLocaleTimeString();
  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  console.log(`\n==================================================`);
  console.log(`📱 [${timestamp}] Νέα κλήση από: ${clientIp}`);
  console.log(`➡️  Method & Path: ${req.method} ${req.originalUrl}`);

  if (req.body && Object.keys(req.body).length > 0) {
    // Δημιουργία αντιγράφου και απόκρυψη ευαίσθητων πεδίων
    const sanitizedBody = { ...req.body };
    if (sanitizedBody.password) sanitizedBody.password = '***HIDDEN***';
    if (sanitizedBody.oldPassword) sanitizedBody.oldPassword = '***HIDDEN***';
    if (sanitizedBody.newPassword) sanitizedBody.newPassword = '***HIDDEN***';
    if (sanitizedBody.token) sanitizedBody.token = '***HIDDEN***';

    console.log(`📦 Body Data:`, JSON.stringify(sanitizedBody, null, 2));
  } else {
    console.log(`📦 Body Data: (Άδειο)`);
  }

  // Παρακολούθηση της απάντησης του Server
  res.on('finish', () => {
    const statusIcon = res.statusCode >= 200 && res.statusCode < 300 ? '✅' : '❌';
    console.log(`${statusIcon} Απάντηση Server: Status Code ${res.statusCode}`);
    console.log(`==================================================\n`);
  });

  next();
});

// --------------------------------------------------
// 1. ΔΗΜΟΣΙΑ ROUTES (Χωρίς JWT - Προσβάσιμα για Login)
// --------------------------------------------------
app.use('/api/auth', require('./routes/auth'));

// Health Check Endpoint (Ελεύθερο)
app.get('/api/health', async (req, res) => {
  try {
    const result = await db.query('SELECT NOW()');
    res.json({
      status: 'OK',
      message: 'Ο Server και η PostgreSQL λειτουργούν κανονικά!',
      time: result.rows[0].now,
    });
  } catch (err) {
    res.status(500).json({ status: 'ERROR', error: err.message });
  }
});

// --------------------------------------------------
// 2. ΠΡΟΣΤΑΤΕΥΜΕΝΑ ROUTES (Απαιτούν έγκυρο JWT Token)
// --------------------------------------------------
app.use('/api/reports', authenticateToken, require('./routes/reports'));
app.use('/api/school', authenticateToken, require('./routes/school'));
app.use('/api/attendance', authenticateToken, require('./routes/attendance'));
app.use('/api/settings', authenticateToken, require('./routes/settings'));

// Endpoint για τον Καθαρισμό (Reset) της Βάσης Δεδομένων (Προστατευμένο & Ασφαλές)
app.post('/api/admin/reset-database', authenticateToken, async (req, res) => {
  // 3. 🛡️ ΑΣΦΑΛΕΙΑ: Απόρριψη αν το JWT token δεν ανήκει σε Admin
  if (!req.user || req.user.role !== 'admin') {
    console.log(`⛔ [SECURITY] Αποτράπηκε προσπάθεια reset βάσης από μη-διαχειριστή`);
    return res.status(403).json({ success: false, message: 'Απαγορεύεται η πρόσβαση. Απαιτούνται δικαιώματα διαχειριστή.' });
  }

  const { adminId, password } = req.body;

  try {
    console.log(`🔍 [RESET DB] Αίτημα καθαρισμού βάσης από Admin ID: ${adminId}`);

    // 1. Επιβεβαίωση ύπαρξης διαχειριστή
    const userRes = await db.query('SELECT password FROM users WHERE id = $1 AND role = $2', [adminId, 'admin']);
    
    if (userRes.rows.length === 0) {
      console.log(`❌ [RESET DB] Δεν βρέθηκε admin με id = ${adminId}`);
      return res.status(401).json({ success: false, message: 'Λανθασμένος κωδικός πρόσβασης.' });
    }

    const dbPassword = userRes.rows[0].password;

    // Έλεγχος αν ο κωδικός στη βάση είναι bcrypt hash ή plain text
    const isHashed = dbPassword.startsWith('$2a$') || dbPassword.startsWith('$2b$');
    const isPasswordValid = isHashed 
      ? await bcrypt.compare(password, dbPassword)
      : (dbPassword === password);

    if (!isPasswordValid) {
      console.log(`❌ [RESET DB] Αποτυχία επιβεβαίωσης κωδικού για τον Admin ID: ${adminId}`);
      return res.status(401).json({ success: false, message: 'Λανθασμένος κωδικός πρόσβασης.' });
    }

    // 2. Διαγραφή όλων των δεδομένων και μηδενισμός των IDs (CASCADE)
    await db.query(
      'TRUNCATE TABLE attendance, students, classes, users, submitted_attendance, class_locks RESTART IDENTITY CASCADE'
    );

    // 3. Δημιουργία αρχικού λογαριασμού Admin με bcrypt hashed κωδικό 'admin' (ID = 1)
    const hashedInitialPassword = await bcrypt.hash('admin', 10);
    const newAdminRes = await db.query(
      "INSERT INTO users (name, username, password, role, is_first_login) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, username, role",
      ['Διαχειριστής Συστήματος', 'admin', hashedInitialPassword, 'admin', true]
    );

    const newAdmin = newAdminRes.rows[0];

    // 4. Έκδοση ΝΕΟΥ JWT Token για το νέο ID του Admin
    const newToken = jwt.sign(
      { id: newAdmin.id, username: newAdmin.username, role: newAdmin.role },
      JWT_SECRET,
      { expiresIn: '12h' }
    );

    console.log("⚠️ Η βάση δεδομένων μηδενίστηκε. Δημιουργήθηκε αρχικός admin (ID: 1) και εκδόθηκε νέο Token.");
    
    res.json({ 
      success: true, 
      message: 'Η βάση δεδομένων καθαρίστηκε επιτυχώς.',
      newToken: newToken,
      user: newAdmin
    });

  } catch (err) {
    console.error("❌ Σφάλμα κατά τον καθαρισμό της βάσης:", err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

async function startServer() {
  try {
    await db.ensureSchema();
  } catch (err) {
    console.error('❌ Αποτυχία προετοιμασίας σχήματος βάσης:', err.message);
    process.exit(1);
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Ο Server τρέχει στη θύρα ${PORT}`);
    console.log(`👉 Τοπικά (Localhost): http://localhost:${PORT}`);
    console.log(`👉 Δίκτυο Wi-Fi (IP): http://0.0.0.0:${PORT}`);
  });
}

startServer();