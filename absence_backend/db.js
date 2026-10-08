const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: process.env.DB_PORT,
  max: 30, // Υποστήριξη έως και 30 ταυτόχρονων συνδέσεων
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000, // 1. ΔΙΟΡΘΩΣΗ: Αύξηση σε 5 δευτερόλεπτα για πιο ασταθή σχολικά Wi-Fi
});

// Ενεργοποιείται μόνο στο πρώτο connection του Pool
pool.on('connect', () => {
  // Χρησιμοποιούμε console.debug ή απλό log
  console.log('✅ Επιτυχής σύνδεση με την PostgreSQL Database');
});

// Προστασία από απρόσμενα σφάλματα (π.χ. αν κλείσει ξαφνικά η βάση)
pool.on('error', (err) => {
  console.error('❌ Απροσδόκητο σφάλμα στο PostgreSQL Pool:', err);
  // Δεν κάνουμε process.exit() για να μην ρίξουμε όλο τον server, το Pool θα προσπαθήσει ξανά.
});

// 2. ΔΙΟΡΘΩΣΗ: Graceful Shutdown
// Ακούμε το κλείσιμο του Node.js (π.χ. CTRL+C) και κλείνουμε το Pool σωστά
process.on('SIGINT', async () => {
  console.log('⚠️ Κλείσιμο του Node Server. Τερματισμός συνδέσεων βάσης...');
  await pool.end();
  process.exit(0);
});

/** Δημιουργία πίνακα δεσμεύσεων τμημάτων (αν δεν υπάρχει). */
async function ensureClassLocksTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS class_locks (
      class_name TEXT NOT NULL,
      school_hour TEXT NOT NULL,
      user_id INTEGER NOT NULL,
      user_name TEXT NOT NULL,
      locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (class_name, school_hour)
    )
  `);
  console.log('✓ Πίνακας class_locks έτοιμος');
}

/** Στήλη ωριαίας απομάκρυνσης + αρκετό μήκος για email_status. */
async function ensureAttendanceSchema() {
  await pool.query(`
    ALTER TABLE attendance
    ADD COLUMN IF NOT EXISTS is_hourly_removal BOOLEAN NOT NULL DEFAULT FALSE
  `);
  // Παλιά τιμή HOURLY_REMOVAL_SKIPPED (23) δεν χωρούσε σε varchar(20)
  await pool.query(`
    ALTER TABLE attendance
    ALTER COLUMN email_status TYPE VARCHAR(50)
  `);
  console.log('✓ Σχήμα attendance (hourly removal / email_status) έτοιμο');
}

async function ensureSchema() {
  await ensureClassLocksTable();
  await ensureAttendanceSchema();
}

module.exports = {
  // Απλά queries
  query: (text, params) => pool.query(text, params),
  ensureClassLocksTable,
  ensureAttendanceSchema,
  ensureSchema,

  // 3. ΔΙΟΡΘΩΣΗ: Προσθήκη getClient για υποστήριξη Transactions (BEGIN/COMMIT)
  getClient: async () => {
    const client = await pool.connect();
    
    // Προσθέτουμε ένα custom release function για να πιάνουμε διαρροές (leaks)
    const query = client.query;
    const release = client.release;
    
    // Timeout 5 δευτερολέπτων. Αν ξεχάσουμε να κάνουμε client.release() στο route, 
    // θα πετάξει error για να μας ειδοποιήσει αντί να "κολλήσει" τη βάση.
    const timeout = setTimeout(() => {
      console.error('Ο client κρατήθηκε ανοιχτός για πάνω από 5 δευτερόλεπτα! Πιθανή διαρροή μνήμης.');
      console.error(`Τελευταίο query που εκτελέστηκε: ${client.lastQuery}`);
    }, 5000);

    client.query = (...args) => {
      client.lastQuery = args;
      return query.apply(client, args);
    };

    client.release = () => {
      clearTimeout(timeout);
      client.query = query;
      client.release = release;
      return release.apply(client);
    };

    return client;
  }
};