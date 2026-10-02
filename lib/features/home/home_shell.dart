import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../flight/flight_screen.dart';
import 'app_nav.dart';
import '../planning/planning_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
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
