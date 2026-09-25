import 'package:flutter/material.dart';

import 'profiles.dart';

/// Badge visuel du profil pilote, affiché à côté du nom.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({super.key, required this.profile, this.compact = false});

  final PilotProfile? profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const SizedBox.shrink();
    if (compact) {
      return Tooltip(
        message: p.label,
        child: CircleAvatar(
          radius: 11,
          backgroundColor: p.color.withValues(alpha: 0.15),
          child: Icon(p.icon, size: 14, color: p.color),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.color.withValues(alpha: 0.12),
        border: Border.all(color: p.color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(p.icon, size: 14, color: p.color),
          const SizedBox(width: 4),
          Text(p.label, style: TextStyle(color: p.color, fontSize: 12)),
        ],
      ),
    );
  }
}
