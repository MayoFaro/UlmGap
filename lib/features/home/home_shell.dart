import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';

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
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: AppServices.of(context).auth.signOut,
          ),
        ],
      ),
      body: const Center(child: Text('Planning : disponible au plan 2.')),
    );
  }
}
