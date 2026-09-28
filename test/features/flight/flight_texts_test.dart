import 'package:flutter_test/flutter_test.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/features/flight/flight_texts.dart';

import '../../support/fakes.dart';

void main() {
  final dir = {for (final m in [member('ral', 'RAL', 'eleve'), member('hil', 'HIL', 'lache_toute_mission')]) m.uid: m};
  ConflictInfo info(String kind, List<String> members) => ConflictInfo(
      start: DateTime(2026, 9, 30, 15), end: DateTime(2026, 9, 30, 16),
      aircraft: 'TR-KJP', crew: const ['hil', 'ral'], passengers: const [],
      kind: kind, members: members);

  test('conflit d\'appareil', () {
    expect(describeConflict(info('aircraft', const []), dir),
        'Conflit : TR-KJP est déjà réservé sur le vol du mercredi 30 septembre, 15:00–16:00 (HIL/RAL).');
  });
  test('conflit de personne', () {
    expect(describeConflict(info('crew', const ['ral']), dir),
        'Conflit : RAL est déjà sur le vol du mercredi 30 septembre, 15:00–16:00 (TR-KJP, HIL/RAL).');
  });
}
