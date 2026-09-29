import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/profile_badge.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';

/// Carte compacte d'un vol pour une colonne du planning (une colonne par
/// appareil). L'appareil n'y est pas répété : il est porté par l'en-tête de
/// colonne.
class FlightCard extends StatelessWidget {
  const FlightCard({
    super.key,
    required this.flight,
    required this.dir,
    required this.now,
    this.mine = false,
    this.onTap,
  });

  final Flight flight;
  final Map<String, CrewMember> dir;
  final DateTime now;

  /// Vrai quand l'utilisateur courant fait partie de l'équipage du vol.
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = flight;
    final status = f.effectiveStatus(now);
    final color = statusColor(status);
    // Refusé (ou demande expirée) : grisé et jamais surligné, pour ne pas le
    // confondre avec un vol validé de l'utilisateur.
    final refused = status == FlightStatus.refuse;
    final content = Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatRange(f.start, f.end),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(crewText(f.crew, f.passengers, dir)),
              for (final u in f.crew)
                ProfileBadge(profile: dir[u]?.profile, compact: true),
            ],
          ),
          Text('→ ${f.destination}', overflow: TextOverflow.ellipsis),
          Text(
            statusLabel(status),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: refused
          ? BoxDecoration(
              color: refusedFill,
              border: Border.all(color: refusedBorder),
              borderRadius: BorderRadius.circular(8),
            )
          : mine
          ? BoxDecoration(
              color: highlightFill,
              border: Border.all(color: highlightBorder, width: 2),
              borderRadius: BorderRadius.circular(8),
            )
          : BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: refused ? Opacity(opacity: 0.6, child: content) : content,
        ),
      ),
    );
  }
}
