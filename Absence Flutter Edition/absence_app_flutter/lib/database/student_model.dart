class StudentModel {
  final int? id;
  final String name;
  final String email;
  final int classId;

  StudentModel({
    this.id,
    required this.name,
    required this.email,
    required this.classId,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'email': email, 'class_id': classId};
  }

  factory StudentModel.fromMap(Map<String, dynamic> map) {
    return StudentModel(
      id: map['id'],
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      classId: map['class_id'] ?? 0,
    );
  }
}
