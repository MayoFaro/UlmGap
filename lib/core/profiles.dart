// Profils pilote et appartenances. SEUL endroit où vivent libellés, couleurs et
// icônes : les renommer ne touche pas aux données (seuls les codes sont stockés).
import 'package:flutter/material.dart';

enum PilotProfile {
  instructeur('instructeur', 'Instructeur', Color(0xFF7B1FA2), Icons.workspace_premium),
  lacheToutesMissions(
      'lache_toute_mission', 'Lâché toute mission', Color(0xFF2E7D32), Icons.flight),
  lacheSolo('lache_solo', 'Lâché solo', Color(0xFF1565C0), Icons.flight_takeoff),
  eleve('eleve', 'Élève', Color(0xFFEF6C00), Icons.school);

  const PilotProfile(this.code, this.label, this.color, this.icon);

  final String code;
  final String label;
  final Color color;
  final IconData icon;

  static PilotProfile? fromCode(String? code) {
    for (final p in values) {
      if (p.code == code) return p;
    }
    return null;
  }
}

enum UserCategory {
  gap('GAP'),
  gr('GR'),
  mil('MIL'),
  ext('EXT');

  const UserCategory(this.code);

  final String code;

  /// Code inconnu → EXT (forfait le plus élevé : choix sûr).
  static UserCategory fromCode(String? code) =>
      values.firstWhere((c) => c.code == code, orElse: () => UserCategory.ext);
}
