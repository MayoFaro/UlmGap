// Rappel de clôture au lancement (spec §5) : le vol terminé et non clôturé
// dont l'utilisateur est membre d'équipage, le plus ancien d'abord. Pur.
import '../../data/flight.dart';

/// Vol validé, non clôturé, non supprimé, dont [uid] est membre d'équipage
/// et dont l'heure de fin est passée ; le plus ancien (départ), ou null.
Flight? firstFlightToClose(Iterable<Flight> flights, String uid, DateTime now) {
  final candidates = flights
      .where((f) =>
          f.status == FlightStatus.valide &&
          !f.isClosed &&
          !f.deleted &&
          f.crew.contains(uid) &&
          !f.end.isAfter(now))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return candidates.isEmpty ? null : candidates.first;
}
