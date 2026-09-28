// Miroir de functions/src/rules/flights.ts, pour l'aperçu du formulaire.
// Cas partagés : test/fixtures/flight_rules.json. L'aperçu est indicatif :
// la décision finale revient toujours aux Functions.

/// Durée prévue minimale (le plan 3 la lira dans settings/pricing).
const minPlannedMinutes = 45;
/// Durée prévue maximale.
const maxPlannedHours = 12;

class RulePerson {
  const RulePerson(this.uid, this.profile);
  final String uid;
  final String? profile; // code de profil, null = non pilote
}

class Decision {
  const Decision.ok(this.status, this.instructorUid) : reason = null;
  const Decision.refused(this.reason)
      : status = null,
        instructorUid = null;

  final String? status; // 'valide' | 'demande'
  final String? instructorUid;
  final String? reason;
  bool get ok => status != null;
}

String? designatedInstructor(String creatorUid, List<RulePerson> crew) {
  for (final p in crew) {
    if (p.uid != creatorUid && p.profile == 'instructeur') return p.uid;
  }
  return null;
}

Decision decideStatus({
  required String creatorUid,
  required String? creatorProfile,
  required bool creatorIsAdmin,
  required List<RulePerson> crew,
  required int passengers,
}) {
  final instructorUid = designatedInstructor(creatorUid, crew);
  if (creatorIsAdmin) return Decision.ok('valide', instructorUid);
  if (!crew.any((p) => p.uid == creatorUid)) {
    return const Decision.refused('Vous devez faire partie de l\'équipage.');
  }
  if (creatorProfile == null) {
    return const Decision.refused('Un compte non pilote ne peut pas créer de vol.');
  }
  if (creatorProfile == 'instructeur') return Decision.ok('valide', instructorUid);
  if (instructorUid != null) return Decision.ok('demande', instructorUid);
  if (creatorProfile == 'eleve') {
    return const Decision.refused('Un élève ne peut voler qu\'avec un instructeur.');
  }
  if (crew.length + passengers == 2 && creatorProfile == 'lache_solo') {
    return const Decision.refused('Un lâché solo ne vole à deux qu\'avec un instructeur.');
  }
  return const Decision.ok('valide', null);
}

String resolvePricingMode({
  required bool allGap,
  required bool hasPassenger,
  required bool mayChoose,
  String? requested,
  String? previous,
}) {
  if (!allGap) return 'standard';
  if (hasPassenger) return 'fuel_only';
  if (!mayChoose) return 'standard';
  return (requested ?? previous ?? 'standard') == 'fuel_only' ? 'fuel_only' : 'standard';
}

class RuleFlight {
  const RuleFlight({
    this.id,
    required this.start,
    required this.end,
    required this.aircraftId,
    required this.crew,
    this.status = 'valide',
    this.deleted = false,
  });

  final String? id;
  final int start;
  final int end;
  final String aircraftId;
  final List<String> crew;
  final String status;
  final bool deleted;
}

/// Vols valide non supprimés, bornes ouvertes, même appareil ou même personne.
RuleFlight? findConflict(RuleFlight c, Iterable<RuleFlight> others) {
  for (final o in others) {
    if (o.id != null && o.id == c.id) continue;
    if (o.status != 'valide' || o.deleted) continue;
    if (!(c.start < o.end && o.start < c.end)) continue;
    if (o.aircraftId == c.aircraftId || o.crew.any(c.crew.contains)) return o;
  }
  return null;
}
