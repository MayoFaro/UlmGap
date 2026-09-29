import 'package:flutter/widgets.dart';

import 'admin_api.dart';
import 'auth_service.dart';
import 'finance_api.dart';
import 'flight_api.dart';
import 'user_repository.dart';

/// Services de l'app, injectés à la racine (doublures en test).
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.auth,
    required this.users,
    this.admin,
    this.flights,
    this.finance,
    required super.child,
  });

  final AuthService auth;
  final UserRepository users;
  final AdminApi? admin;
  final FlightApi? flights;
  final FinanceApi? finance;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppServices>()!;

  @override
  bool updateShouldNotify(AppServices old) =>
      auth != old.auth ||
      users != old.users ||
      admin != old.admin ||
      flights != old.flights ||
      finance != old.finance;
}
