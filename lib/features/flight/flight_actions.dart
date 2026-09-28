import '../../data/app_user.dart';
import '../../data/flight.dart';

enum FlightAction { validate, refuse, edit, cancel }

/// Spec §3.3 : ce que [me] peut faire sur [f]. Tout est fermé après le départ.
/// Le serveur revérifie chaque action.
Set<FlightAction> flightActions(Flight f, AppUser me, DateTime now) {
  if (f.deleted || f.isClosed || !f.start.isAfter(now)) return {};
  final reviewer = me.isAdmin || f.instructorUid == me.uid;
  final creator = f.createdBy == me.uid;
  return {
    if (f.status == FlightStatus.demande && reviewer) ...{
      FlightAction.validate,
      FlightAction.refuse,
    },
    if (creator) FlightAction.edit,
    if (creator || reviewer) FlightAction.cancel,
  };
}
