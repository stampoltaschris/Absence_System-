class UserModel {
  final int? id;
  final String name;
  final String username;
  final String password;
  final String role; // 'teacher' ή 'admin'

  UserModel({
    this.id,
    required this.name,
    required this.username,
    required this.password,
    this.role = 'teacher',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'password': password,
      'role': role,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      name: map['name'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      role: map['role'] ?? 'teacher',
    );
  }
}
