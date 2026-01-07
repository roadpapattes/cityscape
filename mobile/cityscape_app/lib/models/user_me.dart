// lib/models/user_me.dart

class UserMe {
  final String username;
  final bool isStaff;
  final bool isSuperuser;

  const UserMe({
    required this.username,
    required this.isStaff,
    required this.isSuperuser,
  });

  factory UserMe.fromJson(Map<String, dynamic> j) => UserMe(
        username: j['username'] as String? ?? '',
        isStaff: j['is_staff'] == true,
        isSuperuser: j['is_superuser'] == true,
      );

  bool get isAdmin => isStaff || isSuperuser;
}
