import '../../data/app_user.dart';
import '../../data/flight.dart';
import '../performed/performed.dart';

enum FlightAction { validate, refuse, edit, cancel, close, adminEdit, adminDelete }

/// Spec §3.3 : ce que [me] peut faire sur [f].
///
/// Avant le départ : validation/refus (instructeur désigné ou admin),
/// modification et annulation (créateur ou reviewer), comme au plan 2b.
/// Après le départ (Task 9, plan 3) : plus aucune de ces actions, mais un vol
/// `valide` non clôturé peut être clôturé par un membre de l'équipage ou un
/// admin (décision 2 du plan 3).
///
/// Task 10 (plan 3) : un admin gagne en plus `adminDelete`, à tout moment sur
/// tout vol non supprimé, et `adminEdit`, de même sauf sur un vol refusé (le
/// serveur refuse de corriger un vol refusé). Ces deux actions s'ajoutent aux
/// droits ci-dessus, y compris sur un vol clôturé (qui sinon n'offre plus
/// aucune action).
///
/// Plan 4, décision 6 : la clôture est permise dès le jour du vol, même
/// avant l'heure de départ, en plus des actions d'avant départ.
Set<FlightAction> flightActions(Flight f, AppUser me, DateTime now) {
  if (f.deleted) return {};
  final admin = <FlightAction>{
    if (me.isAdmin) FlightAction.adminDelete,
    if (me.isAdmin && f.status != FlightStatus.refuse) FlightAction.adminEdit,
  };
  if (f.isClosed) return admin;
  final member = f.crew.contains(me.uid) || me.isAdmin;
  final close = <FlightAction>{
    if (member && needsClosing(f, now)) FlightAction.close,
  };
  if (!f.start.isAfter(now)) return {...close, ...admin};
  final reviewer = me.isAdmin || f.instructorUid == me.uid;
  final creator = f.createdBy == me.uid;
  return {
    if (f.status == FlightStatus.demande && reviewer) ...{
      FlightAction.validate,
      FlightAction.refuse,
    },
    if (creator) FlightAction.edit,
    if (creator || reviewer) FlightAction.cancel,
    ...close,
    ...admin,
  };
}
