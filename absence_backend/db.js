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

/** Βασικοί πίνακες για fresh εγκατάσταση (IF NOT EXISTS — ασφαλές σε υπάρχον DB). */
async function ensureCoreTables() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      username TEXT NOT NULL UNIQUE,
      password TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'teacher',
      is_first_login BOOLEAN NOT NULL DEFAULT TRUE,
      is_inclusion_parallel BOOLEAN NOT NULL DEFAULT FALSE
    )
  `);
  await pool.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_inclusion_parallel BOOLEAN NOT NULL DEFAULT FALSE
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS classes (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL UNIQUE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS students (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      class_id INTEGER REFERENCES classes(id) ON DELETE CASCADE
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS attendance (
      id SERIAL PRIMARY KEY,
      student_id INTEGER REFERENCES students(id) ON DELETE SET NULL,
      teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      class_name TEXT NOT NULL,
      date DATE NOT NULL,
      hour TEXT NOT NULL,
      is_absent BOOLEAN NOT NULL DEFAULT FALSE,
      is_excused BOOLEAN NOT NULL DEFAULT FALSE,
      is_hourly_removal BOOLEAN NOT NULL DEFAULT FALSE,
      excused_by_teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      excuse_reason TEXT,
      email_status VARCHAR(50)
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS submitted_attendance (
      class_name TEXT NOT NULL,
      school_hour TEXT NOT NULL,
      date DATE NOT NULL,
      username TEXT,
      PRIMARY KEY (class_name, school_hour, date)
    )
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS schedule_settings (
      id INTEGER PRIMARY KEY DEFAULT 1,
      active_days JSONB,
      force_test_mode BOOLEAN NOT NULL DEFAULT FALSE,
      teaching_hours JSONB,
      break_durations JSONB,
      calculated_breaks JSONB,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  `);

  console.log('✓ Βασικοί πίνακες (users/classes/students/attendance/…) έτοιμοι');
}

/**
 * Δεσμεύσεις τμημάτων: πολλοί εκπαιδευτικοί / τμήμα / ώρα
 * (π.χ. ειδική αγωγή + εκπαιδευτικός τμήματος την ίδια ώρα).
 */
async function ensureClassLocksTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS class_locks (
      class_name TEXT NOT NULL,
      school_hour TEXT NOT NULL,
      user_id INTEGER NOT NULL,
      user_name TEXT NOT NULL,
      locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (class_name, school_hour, user_id)
    )
  `);

  // Μετάβαση από παλιό PK (class_name, school_hour) → multi-user
  try {
    const pk = await pool.query(`
      SELECT a.attname
      FROM pg_index i
      JOIN pg_attribute a
        ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
      WHERE i.indrelid = 'public.class_locks'::regclass
        AND i.indisprimary
      ORDER BY array_position(i.indkey, a.attnum)
    `);
    const pkCols = pk.rows.map((r) => r.attname);
    const isOldPk =
      pkCols.length === 2 &&
      pkCols[0] === 'class_name' &&
      pkCols[1] === 'school_hour';
    if (isOldPk) {
      await pool.query(`
        CREATE TABLE class_locks_mig (
          class_name TEXT NOT NULL,
          school_hour TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          user_name TEXT NOT NULL,
          locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          PRIMARY KEY (class_name, school_hour, user_id)
        )
      `);
      await pool.query(`
        INSERT INTO class_locks_mig (class_name, school_hour, user_id, user_name, locked_at)
        SELECT class_name, school_hour, user_id, user_name, locked_at
        FROM class_locks
        ON CONFLICT DO NOTHING
      `);
      await pool.query('DROP TABLE class_locks');
      await pool.query('ALTER TABLE class_locks_mig RENAME TO class_locks');
      console.log('↻ class_locks: μετάβαση σε multi-user locks (συνδιδασκαλία)');
    }
  } catch (err) {
    console.warn('⚠️ class_locks PK check:', err.message);
  }

  console.log('✓ Πίνακας class_locks (πολλαπλοί εκπαιδευτικοί / ώρα) έτοιμος');
}

/** Αναθέσεις: εκπαιδευτικός + ημέρα + διδακτική ώρα + τμήμα. */
async function ensureTeacherAssignmentsTable() {
  const colsRes = await pool.query(
    `SELECT column_name
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'teacher_class_assignments'`
  );
  const colNames = new Set(colsRes.rows.map((r) => r.column_name));

  // Παλιό σχήμα (μόνο teacher_id + class_name) → recreate
  if (colNames.size > 0 && !colNames.has('weekday')) {
    await pool.query('DROP TABLE IF EXISTS teacher_class_assignments CASCADE');
    console.log(
      '↻ teacher_class_assignments: μετάβαση σε σχήμα ημέρας+ώρας (παλιά δεδομένα καθαρίστηκαν)'
    );
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS teacher_class_assignments (
      id SERIAL PRIMARY KEY,
      teacher_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      weekday TEXT NOT NULL,
      school_hour TEXT NOT NULL,
      class_name TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (teacher_id, weekday, school_hour, class_name)
    )
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_tca_teacher
    ON teacher_class_assignments (teacher_id)
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_tca_slot
    ON teacher_class_assignments (teacher_id, weekday, school_hour)
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_tca_class
    ON teacher_class_assignments (class_name)
  `);
  console.log('✓ Πίνακας teacher_class_assignments (ημέρα+ώρα) έτοιμος');
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
  await ensureCoreTables();
  await ensureClassLocksTable();
  await ensureTeacherAssignmentsTable();
  await ensureAttendanceSchema();
}

module.exports = {
  // Απλά queries
  query: (text, params) => pool.query(text, params),
  ensureCoreTables,
  ensureClassLocksTable,
  ensureTeacherAssignmentsTable,
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