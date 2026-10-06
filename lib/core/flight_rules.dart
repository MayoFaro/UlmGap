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

class AmphibiousPerson {
  const AmphibiousPerson(this.profile, this.amphibiousCleared);
  final String? profile; // code de profil, null = non pilote
  final bool amphibiousCleared;
}

/// Équipage d'un appareil amphibie (spec §3.6) ; null si la règle est respectée.
String? amphibiousError(List<AmphibiousPerson> crew) {
  final instructors = crew.where((p) => p.profile == 'instructeur');
  if (instructors.isNotEmpty) {
    return instructors.any((p) => p.amphibiousCleared)
        ? null
        : "Appareil amphibie : l'instructeur doit être lâché amphibie.";
  }
  return crew.any((p) => p.amphibiousCleared)
      ? null
      : 'Appareil amphibie : il faut un pilote lâché amphibie à bord.';
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

/// Vol d'instruction possible : exactement deux membres d'équipage dont un
/// seul instructeur (miroir de functions/src/rules/flights.ts).
bool isInstructionEligible(List<RulePerson> crew) =>
    crew.length == 2 && crew.where((p) => p.profile == 'instructeur').length == 1;

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
  if (creatorIsAdmin || creatorProfile == 'instructeur') {
    return Decision.ok('valide', instructorUid);
  }
  if (!crew.any((p) => p.uid == creatorUid)) {
    return const Decision.refused('Vous devez faire partie de l\'équipage.');
  }
  if (creatorProfile == null) {
    return const Decision.refused('Un compte non pilote ne peut pas créer de vol.');
  }
  if (instructorUid != null) return Decision.ok('demande', instructorUid);
  if (creatorProfile == 'eleve') {
    return const Decision.refused(
        'Impossible de créer un vol à votre profit sans la présence d\'un instructeur.');
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
  if (!mayChoose) return previous == 'fuel_only' ? 'fuel_only' : 'standard';
  return (requested ?? previous ?? 'standard') == 'fuel_only' ? 'fuel_only' : 'standard';
}

/// Décision utilisateur : hors instructeurs et admins, le créateur est le
/// compte débité (spec §4.2, mirroir functions/src/rules/flights.ts).
String? checkPayer({
  required String creatorUid,
  required String? creatorProfile,
  required bool creatorIsAdmin,
  required List<String> crew,
}) {
  if (creatorIsAdmin || creatorProfile == 'instructeur') return null;
  if (!crew.contains(creatorUid)) return null; // laissé à la matrice (decideStatus)
  return crew.isNotEmpty && crew[0] == creatorUid
      ? null
      : 'Le compte débité doit être le vôtre : placez-vous en premier.';
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
    this.closed = false,
  });

  final String? id;
  final int start;
  final int end;
  final String aircraftId;
  final List<String> crew;
  final String status;
  final bool deleted;

  /// Vol clôturé : jamais en conflit (révision du 2026-10-01).
  final bool closed;
}

/// Plan 9 : battement fixe entre deux vols (même appareil ou même personne).
const flightBufferMinutes = 30;
const _bufferMs = flightBufferMinutes * 60000;

/// Vols valide non supprimés et non clôturés, bornes ouvertes (un écart
/// d'exactement 30 min est accepté), même appareil ou même personne (miroir
/// de functions/src/rules/flights.ts).
RuleFlight? findConflict(RuleFlight c, Iterable<RuleFlight> others) {
  for (final o in others) {
    if (o.id != null && o.id == c.id) continue;
    if (o.status != 'valide' || o.deleted || o.closed) continue;
    if (!(c.start < o.end + _bufferMs && o.start < c.end + _bufferMs)) continue;
    if (o.aircraftId == c.aircraftId || o.crew.any(c.crew.contains)) return o;
  }
  return null;
}

/// Révision du 2026-10-01 : les conflits bloquent la planification, jamais
/// la conduite (vol clôturé ou départ atteint).
bool isPlanning({required int start, required int now, required bool closed}) =>
    !closed && start > now;

/// Cause d'un conflit : l'appareil d'abord, sinon les personnes communes.
({String kind, List<String> members}) conflictCause(RuleFlight candidate, RuleFlight other) {
  if (candidate.aircraftId == other.aircraftId) return (kind: 'aircraft', members: const <String>[]);
  return (kind: 'crew', members: candidate.crew.where(other.crew.contains).toList());
}
