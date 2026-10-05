// Carnet de vol (spec §5, révision du 2026-09-30) : tous les vols effectués,
// tous appareils confondus, avec le temps de vol total de la période en
// haut (vols clôturés). Seul accès aux vols passés, donc à la clôture
// (l'action « Clôturer » est dans FlightScreen).
import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/finance_api.dart';
import '../../data/flight.dart';
import '../../data/services.dart';
import '../flight/flight_screen.dart';
import '../flight/flight_texts.dart';
import 'logbook.dart';
import 'logbook_flight_tile.dart';
import '../home/app_nav.dart';

/// Choix d'une période précise : début et fin, bornes incluses.
typedef RangePicker = Future<DateTimeRange?> Function(
    BuildContext context, DateTimeRange? initial);

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({
    super.key,
    required this.me,
    this.now = DateTime.now,
    this.onOpen,
    this.pickRange,
  });

  final AppUser me;
  final DateTime Function() now;

  /// Ouverture d'un vol ; par défaut, FlightScreen.
  final void Function(Flight flight)? onOpen;

  /// Calendrier de période précise ; par défaut, showDateRangePicker.
  final RangePicker? pickRange;

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

/// Filtre de clôture de la liste de la période (le total n'en dépend pas).
enum _ClosedFilter { all, closed, open }

class _LogbookScreenState extends State<LogbookScreen> {
  late int _year;
  late int _month; // 1 à 12, ou 0 pour l'année entière
  DateTimeRange? _custom; // période précise, bornes incluses
  String? _pilotUid; // null : tous les pilotes (instructeurs et admins)
  String? _aircraftId; // null : tous les appareils
  bool _onlyToClose = false;
  _ClosedFilter _closedFilter = _ClosedFilter.all;

  FinanceApi? _finance;
  Stream<List<Flight>>? _periodFlights;
  Stream<List<Flight>>? _unclosed;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  bool get _canChoosePilot => widget.me.isAdmin || widget.me.isInstructor;

  /// Bornes [from, to[ de la période affichée.
  ({DateTime from, DateTime to}) get _period {
    final c = _custom;
    if (c == null) return monthPeriod(_year, _month);
    return (
      from: dayOf(c.start),
      to: DateTime(c.end.year, c.end.month, c.end.day + 1),
    );
  }

  @override
  void initState() {
    super.initState();
    final n = widget.now();
    _year = n.year;
    _month = n.month;
    _pilotUid = widget.me.uid;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    final finance = services.finance!;
    if (!identical(_finance, finance)) {
      _finance = finance;
      _periodFlights = _watchPeriod();
      _unclosed = finance.watchValidUnclosedFlights();
      _dir = services.flights!.watchDirectory();
      _aircraft = services.flights!.watchAircraft();
    }
  }

  Stream<List<Flight>> _watchPeriod() {
    final p = _period;
    return _finance!.watchFlightsBetween(p.from, p.to);
  }

  /// Change la période ; quitte l'affichage « à clôturer ».
  void _setPeriod({int? year, int? month, DateTimeRange? custom}) => setState(() {
        if (year != null) _year = year;
        if (month != null) _month = month;
        _custom = custom;
        _onlyToClose = false;
        _periodFlights = _watchPeriod();
      });

  Future<void> _pickCustom() async {
    final today = dayOf(widget.now());
    final p = _period;
    final lastIncluded = DateTime(p.to.year, p.to.month, p.to.day - 1);
    final initial = p.from.isAfter(today)
        ? null
        : DateTimeRange(start: p.from, end: lastIncluded.isAfter(today) ? today : lastIncluded);
    final pick = widget.pickRange ??
        (context, initial) => showDateRangePicker(
              context: context,
              firstDate: DateTime(firstLogbookYear),
              lastDate: today,
              initialDateRange: initial,
            );
    final r = await pick(context, initial);
    if (r != null && mounted) _setPeriod(custom: r);
  }

  void _open(Flight f) {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen(f);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlightScreen(me: widget.me, flight: f),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Carnet de vol'),
          actions: appNavActions(context, widget.me, current: AppDestination.logbook),
        ),
        body: StreamBuilder<List<CrewMember>>(
          stream: _dir,
          builder: (context, dirSnap) {
            final dir = dirSnap.data ?? const <CrewMember>[];
            return StreamBuilder<List<Aircraft>>(
              stream: _aircraft,
              builder: (context, acSnap) => StreamBuilder<List<Flight>>(
                stream: _unclosed,
                builder: (context, unclosedSnap) => StreamBuilder<List<Flight>>(
                  stream: _periodFlights,
                  builder: (context, periodSnap) => _body(
                      dir, acSnap.data ?? const <Aircraft>[], unclosedSnap, periodSnap),
                ),
              ),
            );
          },
        ),
      );

  Widget _periodSelectors() {
    final c = _custom;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<int>(
          key: const Key('month-select'),
          value: c == null ? _month : null,
          hint: const Text('Mois'),
          onChanged: (m) => _setPeriod(month: m),
          items: [
            for (var m = 1; m <= 12; m++)
              DropdownMenuItem(value: m, child: Text(formatMonth(m))),
            const DropdownMenuItem(value: 0, child: Text('Année')),
          ],
        ),
        DropdownButton<int>(
          key: const Key('year-select'),
          value: _year,
          onChanged: (y) => _setPeriod(year: y),
          items: [
            for (final y in logbookYears(widget.now()))
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
        ),
        OutlinedButton.icon(
          key: const Key('custom-period'),
          icon: const Icon(Icons.date_range),
          label: Text(c == null
              ? 'Période précise'
              : 'Du ${formatShortDate(c.start)} au ${formatShortDate(c.end)}'),
          onPressed: _pickCustom,
        ),
      ],
    );
  }

  Widget _pilotFilter(List<CrewMember> dir) {
    final me = widget.me;
    // Annuaire pas encore chargé (ou sans ce compte) : une entrée de repli
    // pour le compte connecté, plutôt qu'une assertion de DropdownButton.
    final missingMe = _pilotUid == me.uid && !dir.any((m) => m.uid == me.uid);
    return DropdownButton<String?>(
      key: const Key('pilot-filter'),
      value: _pilotUid,
      onChanged: (v) => setState(() => _pilotUid = v),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Tous les pilotes')),
        if (missingMe) DropdownMenuItem<String?>(value: me.uid, child: Text(me.shortName)),
        for (final m in dir)
          DropdownMenuItem<String?>(value: m.uid, child: Text('${m.shortName} · ${m.displayName}')),
      ],
    );
  }

  /// « Atterrissages : 3 », complété des amerrissages s'il y en a (plan 4b).
  String _landingsLine(({int landings, int waterLandings}) t) => t.waterLandings > 0
      ? 'Atterrissages : ${t.landings} · Amerrissages : ${t.waterLandings}'
      : 'Atterrissages : ${t.landings}';

  /// Tous les appareils, inactifs compris (historique) ; appareil disparu
  /// de la liste : retour à « Tous les appareils ».
  Widget _aircraftFilter(List<Aircraft> aircraft) => DropdownButton<String?>(
        key: const Key('aircraft-filter'),
        value: aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : null,
        onChanged: (v) => setState(() => _aircraftId = v),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Tous les appareils')),
          for (final a in aircraft)
            DropdownMenuItem<String?>(value: a.id, child: Text('${a.label} (${a.registration})')),
        ],
      );

  Widget _body(List<CrewMember> dir, List<Aircraft> aircraft,
      AsyncSnapshot<List<Flight>> unclosedSnap, AsyncSnapshot<List<Flight>> periodSnap) {
    final now = widget.now();
    final me = widget.me;
    final pilotUid = _canChoosePilot ? _pilotUid : me.uid;
    final aircraftId = aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : null;
    final periodList = logbookList(periodSnap.data ?? const <Flight>[],
        me: me, now: now, pilotUid: pilotUid, aircraftId: aircraftId);
    final toClose = logbookList(unclosedSnap.data ?? const <Flight>[],
            me: me, now: now, pilotUid: pilotUid, aircraftId: aircraftId)
        .where((f) => needsClosing(f, now))
        .toList();
    // Plus aucun vol à clôturer (le dernier vient de l'être) : l'affichage
    // « à clôturer » s'arrête et la liste revient à la période.
    final onlyToClose = _onlyToClose && toClose.isNotEmpty;
    final filtered = switch (_closedFilter) {
      _ClosedFilter.all => periodList,
      _ClosedFilter.closed => periodList.where((f) => f.isClosed).toList(),
      _ClosedFilter.open => periodList.where((f) => !f.isClosed).toList(),
    };
    final shown = onlyToClose ? toClose : filtered;
    final state = asyncState(
      onlyToClose ? unclosedSnap : periodSnap,
      isEmpty: shown.isEmpty,
      empty: onlyToClose
          ? 'Aucun vol à clôturer.'
          : switch (_closedFilter) {
              _ClosedFilter.all => 'Aucun vol sur cette période.',
              _ClosedFilter.closed => 'Aucun vol clôturé sur cette période.',
              _ClosedFilter.open => 'Aucun vol non clôturé sur cette période.',
            },
    );
    final dirMap = {for (final m in dir) m.uid: m};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _periodSelectors(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 12, children: [
            if (_canChoosePilot) _pilotFilter(dir),
            _aircraftFilter(aircraft),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<_ClosedFilter>(
            key: const Key('closed-filter'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _ClosedFilter.all, label: Text('Tous')),
              ButtonSegment(value: _ClosedFilter.closed, label: Text('Clôturés')),
              ButtonSegment(value: _ClosedFilter.open, label: Text('Non clôturés')),
            ],
            // Pendant l'affichage « à clôturer », aucun segment n'est actif.
            selected: onlyToClose ? const {} : {_closedFilter},
            emptySelectionAllowed: true,
            onSelectionChanged: (sel) => setState(() {
              if (sel.isNotEmpty) _closedFilter = sel.first;
              _onlyToClose = false;
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Temps de vol : ${formatDurationHm(totalMinutes(periodList))}',
            key: const Key('logbook-total'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(_landingsLine(totalLandings(periodList)), key: const Key('logbook-landings')),
        ),
        if (toClose.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const Key('to-close-count'),
                label: Text(toCloseCountText(toClose.length),
                    style: TextStyle(color: toCloseColor, fontWeight: FontWeight.bold)),
                side: BorderSide(color: toCloseColor),
                selected: onlyToClose,
                onSelected: (v) => setState(() => _onlyToClose = v),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: state ??
              ListView(children: [
                for (final f in shown)
                  LogbookFlightTile(flight: f, dir: dirMap, now: now, onTap: () => _open(f)),
              ]),
        ),
      ],
    );
  }
}
