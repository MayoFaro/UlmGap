import 'package:flutter/material.dart';

import '../../data/services.dart';
import 'sign_out.dart';

class NoAccessScreen extends StatelessWidget {
  const NoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 48),
              const SizedBox(height: 12),
              const Text('Ce compte n\'a pas accès à UlmGap. Contactez un administrateur.',
                  textAlign: TextAlign.center),
              TextButton(
                onPressed: () => signOutCleanly(AppServices.of(context)),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
