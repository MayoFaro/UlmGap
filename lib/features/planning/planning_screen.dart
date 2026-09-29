import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/async_state.dart';
import '../../core/formats.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';
import '../../data/services.dart';
import 'flight_card.dart';
import 'flight_tile.dart';

/// Accueil : vols à partir d'aujourd'hui, groupés par jour (corps de HomeShell).
class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key, required this.me, this.now = DateTime.now, this.onOpen});

  final AppUser me;
  final DateTime Function() now;

  /// Ouverture d'un vol (branchée par HomeShell vers le détail, Task 10).
  final void Function(Flight flight)? onOpen;

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

/// Largeur minimale d'une colonne pour qu'elle reste lisible sans défilement.
const double minFitColumnWidth = 220.0;

/// Une colonne du planning : un appareil, avec l'en-tête à afficher.
class _AircraftColumn {
  const _AircraftColumn(this.aircraftId, this.header);
  final String aircraftId;
  final String header;
}

/// Appareils actifs triés par libellé, puis tout aircraftId présent dans les
/// vols et absent de cette liste (en-tête = immatriculation du vol).
List<_AircraftColumn> _columnsFor(List<Aircraft> aircraft, List<Flight> flights) {
  final active = aircraft.where((a) => a.active).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  final knownIds = active.map((a) => a.id).toSet();
  final columns = [
    for (final a in active) _AircraftColumn(a.id, '${a.label} (${a.registration})'),
  ];
  final extraSeen = <String>{};
  for (final f in flights) {
    if (!knownIds.contains(f.aircraftId) && extraSeen.add(f.aircraftId)) {
      columns.add(_AircraftColumn(f.aircraftId, f.aircraft));
    }
  }
  return columns;
}

/// Hauteur fixe de la rangée d'en-têtes d'appareils épinglée en haut de la
/// grille (voir [_AircraftHeaderDelegate]).
const double _headerHeight = 40;

/// En-tête d'appareils épinglé : reste visible en haut du CustomScrollView
/// pendant le défilement vertical (SliverPersistentHeader). Hauteur fixe et
/// fond opaque (couleur de fond de la page) pour que les cartes ne
/// transparaissent pas dessous.
class _AircraftHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _AircraftHeaderDelegate({required this.background, required this.child});

  final Color background;
  final Widget child;

  @override
  double get minExtent => _headerHeight;

  @override
  double get maxExtent => _headerHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        height: _headerHeight,
        color: background,
        child: child,
      );

  @override
  bool shouldRebuild(covariant _AircraftHeaderDelegate oldDelegate) =>
      background != oldDelegate.background || child != oldDelegate.child;
}

class _PlanningScreenState extends State<PlanningScreen> {
  FlightApi? _api;
  Stream<List<Flight>>? _flights;
  Stream<List<CrewMember>>? _dir;
  Stream<List<Aircraft>>? _aircraft;

  // Fix planning (retours de recette) : l'en-tête d'appareils est affiché une
  // seule fois, épinglé en haut de la grille (SliverPersistentHeader), et non
  // plus répété sous chaque titre de jour. La rangée d'en-têtes et chaque
  // rangée de jour ont chacune leur propre défilement horizontal (pour
  // partager le même SingleChildScrollView il faudrait une seule rangée par
  // écran, ce qui empêcherait le titre de chaque jour de rester hors du
  // défilement horizontal) ; tous ces ScrollController sont donc synchronisés
  // entre eux, en-tête compris, pour que les colonnes restent alignées.
  final ScrollController _headerScrollController = ScrollController();
  final Map<DateTime, ScrollController> _dayScrollControllers = {};
  final Set<ScrollController> _syncedControllers = {};
  bool _syncingScroll = false;

  ScrollController _registerSynced(ScrollController controller) {
    _syncedControllers.add(controller);
    controller.addListener(() => _syncScroll(controller));
    return controller;
  }

  void _syncScroll(ScrollController source) {
    if (_syncingScroll || !source.hasClients) return;
    _syncingScroll = true;
    for (final other in _syncedControllers) {
      if (other != source && other.hasClients && other.offset != source.offset) {
        other.jumpTo(source.offset);
      }
    }
    _syncingScroll = false;
  }

  ScrollController _dayScrollController(DateTime day) =>
      _dayScrollControllers.putIfAbsent(day, () => _registerSynced(ScrollController()));

  /// Supprime les contrôleurs des jours qui ne sont plus affichés (sinon ils
  /// fuiraient d'un rendu à l'autre, ex. après un changement de plage de
  /// vols). La suppression de la liste a lieu immédiatement (pour ne pas
  /// recréer/reconnecter un contrôleur déjà obsolète pendant ce même build),
  /// mais le dispose() effectif est reporté après la frame en cours : on ne
  /// dispose jamais un ScrollController pendant un build.
  void _pruneDayScrollControllers(Iterable<DateTime> currentDays) {
    final keep = currentDays.toSet();
    final removed = <ScrollController>[];
    for (final day in _dayScrollControllers.keys.toList()) {
      if (!keep.contains(day)) {
        final controller = _dayScrollControllers.remove(day);
        if (controller != null) {
          _syncedControllers.remove(controller);
          removed.add(controller);
        }
      }
    }
    if (removed.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in removed) {
        controller.dispose();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _registerSynced(_headerScrollController);
  }

  @override
  void dispose() {
    for (final c in _dayScrollControllers.values) {
      c.dispose();
    }
    _headerScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = AppServices.of(context).flights!;
    if (!identical(_api, api)) {
      _api = api;
      _flights = api.watchFrom(dayOf(widget.now()));
      _dir = api.watchDirectory();
      _aircraft = api.watchAircraft();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CrewMember>>(
      stream: _dir,
      builder: (context, dirSnap) {
        final dir = {for (final m in dirSnap.data ?? const <CrewMember>[]) m.uid: m};
        return StreamBuilder<List<Aircraft>>(
          stream: _aircraft,
          builder: (context, acSnap) => StreamBuilder<List<Flight>>(
            stream: _flights,
            builder: (context, snap) =>
                _body(snap, dir, acSnap.data ?? const <Aircraft>[]),
          ),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<List<Flight>> snap, Map<String, CrewMember> dir,
      List<Aircraft> aircraft) {
    final now = widget.now();
    final me = widget.me;
    final flights = (snap.data ?? const <Flight>[]).where((f) => !f.deleted).toList();
    final state = asyncState(snap, isEmpty: flights.isEmpty, empty: 'Aucun vol à venir.');

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        );

    if (state != null) {
      return CustomScrollView(
        slivers: [SliverFillRemaining(hasScrollBody: false, child: state)],
      );
    }

    final toValidate = flights
        .where((f) =>
            f.status == FlightStatus.demande &&
            !f.isExpiredRequest(now) &&
            f.instructorUid == me.uid)
        .toList();
    final mineList = flights
        .where((f) => f.createdBy == me.uid && f.effectiveStatus(now) != FlightStatus.valide)
        .toList();

    Widget tile(Flight f) => FlightTile(
          flight: f,
          dir: dir,
          now: now,
          mine: f.crew.contains(me.uid),
          onTap: () => widget.onOpen?.call(f),
        );

    final columns = _columnsFor(aircraft, flights);
    final byDay = <DateTime, List<Flight>>{};
    for (final f in flights) {
      byDay.putIfAbsent(dayOf(f.start), () => []).add(f);
    }
    _pruneDayScrollControllers(byDay.keys);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final n = columns.length;
        // Sur un écran large, on répartit la largeur disponible entre toutes
        // les colonnes (sans défilement) tant que chacune reste lisible ;
        // sinon (mobile), on garde la règle historique avec défilement.
        final colWidth = n <= 1
            ? w
            : (w - 8) / n >= minFitColumnWidth
                ? (w - 8) / n
                : math.max((w - 8) / 2, 160.0);
        final gridWidth = columns.length <= 1
            ? w
            : colWidth * columns.length + 8.0 * (columns.length - 1);

        Widget rowOf(List<Widget> cells) {
          final children = <Widget>[];
          for (var i = 0; i < cells.length; i++) {
            if (i > 0) children.add(const SizedBox(width: 8));
            children.add(cells[i]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
        }

        Widget headCell(_AircraftColumn col) => SizedBox(
              key: Key('head-${col.aircraftId}'),
              width: colWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    col.header,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );

        Widget dayCell(_AircraftColumn col, List<Flight>? dayFlights) {
          final dayList = (dayFlights ?? const <Flight>[])
              .where((f) => f.aircraftId == col.aircraftId)
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
          final content = dayList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('—', style: TextStyle(color: Colors.grey)),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in dayList)
                        FlightCard(
                          flight: f,
                          dir: dir,
                          now: now,
                          mine: f.crew.contains(me.uid),
                          onTap: () => widget.onOpen?.call(f),
                        ),
                    ],
                  ),
                );
          return SizedBox(
            key: Key('col-${col.aircraftId}'),
            width: colWidth,
            child: content,
          );
        }

        final background = Theme.of(context).scaffoldBackgroundColor;

        return CustomScrollView(
          slivers: [
            if (toValidate.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('À valider')),
              SliverList(delegate: SliverChildListDelegate(toValidate.map(tile).toList())),
            ],
            if (mineList.isNotEmpty) ...[
              SliverToBoxAdapter(child: header('Mes demandes')),
              SliverList(delegate: SliverChildListDelegate(mineList.map(tile).toList())),
            ],
            if (columns.isNotEmpty) ...[
              // En-tête d'appareils : une seule rangée, épinglée, alignée
              // (même largeurs de colonnes) avec chaque rangée de jour.
              SliverPersistentHeader(
                pinned: true,
                delegate: _AircraftHeaderDelegate(
                  background: background,
                  child: SingleChildScrollView(
                    controller: _headerScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: gridWidth,
                      child: rowOf([for (final c in columns) headCell(c)]),
                    ),
                  ),
                ),
              ),
              // Le titre de chaque jour est hors défilement horizontal
              // (pleine largeur, toujours visible) ; en dessous, une rangée
              // de cartes par appareil, sans en-tête répété.
              for (final day in byDay.keys) ...[
                SliverToBoxAdapter(child: header(formatDay(day))),
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    controller: _dayScrollController(day),
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: gridWidth,
                      child: rowOf([for (final c in columns) dayCell(c, byDay[day])]),
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}
