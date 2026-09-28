import '../core/profiles.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.shortName,
    required this.email,
    required this.profile,
    required this.category,
    required this.isAdmin,
    required this.active,
    required this.balance,
  });

  final String uid;
  final String displayName;
  final String shortName;
  final String email;
  final PilotProfile? profile;
  final UserCategory category;
  final bool isAdmin;
  final bool active;
  final int balance;

  bool get isInstructor => profile == PilotProfile.instructeur;

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) => AppUser(
        uid: uid,
        displayName: (m['displayName'] as String?) ?? '',
        shortName: (m['shortName'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        profile: PilotProfile.fromCode(m['profile'] as String?),
        category: UserCategory.fromCode(m['category'] as String?),
        isAdmin: m['isAdmin'] == true,
        active: m['active'] == true,
        balance: (m['balance'] as num?)?.toInt() ?? 0,
      );
}
