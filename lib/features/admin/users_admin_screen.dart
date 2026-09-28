import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../data/admin_api.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import 'user_form_dialog.dart';

class UsersAdminScreen extends StatelessWidget {
  const UsersAdminScreen({super.key});

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    void show(String m) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    }

    try {
      await action();
    } on PasswordLinkNotSent {
      show('Compte créé, mais l\'e-mail de mot de passe n\'a pas pu être envoyé. '
          'Utilisez « Envoyer le lien de mot de passe » sur sa ligne.');
    } on FirebaseFunctionsException catch (e) {
      show(e.message ?? e.code);
    } on FirebaseAuthException catch (e) {
      show(e.message ?? e.code);
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
                    IconButton(
                      tooltip: 'Envoyer le lien de mot de passe',
                      icon: const Icon(Icons.forward_to_inbox),
                      onPressed: () => _guard(context, () async {
                        await api.sendPasswordLink(u.email);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Lien envoyé à ${u.email}.')));
                        }
                      }),
                    ),
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
