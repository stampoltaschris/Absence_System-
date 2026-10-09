/**
 * Feature smoke tests against running local backend.
 * Usage: node scripts/feature_smoke_test.js [adminUser] [adminPass]
 */
const BASE = process.env.API_BASE || 'http://localhost:5000/api';

const args = process.argv.slice(2);
const ADMIN_USER = args[0] || 'admin';
const ADMIN_PASS = args[1] || 'admin';

const results = [];
let token = null;
let teacherToken = null;
let createdTeacherId = null;
const TEST_PERIOD = '7η ώρα'; // λιγότερο πιθανό να έχει ήδη δεδομένα σήμερα
const TEST_CLASS = 'Α4';

function ok(name, detail = '') {
  results.push({ name, pass: true, detail });
  console.log(`✅ ${name}${detail ? ' — ' + detail : ''}`);
}
function fail(name, detail = '') {
  results.push({ name, pass: false, detail });
  console.log(`❌ ${name}${detail ? ' — ' + detail : ''}`);
}

async function req(method, path, body, useToken = token) {
  const headers = { 'Content-Type': 'application/json' };
  if (useToken) headers.Authorization = `Bearer ${useToken}`;
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers,
    body: body != null ? JSON.stringify(body) : undefined,
  });
  let data = null;
  const text = await res.text();
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }
  return { status: res.status, data };
}

async function login(username, password) {
  return req('POST', '/auth/login', { username, password }, null);
}

async function run() {
  console.log(`\n=== Absence System smoke test @ ${BASE} ===\n`);

  // 1. Health
  {
    const r = await req('GET', '/health', null, null);
    if (r.status === 200 && r.data?.status === 'OK') ok('Health check', r.data.message);
    else fail('Health check', `status=${r.status}`);
  }

  // 2. Admin login
  {
    const r = await login(ADMIN_USER, ADMIN_PASS);
    if (r.status === 200 && r.data?.token) {
      token = r.data.token;
      ok('Admin login', `user=${r.data.user?.username} role=${r.data.user?.role}`);
    } else {
      fail('Admin login', r.data?.message || `status=${r.status}`);
      console.log('\nΔώσε σωστό κωδικό: node scripts/feature_smoke_test.js admin <password>\n');
      printSummary();
      process.exit(1);
    }
  }

  // 3. Schedule settings (GET)
  {
    const r = await req('GET', '/settings/schedule');
    if (r.status === 200 && (r.data?.teachingHours || r.data?.forceTestMode !== undefined)) {
      ok('Schedule settings GET', `forceTestMode=${r.data.forceTestMode}`);
    } else fail('Schedule settings GET', `status=${r.status}`);
  }

  // 4. Teacher CRUD
  const uname = `test_t_${Date.now().toString().slice(-6)}`;
  {
    const r = await req('POST', '/auth/users', {
      name: 'TEST Εκπαιδευτικός',
      username: uname,
      password: 'Test1234!',
      role: 'teacher',
    });
    if ((r.status === 200 || r.status === 201) && (r.data?.user?.id || r.data?.id)) {
      createdTeacherId = r.data.user?.id || r.data.id;
      ok('Teacher CREATE', `id=${createdTeacherId} @${uname}`);
    } else fail('Teacher CREATE', r.data?.message || `status=${r.status}`);
  }

  {
    const r = await req('GET', '/auth/users?role=teacher');
    if (r.status === 200 && Array.isArray(r.data)) {
      const found = r.data.some((u) => u.id === createdTeacherId || u.username === uname);
      if (found) ok('Teacher LIST', `count=${r.data.length}`);
      else fail('Teacher LIST', 'νεοδημιουργημένος δεν εμφανίζεται');
    } else fail('Teacher LIST', `status=${r.status}`);
  }

  if (createdTeacherId) {
    const r = await req('PUT', `/auth/users/${createdTeacherId}`, {
      name: 'TEST Εκπαιδευτικός Updated',
      username: uname,
      password: 'Test5678!',
    });
    if (r.status === 200 && r.data?.success !== false) ok('Teacher UPDATE', r.data?.message || '');
    else fail('Teacher UPDATE', r.data?.message || `status=${r.status}`);
  }

  // Teacher login
  {
    const r = await login(uname, 'Test5678!');
    if (r.status === 200 && r.data?.token) {
      teacherToken = r.data.token;
      ok('Teacher login after update', uname);
    } else fail('Teacher login after update', r.data?.message || `status=${r.status}`);
  }

  // 5. Classes list
  let classStudents = [];
  {
    const r = await req('GET', `/school/classes?currentHour=${encodeURIComponent(TEST_PERIOD)}`);
    if (r.status === 200 && Array.isArray(r.data)) {
      ok('Classes list', `count=${r.data.length}`);
      const cls = r.data.find((c) => c.name === TEST_CLASS);
      if (cls?.id) {
        const s = await req('GET', `/school/students/${cls.id}`);
        // try common paths
        let studentsRes = s;
        if (s.status !== 200) {
          studentsRes = await req('GET', `/school/classes/${cls.id}/students`);
        }
        // ApiService.getStudentsByClass - check route
      }
    } else fail('Classes list', `status=${r.status}`);
  }

  // Discover students endpoint from school routes
  {
    const classes = await req('GET', `/school/classes?currentHour=${encodeURIComponent(TEST_PERIOD)}`);
    const cls = (classes.data || []).find((c) => c.name === TEST_CLASS);
    if (!cls) {
      fail('Find test class', TEST_CLASS);
    } else {
      // try getStudentsByClass pattern used in Flutter
      const r = await req('GET', `/school/students/class/${cls.id}`);
      if (r.status === 200 && Array.isArray(r.data)) {
        classStudents = r.data;
        ok('Students by class', `${TEST_CLASS}: ${classStudents.length}`);
      } else {
        fail('Students by class', `status=${r.status} tried /school/students/class/${cls.id}`);
      }
    }
  }

  // 6. Lock / unlock
  {
    const lock = await req(
      'POST',
      '/school/lock-class',
      { className: TEST_CLASS, currentHour: TEST_PERIOD },
      teacherToken || token
    );
    if (lock.status === 200 && lock.data?.success !== false) {
      ok('Lock class', lock.data?.message || TEST_CLASS);
    } else fail('Lock class', lock.data?.message || `status=${lock.status}`);

    const unlock = await req(
      'POST',
      '/school/unlock-class',
      { className: TEST_CLASS, currentHour: TEST_PERIOD },
      teacherToken || token
    );
    if (unlock.status === 200 && unlock.data?.success !== false) {
      ok('Unlock class', unlock.data?.message || TEST_CLASS);
    } else fail('Unlock class', unlock.data?.message || `status=${unlock.status}`);
  }

  // Re-lock for attendance flow
  await req(
    'POST',
    '/school/lock-class',
    { className: TEST_CLASS, currentHour: TEST_PERIOD },
    teacherToken || token
  );

  // 7. Attendance: reserved (δέσμευση) + one absent + rest present
  if (classStudents.length >= 2) {
    // Clean any prior test data for this period today? may fail if already submitted
    const absences = classStudents.map((s, i) => {
      const id = s.id;
      if (i === 0) {
        // reserved - not absence
        return {
          studentId: id,
          studentName: s.name,
          absent: false,
          isAbsent: false,
          is_absent: 0,
          isExcused: true,
          is_excused: true,
          excuseReason: 'Πρόβα γιορτής',
          excuse_reason: 'Πρόβα γιορτής',
          guardianEmail: s.email || '',
        };
      }
      if (i === 1) {
        // real absence
        return {
          studentId: id,
          studentName: s.name,
          absent: true,
          isAbsent: true,
          is_absent: 1,
          isExcused: false,
          isHourlyRemoval: false,
          guardianEmail: s.email || '',
        };
      }
      // present
      return {
        studentId: id,
        studentName: s.name,
        absent: false,
        isAbsent: false,
        is_absent: 0,
        isExcused: false,
        guardianEmail: s.email || '',
      };
    });

    const submit = await req(
      'POST',
      '/attendance/submit',
      {
        className: TEST_CLASS,
        period: TEST_PERIOD,
        absences,
      },
      teacherToken || token
    );

    if (submit.status === 200 && submit.data?.success !== false) {
      ok('Submit attendance (mix reserved+absent)', submit.data?.message || '');
    } else {
      fail('Submit attendance (mix reserved+absent)', submit.data?.message || `status=${submit.status}`);
    }

    // Verify records
    const records = await req(
      'GET',
      `/attendance/records?className=${encodeURIComponent(TEST_CLASS)}&period=${encodeURIComponent(TEST_PERIOD)}`,
      null,
      teacherToken || token
    );
    if (records.status === 200) {
      const list = records.data?.records || records.data || [];
      const reserved = list.filter(
        (x) => x.isExcused === true && !(x.isAbsent === true || x.is_absent === 1)
      );
      const absent = list.filter(
        (x) => (x.isAbsent === true || x.is_absent === 1) && !x.isHourlyRemoval
      );
      if (reserved.length >= 1) ok('Reserved = not absence in DB', `reserved=${reserved.length}`);
      else fail('Reserved = not absence in DB', JSON.stringify(list.slice(0, 2)));
      if (absent.length >= 1) ok('Real absence stored', `absent=${absent.length}`);
      else fail('Real absence stored', `absent=${absent.length}`);
    } else fail('Fetch attendance records', `status=${records.status}`);
  } else {
    fail('Attendance submit skipped', 'όχι αρκετοί μαθητές');
  }

  // 8. Hourly removal on a present student
  if (classStudents.length >= 3) {
    const presentId = classStudents[2].id;
    const hr = await req(
      'POST',
      '/attendance/hourly-removal',
      {
        className: TEST_CLASS,
        period: TEST_PERIOD,
        studentIds: [presentId],
      },
      teacherToken || token
    );
    if (hr.status === 200 && hr.data?.success !== false) {
      ok('Hourly removal', hr.data?.message || '');
    } else fail('Hourly removal', hr.data?.message || `status=${hr.status}`);
  }

  // 9. Double submit should fail
  if (classStudents.length >= 1) {
    const again = await req(
      'POST',
      '/attendance/submit',
      {
        className: TEST_CLASS,
        period: TEST_PERIOD,
        absences: classStudents.map((s) => ({
          studentId: s.id,
          absent: false,
          isAbsent: false,
          is_absent: 0,
        })),
      },
      teacherToken || token
    );
    if (again.status >= 400) ok('Double submit blocked', again.data?.message || `status=${again.status}`);
    else fail('Double submit blocked', 'επέτρεψε δεύτερη υποβολή');
  }

  // 10. Submitted list + daily summary
  {
    const today = new Date().toISOString().slice(0, 10);
    const sub = await req(
      'GET',
      `/attendance/submitted?date=${today}&schoolHour=${encodeURIComponent(TEST_PERIOD)}`
    );
    if (sub.status === 200) ok('Submitted classes GET', JSON.stringify(sub.data).slice(0, 120));
    else fail('Submitted classes GET', `status=${sub.status}`);

    const sum = await req('GET', `/attendance/daily-summary?date=${today}`);
    if (sum.status === 200) {
      const body = sum.data || {};
      const hasReserved =
        body.reservedStudents != null ||
        JSON.stringify(body).includes('RESERVED') ||
        JSON.stringify(body).includes('δεσμε');
      ok('Daily summary GET', hasReserved ? 'includes reserved info' : 'ok (check reserved field manually)');
    } else fail('Daily summary GET', `status=${sum.status}`);
  }

  // 11. SMTP settings (admin only)
  {
    const r = await req('GET', '/settings/smtp');
    if (r.status === 200) ok('SMTP settings GET (admin)', 'ok');
    else fail('SMTP settings GET (admin)', `status=${r.status}`);

    if (teacherToken) {
      const t = await req('GET', '/settings/smtp', null, teacherToken);
      if (t.status === 403 || t.status === 401) ok('SMTP blocked for teacher', `status=${t.status}`);
      else fail('SMTP blocked for teacher', `status=${t.status} (έπρεπε 403)`);
    }
  }

  // 12. Cleanup test teacher
  if (createdTeacherId) {
    // May fail if FK from attendance - teacher submitted attendance
    const del = await req('DELETE', `/auth/users/${createdTeacherId}`);
    if (del.status === 200 && del.data?.success !== false) {
      ok('Teacher DELETE cleanup', del.data?.message || '');
    } else {
      // expected if CASCADE deleted attendance or blocked
      fail('Teacher DELETE cleanup', del.data?.message || `status=${del.status} (πιθανό λόγω απουσιών που υπέβαλε)`);
    }
  }

  // 13. Admin cannot be deleted as teacher path
  {
    const users = await req('GET', '/auth/users');
    const admin = (users.data || []).find((u) => u.role === 'admin');
    if (admin) {
      const del = await req('DELETE', `/auth/users/${admin.id}`);
      if (del.status >= 400) ok('Admin delete blocked via teacher CRUD', del.data?.message || '');
      else fail('Admin delete blocked via teacher CRUD', 'διέγραψε admin!');
    }
  }

  printSummary();
}

function printSummary() {
  const passed = results.filter((r) => r.pass).length;
  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n=== SUMMARY: ${passed} passed, ${failed} failed / ${results.length} total ===\n`);
  if (failed) {
    console.log('Failures:');
    results.filter((r) => !r.pass).forEach((r) => console.log(` - ${r.name}: ${r.detail}`));
  }
  process.exit(failed ? 1 : 0);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
