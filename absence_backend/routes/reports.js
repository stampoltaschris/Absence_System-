const express = require('express');
const router = express.Router();
const db = require('../db');
const authenticateToken = require('../middleware/auth'); // Προσθήκη για ασφάλεια

// ==========================================
// GET /api/reports/logs
// ==========================================
router.get('/logs', authenticateToken, async (req, res) => {
  try {
    const { startDate, endDate, teacherIds, classNames } = req.query;

    // 🛡️ RBAC Έλεγχος: Αν είναι απλός καθηγητής, μπορεί να δει μόνο τις δικές του αναφορές
    let effectiveTeacherIds = teacherIds;
    if (req.user.role === 'teacher') {
      effectiveTeacherIds = req.user.id.toString(); // Περιορισμός αποκλειστικά στον ίδιο
    }

    let queryText = `
      SELECT 
        a.id AS attendance_id,
        a.date,
        a.hour AS school_hour,
        a.class_name,
        a.is_absent,
        a.is_excused,
        a.is_hourly_removal,
        a.excuse_reason,
        a.email_status,
        s.id AS student_id,
        s.name AS student_name,
        s.email AS parent_email,
        u.id AS teacher_id,
        u.name AS teacher_name
      FROM attendance a
      JOIN students s ON a.student_id = s.id
      JOIN users u ON a.teacher_id = u.id
      WHERE 1=1
    `;

    const queryParams = [];
    let paramIndex = 1;

    // Φίλτρο εύρους ημερομηνιών
    if (startDate && endDate) {
      queryText += ` AND a.date >= $${paramIndex} AND a.date <= $${paramIndex + 1}`;
      queryParams.push(startDate, endDate);
      paramIndex += 2;
    } else {
      // 🛡️ ΠΡΟΣΤΑΣΙΑ RAM: Αν δεν δωθούν ημερομηνίες, περιορίζουμε αυτόματα στον τελευταίο μήνα για αποφυγή OOM (Out Of Memory)
      queryText += ` AND a.date >= CURRENT_DATE - INTERVAL '30 days'`;
    }

    // Φίλτρο εκπαιδευτικών
    if (effectiveTeacherIds) {
      const idsArray = effectiveTeacherIds.split(',').map(id => parseInt(id.trim())).filter(id => !isNaN(id));
      if (idsArray.length > 0) {
        queryText += ` AND a.teacher_id = ANY($${paramIndex}::int[])`;
        queryParams.push(idsArray);
        paramIndex++;
      }
    }

    // Φίλτρο τμημάτων
    if (classNames) {
      const namesArray = classNames.split(',').map(name => name.trim());
      if (namesArray.length > 0) {
        queryText += ` AND a.class_name = ANY($${paramIndex}::text[])`;
        queryParams.push(namesArray);
        paramIndex++;
      }
    }

    queryText += ` ORDER BY a.date DESC, a.hour ASC, a.class_name ASC, s.name ASC LIMIT 5000`; // Όριο ασφαλείας 5000 εγγραφών

    const result = await db.query(queryText, queryParams);

    // Ομαδοποίηση εγγραφών ανά Υποβολή
    const groupedReportsMap = new Map();

    result.rows.forEach(row => {
      const groupKey = `${row.date}_${row.school_hour}_${row.class_name}_${row.teacher_id}`;

      if (!groupedReportsMap.has(groupKey)) {
        groupedReportsMap.set(groupKey, {
          date: row.date,
          schoolHour: row.school_hour,
          className: row.class_name,
          teacherId: row.teacher_id,
          teacherName: row.teacher_name,
          totalStudents: 0,
          absentCount: 0,
          emailSuccessCount: 0,
          emailFailedCount: 0,
          studentsDetails: []
        });
      }

      const group = groupedReportsMap.get(groupKey);
      group.totalStudents++;

      if (row.is_absent) {
        group.absentCount++;
        if (row.email_status === 'SENT') {
          group.emailSuccessCount++;
        } else if (row.email_status === 'FAILED') {
          group.emailFailedCount++;
        }
      }

      group.studentsDetails.push({
        studentId: row.student_id,
        studentName: row.student_name,
        parentEmail: row.parent_email,
        isAbsent: row.is_absent,
        isExcused: row.is_excused,
        isHourlyRemoval: row.is_hourly_removal,
        excuseReason: row.excuse_reason,
        emailStatus: row.email_status
      });
    });

    const reports = Array.from(groupedReportsMap.values());
    res.json({ success: true, count: reports.length, data: reports });

  } catch (err) {
    console.error("❌ Σφάλμα κατά την παραγωγή αναφορών:", err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;