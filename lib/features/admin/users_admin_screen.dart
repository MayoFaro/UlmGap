import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import 'user_form_dialog.dart';

class UsersAdminScreen extends StatelessWidget {
  const UsersAdminScreen({super.key});

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppServices.of(context).admin!;
    return Scaffold(
      appBar: AppBar(title: const Text('Comptes')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouveau compte',
        child: const Icon(Icons.person_add),
        onPressed: () async {
          final input = await showUserFormDialog(context);
          if (input != null && context.mounted) {
            await _guard(context, () => api.createUser(input));
          }
        },
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: api.watchAllUsers(),
        builder: (context, snap) {
          final users = snap.data ?? const <AppUser>[];
          return ListView(
            children: [
              for (final u in users)
                ListTile(
                  // Pas de `enabled: false` : un compte désactivé doit rester
                  // cliquable pour pouvoir être réactivé.
                  textColor: u.active ? null : Theme.of(context).disabledColor,
                  leading: ProfileBadge(profile: u.profile, compact: true),
                  title: Text(u.displayName),
                  subtitle: Text('${u.shortName} · ${u.email}'),
                  trailing: Wrap(spacing: 6, children: [
                    Chip(label: Text(u.category.code)),
                    if (u.isAdmin) const Icon(Icons.admin_panel_settings),
                    if (!u.active) const Chip(label: Text('Désactivé')),
                  ]),
                  onTap: () async {
                    final patch = await showUserFormDialog(context, user: u);
                    if (patch != null && context.mounted) {
                      await _guard(context, () => api.updateUser(u.uid, patch));
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
