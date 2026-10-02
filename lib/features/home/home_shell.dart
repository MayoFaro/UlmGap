import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import '../flight/flight_screen.dart';
import 'app_nav.dart';
import 'closing_reminder.dart';
import '../planning/planning_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.user, this.now = DateTime.now});
  final AppUser user;
  final DateTime Function() now;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _reminderChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reminderChecked) return;
    _reminderChecked = true;
    _remindClosing();
  }

  /// Rappel de clôture (spec §5) : une seule fois au lancement, ouvre la
  /// fiche du plus ancien vol terminé non clôturé dont l'utilisateur est
  /// membre d'équipage ; « retour » ramène à l'accueil.
  Future<void> _remindClosing() async {
    final finance = AppServices.of(context).finance;
    if (finance == null) return;
    try {
      final flights = await finance.watchValidUnclosedFlights().first;
      final f = firstFlightToClose(flights, widget.user.uid, widget.now());
      if (f == null || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlightScreen(me: widget.user, flight: f),
      ));
    } catch (_) {
      // Rappel facultatif : sans données (hors ligne, droits), on reste sur l'accueil.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('UlmGap'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Text(user.shortName),
              const SizedBox(width: 6),
              ProfileBadge(profile: user.profile, compact: true),
            ]),
          ),
          ...appNavActions(context, user),
        ],
      ),
      body: PlanningScreen(
        me: user,
        onOpen: (f) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FlightScreen(me: user, flight: f),
        )),
      ),
      floatingActionButton: (user.isAdmin || user.profile != null)
          ? FloatingActionButton(
              tooltip: 'Nouveau vol',
              child: const Icon(Icons.add),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FlightScreen(me: user),
              )),
            )
          : null,
    );
  }
}
