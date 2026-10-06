import 'package:flutter/material.dart';

import '../../core/profile_badge.dart';
import '../../core/profiles.dart';
import '../../data/app_user.dart';
import 'validators.dart';

/// Renvoie le payload à envoyer (création : avec email ; modification : sans).
/// Rendu par la fenêtre quand l'admin demande la suppression du compte.
const userDeleteRequest = <String, dynamic>{'delete': true};

Future<Map<String, dynamic>?> showUserFormDialog(BuildContext context, {AppUser? user}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserFormDialog(user: user),
    );

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});
  final AppUser? user;
  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.user?.email ?? '');
  late final _name = TextEditingController(text: widget.user?.displayName ?? '');
  late final _short = TextEditingController(text: widget.user?.shortName ?? '');
  late PilotProfile? _profile = widget.user == null ? PilotProfile.eleve : widget.user!.profile;
  late UserCategory _category = widget.user?.category ?? UserCategory.ext;
  late bool _isAdmin = widget.user?.isAdmin ?? false;
  late bool _active = widget.user?.active ?? true;
  late bool _amphibiousCleared = widget.user?.amphibiousCleared ?? false;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(<String, dynamic>{
      if (_isNew) 'email': _email.text.trim().toLowerCase(),
      'displayName': _name.text.trim(),
      'shortName': _short.text.trim().toUpperCase(),
      'profile': _profile?.code,
      'category': _category.code,
      'isAdmin': _isAdmin,
      'active': _active,
      'amphibiousCleared': _amphibiousCleared,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Nouveau compte' : 'Modifier le compte'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('f-email'),
                controller: _email,
                enabled: _isNew,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (v) => validateEmail(v ?? ''),
              ),
              TextFormField(
                key: const Key('f-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (v) => validateRequired(v ?? '', 'Nom'),
              ),
              TextFormField(
                key: const Key('f-short'),
                controller: _short,
                decoration: const InputDecoration(labelText: 'Code court (trigramme)'),
                validator: (v) => validateShortName(v ?? ''),
              ),
              DropdownButtonFormField<PilotProfile?>(
                value: _profile,
                decoration: const InputDecoration(labelText: 'Profil'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Non pilote')),
                  for (final p in PilotProfile.values)
                    DropdownMenuItem(
                      value: p,
                      child: Row(children: [
                        ProfileBadge(profile: p, compact: true),
                        const SizedBox(width: 8),
                        Text(p.label),
                      ]),
                    ),
                ],
                onChanged: (v) => setState(() => _profile = v),
              ),
              DropdownButtonFormField<UserCategory>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Appartenance'),
                items: [
                  for (final c in UserCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.code)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              SwitchListTile(
                key: const Key('user-amphibious'),
                title: const Text('Lâché amphibie'),
                value: _amphibiousCleared,
                onChanged: (v) => setState(() => _amphibiousCleared = v),
              ),
              SwitchListTile(
                title: const Text('Administrateur'),
                value: _isAdmin,
                onChanged: (v) => setState(() => _isAdmin = v),
              ),
              SwitchListTile(
                title: const Text('Compte actif'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(userDeleteRequest),
            child: const Text('Supprimer le compte'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
