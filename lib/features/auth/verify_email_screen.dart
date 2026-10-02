import 'package:flutter/material.dart';

import '../../data/services.dart';
import 'sign_out.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key, required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_unread, size: 48),
              const SizedBox(height: 12),
              Text('Vérifiez votre adresse e-mail ($email) pour accéder à UlmGap.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: auth.reload,
                child: const Text('J\'ai vérifié mon e-mail'),
              ),
              TextButton(
                onPressed: () async {
                  await auth.sendEmailVerification();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('E-mail de vérification envoyé.')));
                  }
                },
                child: const Text('Renvoyer le lien'),
              ),
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
