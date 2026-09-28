import '../core/profiles.dart';

/// Entrée de l'annuaire public (collection profiles).
class CrewMember {
  const CrewMember({
    required this.uid,
    required this.displayName,
    required this.shortName,
    required this.profile,
    required this.active,
  });

  final String uid;
  final String displayName;
  final String shortName;
  final PilotProfile? profile;
  final bool active;

  factory CrewMember.fromMap(String uid, Map<String, dynamic> m) => CrewMember(
        uid: uid,
        displayName: (m['displayName'] as String?) ?? '',
        shortName: (m['shortName'] as String?) ?? '',
        profile: PilotProfile.fromCode(m['profile'] as String?),
        active: m['active'] == true,
      );
}
