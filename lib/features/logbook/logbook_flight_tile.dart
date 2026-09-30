import 'package:flutter/material.dart';

import '../../core/formats.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../flight/flight_texts.dart';
import 'logbook.dart';

/// Une ligne du carnet de vol ; surlignée en orange quand le
/// vol est à clôturer.
class LogbookFlightTile extends StatelessWidget {
  const LogbookFlightTile({
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
    final toClose = needsClosing(f, now);
    final color = toClose
        ? toCloseColor
        : f.isClosed
            ? statusColor(FlightStatus.valide)
            : Colors.grey;
    final tile = ListTile(
      key: Key('logbook-${f.id}'),
      onTap: onTap,
      title: Text('${formatDay(f.start)} · ${formatRange(f.start, f.end)}'),
      subtitle: Text('${f.aircraft} · ${crewText(f.crew, f.passengers, dir)} → ${f.destination}'),
      trailing: Text(
        performedLabel(f, now),
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
    if (!toClose) return tile;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: toCloseFill,
        border: Border.all(color: toCloseColor, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: tile,
    );
  }
}
