import 'package:flutter/material.dart';

/// Message d'erreur de connexion, réutilisable hors flux de liste (par
/// exemple un flux à valeur unique où `hasData` ne distingue pas « en
/// cours » de « chargé, valeur nulle »).
Widget connectionErrorMessage() => const _Message(
    icon: Icons.error_outline,
    text: 'Impossible de charger les données. Vérifiez la connexion.');

/// État d'un flux de liste : chargement, erreur ou liste vide. Renvoie `null`
/// quand il y a des données à afficher.
Widget? asyncState(AsyncSnapshot<Object?> snap,
    {required bool isEmpty, required String empty}) {
  if (snap.hasError) return connectionErrorMessage();
  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
  if (isEmpty) return _Message(icon: Icons.inbox_outlined, text: empty);
  return null;
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Theme.of(context).disabledColor),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}
