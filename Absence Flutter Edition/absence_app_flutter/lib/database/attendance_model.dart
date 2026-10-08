class AttendanceModel {
  final int? id;
  final int studentId;
  final int teacherId;
  final String className;
  final String date;
  final String schoolHour;
  final bool isAbsent;
  final String emailStatus;

  // Νέα πεδία για τη δέσμευση μαθητή
  final bool isExcused;
  final int? excusedByTeacherId;
  final String? excuseReason;

  AttendanceModel({
    this.id,
    required this.studentId,
    required this.teacherId,
    required this.className,
    required this.date,
    required this.schoolHour,
    required this.isAbsent,
    this.emailStatus = 'PRESENT',
    this.isExcused = false,
    this.excusedByTeacherId,
    this.excuseReason,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'student_id': studentId,
      'teacher_id': teacherId,
      'class_name': className,
      'date': date,
      'school_hour': schoolHour,
      'is_absent': isAbsent,
      'email_status': emailStatus,
      'is_excused': isExcused,
      'excused_by_teacher_id': excusedByTeacherId,
      'excuse_reason': excuseReason,
    };
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id: map['id'] as int?,
      studentId: map['student_id'] as int,
      teacherId: map['teacher_id'] as int,
      className: map['class_name'] as String,
      date: map['date'] as String,
      schoolHour: map['school_hour'] as String,
      isAbsent: map['is_absent'] as bool,
      emailStatus: map['email_status'] as String? ?? 'PRESENT',
      isExcused: map['is_excused'] as bool? ?? false,
      excusedByTeacherId: map['excused_by_teacher_id'] as int?,
      excuseReason: map['excuse_reason'] as String?,
    );
  }
}
