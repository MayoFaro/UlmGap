// Compteurs d'heures (spec §5) : base = actualFlightMinutes des vols
// clôturés, non supprimés. Fonctions pures, testées sans widget.
import '../../data/flight.dart';

/// Minutes comptées pour [f] : 0 s'il n'est pas clôturé, s'il est supprimé
/// ou s'il n'a pas de durée réelle.
int countedMinutes(Flight f) =>
    f.isClosed && !f.deleted ? (f.actualFlightMinutes ?? 0) : 0;

/// Total d'un pilote : chaque membre de `crew` cumule le vol (décision 3).
int pilotMinutes(Iterable<Flight> flights, String uid) => flights
    .where((f) => f.crew.contains(uid))
    .fold(0, (sum, f) => sum + countedMinutes(f));

/// Total d'un appareil.
int aircraftMinutes(Iterable<Flight> flights, String aircraftId) => flights
    .where((f) => f.aircraftId == aircraftId)
    .fold(0, (sum, f) => sum + countedMinutes(f));
