import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/profile_badge.dart';
import '../../core/profiles.dart';
import '../../data/admin_api.dart';
import '../../data/app_user.dart';
import '../../data/services.dart';
import 'user_form_dialog.dart';
import '../home/app_nav.dart';

class UsersAdminScreen extends StatelessWidget {
  const UsersAdminScreen({super.key, this.me});

  /// Compte connecté : icônes de navigation (absentes si null).
  final AppUser? me;

  static Widget _chip(String label) => Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: const TextStyle(fontSize: 12),
        padding: EdgeInsets.zero,
      );

  /// Suppression d'un compte vierge (révision du 2026-10-06), après
  /// confirmation ; le serveur refuse un compte qui a un historique.
  Future<void> _delete(BuildContext context, AdminApi api, AppUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer définitivement le compte de ${u.displayName} ?'),
        content: const Text('Possible seulement pour un compte sans vol ni mouvement de solde.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, supprimer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _guard(context, () async {
      await api.deleteUser(u.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Compte supprimé.')));
      }
    });
  }

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
      appBar: AppBar(
        title: const Text('Comptes'),
        actions: me == null ? null : appNavActions(context, me!, current: AppDestination.users),
      ),
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
          final users = sortedByProfile(
              snap.data ?? const <AppUser>[], (u) => u.profile, (u) => u.displayName);
          final state = asyncState(snap, isEmpty: users.isEmpty, empty: 'Aucun compte.');
          if (state != null) return state;
          return ListView(
            children: [
              for (final u in users)
                ListTile(
                  // Pas de `enabled: false` : un compte désactivé doit rester
                  // cliquable pour pouvoir être réactivé.
                  textColor: u.active ? null : Theme.of(context).disabledColor,
                  leading: ProfileBadge(profile: u.profile, compact: true),
                  title: Text(u.displayName),
                  // Révision du 2026-10-06 : puces sous le nom, seule l'icône
                  // du lien à droite (lisible sur un écran étroit).
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${u.shortName} · ${u.email}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _chip(u.category.code),
                      if (u.amphibiousCleared) _chip('amphibie'),
                      if (u.isAdmin) _chip('admin'),
                      if (!u.active) _chip('Désactivé'),
                    ]),
                  ]),
                  trailing: IconButton(
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
                  onTap: () async {
                    final patch = await showUserFormDialog(context, user: u);
                    if (identical(patch, userDeleteRequest) && context.mounted) {
                      await _delete(context, api, u);
                    } else if (patch != null && context.mounted) {
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
