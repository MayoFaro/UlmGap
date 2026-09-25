import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/env.dart';

/// Couleur de marque UlmGap (orange ULM).
const Color kBrandColor = Color(0xFFEF6C00);

class UlmGapApp extends StatelessWidget {
  const UlmGapApp({super.key, required this.env, required this.home});

  final AppEnv env;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UlmGap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: kBrandColor, useMaterial3: true),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => env == AppEnv.dev
          ? Banner(
              message: 'DEV',
              location: BannerLocation.topEnd,
              child: child ?? const SizedBox.shrink(),
            )
          : child ?? const SizedBox.shrink(),
      home: home,
    );
  }
}
