// lib/models/user_me.dart

class UserMe {
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final bool isStaff;
  final bool isSuperuser;

  const UserMe({
    required this.username,
    this.email = '',
    this.firstName = '',
    this.lastName = '',
    required this.isStaff,
    required this.isSuperuser,
  });

  factory UserMe.fromJson(Map<String, dynamic> j) => UserMe(
        username: j['username'] as String? ?? '',
        email: j['email'] as String? ?? '',
        firstName: j['first_name'] as String? ?? '',
        lastName: j['last_name'] as String? ?? '',
        isStaff: j['is_staff'] == true,
        isSuperuser: j['is_superuser'] == true,
      );

  bool get isAdmin => isStaff || isSuperuser;
}
