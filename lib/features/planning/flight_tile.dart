import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../core/profile_badge.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';

class FlightTile extends StatelessWidget {
  const FlightTile({
    super.key,
    required this.flight,
    required this.dir,
    required this.now,
    this.onTap,
  });

  final Flight flight;
  final Map<String, CrewMember> dir;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = flight;
    final status = f.effectiveStatus(now);
    final color = statusColor(status);
    return ListTile(
      onTap: onTap,
      leading: Icon(Icons.circle, size: 14, color: color),
      title: Text('${formatRange(f.start, f.end)} · ${f.aircraft}'),
      subtitle: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(crewText(f.crew, f.passengers, dir)),
          for (final u in f.crew) ProfileBadge(profile: dir[u]?.profile, compact: true),
          Text('→ ${f.destination}'),
        ],
      ),
      trailing: Chip(
        label: Text(statusLabel(status), style: TextStyle(color: color)),
        side: BorderSide(color: color),
      ),
    );
  }
}
