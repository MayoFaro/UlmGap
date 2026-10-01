// Icônes de navigation de la barre du haut, communes à l'accueil et à tous
// les écrans (retour de l'utilisateur, 2026-10-01) : on passe d'un écran à
// l'autre sans revenir à l'accueil. Un appui revient d'abord à l'accueil
// puis ouvre l'écran voulu : la pile ne grandit jamais, et « retour » ramène
// toujours à l'accueil.
import 'package:flutter/material.dart';

import '../../data/app_user.dart';
import '../account/account_screen.dart';
import '../admin/aircraft_admin_screen.dart';
import '../admin/billing_report_screen.dart';
import '../admin/pricing_admin_screen.dart';
import '../admin/users_admin_screen.dart';
import '../instructors/instructors_screen.dart';
import '../logbook/logbook_screen.dart';

enum AppDestination { logbook, account, instructors, users, aircraft, pricing, billing }

Widget _screenFor(AppDestination d, AppUser user) => switch (d) {
      AppDestination.logbook => LogbookScreen(me: user),
      AppDestination.account => AccountScreen(me: user),
      AppDestination.instructors => InstructorsScreen(me: user),
      AppDestination.users => UsersAdminScreen(me: user),
      AppDestination.aircraft => AircraftAdminScreen(me: user),
      AppDestination.pricing => PricingAdminScreen(me: user),
      AppDestination.billing => BillingReportScreen(me: user),
    };

/// Ouvre [d] juste au-dessus de l'accueil.
void goTo(BuildContext context, AppDestination d, AppUser user) {
  final nav = Navigator.of(context);
  nav.popUntil((r) => r.isFirst);
  nav.push(MaterialPageRoute(builder: (_) => _screenFor(d, user)));
}

/// Icônes de la barre du haut ; celle de [current] (l'écran affiché) est
/// désactivée.
List<Widget> appNavActions(BuildContext context, AppUser user, {AppDestination? current}) {
  VoidCallback? go(AppDestination d) => d == current ? null : () => goTo(context, d, user);
  const adminItems = [
    (AppDestination.users, 'Comptes'),
    (AppDestination.aircraft, 'Appareils'),
    (AppDestination.pricing, 'Tarifs'),
    (AppDestination.billing, 'Relevé des vols facturés'),
  ];
  return [
    IconButton(
      tooltip: 'Carnet de vol',
      icon: const Icon(Icons.menu_book),
      onPressed: go(AppDestination.logbook),
    ),
    IconButton(
      tooltip: 'Mon compte',
      icon: const Icon(Icons.account_balance_wallet),
      onPressed: go(AppDestination.account),
    ),
    if (user.isInstructor || user.isAdmin)
      IconButton(
        tooltip: 'Instructeurs',
        icon: const Icon(Icons.groups),
        onPressed: go(AppDestination.instructors),
      ),
    if (user.isAdmin)
      PopupMenuButton<AppDestination>(
        tooltip: 'Administration',
        icon: const Icon(Icons.admin_panel_settings),
        onSelected: (d) => goTo(context, d, user),
        itemBuilder: (_) => [
          for (final (d, label) in adminItems)
            PopupMenuItem(value: d, enabled: d != current, child: Text(label)),
        ],
      ),
  ];
}
