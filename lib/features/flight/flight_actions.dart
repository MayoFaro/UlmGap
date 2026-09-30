import '../../data/app_user.dart';
import '../../data/flight.dart';

enum FlightAction { validate, refuse, edit, cancel, close }

/// Spec §3.3 : ce que [me] peut faire sur [f].
///
/// Avant le départ : validation/refus (instructeur désigné ou admin),
/// modification et annulation (créateur ou reviewer), comme au plan 2b.
/// Après le départ (Task 9, plan 3) : plus aucune de ces actions, mais un vol
/// `valide` non clôturé peut être clôturé par un membre de l'équipage ou un
/// admin (décision 2 du plan 3).
Set<FlightAction> flightActions(Flight f, AppUser me, DateTime now) {
  if (f.deleted || f.isClosed) return {};
  if (!f.start.isAfter(now)) {
    final member = f.crew.contains(me.uid) || me.isAdmin;
    return (f.status == FlightStatus.valide && member) ? {FlightAction.close} : {};
  }
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
