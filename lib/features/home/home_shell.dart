import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import '../account/account_screen.dart';
import '../admin/aircraft_admin_screen.dart';
import '../admin/users_admin_screen.dart';
import '../flight/flight_screen.dart';
import '../instructors/instructors_screen.dart';
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
          IconButton(
            tooltip: 'Mon compte',
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AccountScreen(me: user),
            )),
          ),
          if (user.isInstructor || user.isAdmin)
            IconButton(
              tooltip: 'Instructeurs',
              icon: const Icon(Icons.groups),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const InstructorsScreen(),
              )),
            ),
          if (user.isAdmin)
            PopupMenuButton<String>(
              tooltip: 'Administration',
              icon: const Icon(Icons.admin_panel_settings),
              onSelected: (v) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    v == 'users' ? const UsersAdminScreen() : const AircraftAdminScreen(),
              )),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'users', child: Text('Comptes')),
                PopupMenuItem(value: 'aircraft', child: Text('Appareils')),
              ],
            ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: AppServices.of(context).auth.signOut,
          ),
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
