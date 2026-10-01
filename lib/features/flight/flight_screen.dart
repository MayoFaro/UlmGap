import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/flight_rules.dart';
import '../../core/formats.dart';
import '../../core/money.dart';
import '../../core/pricing.dart';
import '../../core/profile_badge.dart';
import '../../core/profiles.dart';
import '../../data/aircraft.dart';
import '../../data/app_user.dart';
import '../../data/crew_member.dart';
import '../../data/finance_api.dart';
import '../../data/flight.dart';
import '../../data/flight_api.dart';
import '../../data/services.dart';
import 'closing_dialog.dart';
import 'flight_actions.dart';
import 'flight_texts.dart';
import '../home/app_nav.dart';

/// Fenêtre unique d'un vol : consultation, création, édition, validation,
/// refus et annulation (spec plan 2b, Task 3). Les droits sont calculés par
/// [flightActions] à partir de [flight] ; `flight == null` signifie création.
class FlightScreen extends StatefulWidget {
  const FlightScreen({
    super.key,
    required this.me,
    this.flight,
    this.now = DateTime.now,
  });

  final AppUser me;
  final Flight? flight;
  final DateTime Function() now;

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

enum _Mode { create, edit, validate, view }

class _FlightScreenState extends State<FlightScreen> {
  late DateTime _start;
  late DateTime _end;
  String? _aircraftId;
  late List<String> _crew;
  String? _passenger;
  final _destination = TextEditingController();
  final _destinationFocus = FocusNode();
  bool _fuelOnly = false;
  bool _saving = false;

  // --- Task 10 (finances) : correction admin d'un vol clôturé ---
  bool _correcting = false;
  final _correctMinutes = TextEditingController();
  final _correctShortAmount = TextEditingController();
  final _correctCustomAmount = TextEditingController();
  bool _correctCustomChecked = false;
  // Plan 4b : nombres saisis à la clôture, corrigeables par un admin.
  final _correctLandings = TextEditingController();
  final _correctWaterLandings = TextEditingController();

  final _subs = <StreamSubscription<Object?>>[];
  /// Version « live » d'un vol existant (Task 3, retours de recette) : mise à
  /// jour par [FlightApi.watchFlight] pendant la consultation, pour refléter
  /// une validation/un refus/une annulation faits ailleurs. Les champs
  /// modifiables (_start, _crew, ...) restent sur la saisie en cours : seuls
  /// le statut, l'en-tête et les boutons se recalculent à partir d'elle.
  Flight? _current;
  Map<String, CrewMember> _dir = {};
  List<Aircraft> _aircraft = [];

  /// Tous les appareils, inactifs compris (plan 4b : un amphibie désactivé
  /// garde ses amerrissages à la clôture et en correction).
  List<Aircraft> _allAircraft = [];
  Map<String, UserCategory> _categories = {};
  List<Flight> _flights = [];
  List<String> _destinations = [];
  bool _listening = false;

  // --- Task 9 (finances) : coût estimé, crédit disponible, clôture ---
  Pricing _pricing = defaultPricing;
  Map<String, AppUser> _accounts = {};
  /// null si l'écran n'a pas de FinanceApi (tests d'autres fonctionnalités
  /// qui n'en fournissent pas) : le bloc coût/crédit est alors entièrement
  /// masqué, sans quoi un solde par défaut à 0 bloquerait localement tout
  /// enregistrement.
  FinanceApi? _finance;

  /// Vols non clôturés du compte débité affiché (passés compris), écoutés
  /// pour [_payerFlightsUid] et réabonnés quand le compte débité change.
  List<Flight> _payerFlights = [];
  String? _payerFlightsUid;
  StreamSubscription<List<Flight>>? _payerFlightsSub;

  AppUser get _me => widget.me;

  Set<FlightAction> get _actions {
    final f = _current;
    return f == null ? const {} : flightActions(f, _me, widget.now());
  }

  _Mode get _mode {
    if (widget.flight == null) return _Mode.create;
    if (_actions.contains(FlightAction.validate)) return _Mode.validate;
    if (_actions.contains(FlightAction.edit)) return _Mode.edit;
    return _Mode.view;
  }

  bool get _validating => _mode == _Mode.validate;
  bool get _fieldsEditable => _mode != _Mode.view || _correcting;
  bool get _crewEditable => _mode == _Mode.create || _mode == _Mode.edit || _correcting;
  bool get _isStaff => _me.isAdmin || _me.isInstructor;
  bool get _mayChoose => _validating || _isStaff;

  @override
  void initState() {
    super.initState();
    final f = widget.flight;
    _current = f;
    if (f != null) {
      _start = f.start;
      _end = f.end;
      _aircraftId = f.aircraftId;
      _crew = [...f.crew];
      _passenger = f.passengers.isEmpty ? null : f.passengers.first;
      _destination.text = f.destination;
      _fuelOnly = f.pricingMode == 'fuel_only';
      // Task 10 : préremplissage des champs de clôture pour une correction
      // admin éventuelle (aperçu de régularisation calculé avant même que le
      // bouton « Corriger » ne soit pressé n'est pas nécessaire ici : ces
      // champs ne sont lus que si _correcting devient vrai).
      _correctMinutes.text = f.actualFlightMinutes?.toString() ?? '';
      _correctShortAmount.text =
          f.shortFlightAmount == null ? '' : formatAmountInput(f.shortFlightAmount!);
      _correctCustomAmount.text =
          f.customAmount == null ? '' : formatAmountInput(f.customAmount!);
      _correctCustomChecked = f.billedTo == 'off_app';
      // Vol clôturé avant le plan 4b (sans nombres) : 1 et 0.
      _correctLandings.text = '${f.landings ?? 1}';
      _correctWaterLandings.text = '${f.waterLandings ?? 0}';
    } else {
      final n = widget.now();
      _start = DateTime(n.year, n.month, n.day, n.hour + 1);
      _end = _start.add(const Duration(hours: 1));
      _crew = [_me.uid];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listening) return;
    _listening = true;
    final api = AppServices.of(context).flights!;
    void listen<T>(Stream<T> s, void Function(T) on) => _subs.add(s.listen(
          (v) {
            if (mounted) setState(() => on(v));
          },
          onError: (Object _) {}, // l'aperçu reste indicatif
        ));
    listen(api.watchDirectory(), (l) => _dir = {for (final m in l) m.uid: m});
    listen(api.watchAircraft(), (l) {
      _allAircraft = l;
      _aircraft = l.where((a) => a.active).toList();
      // Spec §6 : en création, l'appareil par défaut est le premier de la
      // liste dès qu'elle arrive.
      if (widget.flight == null && _aircraftId == null && _aircraft.isNotEmpty) {
        _aircraftId = _aircraft.first.id;
      }
    });
    listen(api.watchFrom(dayOf(widget.now())), (l) => _flights = l);
    // Task 3 (retours de recette) : un vol existant reste écouté pour refléter
    // en direct une validation/un refus/une annulation faits ailleurs.
    if (widget.flight != null) {
      listen(api.watchFlight(widget.flight!.id), (v) => _current = v);
    }
    if (_mayChoose) listen(api.watchCategories(), (m) => _categories = m);
    api.recentDestinations().then((d) {
      if (mounted) setState(() => _destinations = d);
    }, onError: (Object _) {});
    // Task 9 : tarifs courants et, pour un instructeur/admin, tous les
    // comptes (nécessaires pour lire le solde d'un compte débité autre que
    // le sien). Un élève non concerné ne lit que le sien (_me.balance).
    _finance = AppServices.of(context).finance;
    final finance = _finance;
    if (finance != null) {
      listen(finance.watchPricing(), (p) => _pricing = p);
      if (_isStaff) listen(finance.watchAccounts(), (l) => _accounts = {for (final u in l) u.uid: u});
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _payerFlightsSub?.cancel();
    _destination.dispose();
    _destinationFocus.dispose();
    _correctMinutes.dispose();
    _correctLandings.dispose();
    _correctWaterLandings.dispose();
    _correctShortAmount.dispose();
    _correctCustomAmount.dispose();
    super.dispose();
  }

  // --- calculs de l'aperçu (indicatifs : le serveur décide) ---

  String _short(String uid) => uid == _me.uid ? _me.shortName : (_dir[uid]?.shortName ?? '…');
  PilotProfile? _profile(String uid) => uid == _me.uid ? _me.profile : _dir[uid]?.profile;
  UserCategory? _category(String uid) => uid == _me.uid ? _me.category : _categories[uid];

  bool get _allGap => _crew.every((u) => _category(u) == UserCategory.gap);
  bool get _showFuelChoice => _mayChoose && _allGap && _passenger == null;

  Decision get _decision => _validating
      ? Decision.ok('valide', _current!.instructorUid)
      : decideStatus(
          creatorUid: _me.uid,
          creatorProfile: _me.profile?.code,
          creatorIsAdmin: _me.isAdmin,
          crew: [for (final u in _crew) RulePerson(u, _profile(u)?.code)],
          passengers: _passenger == null ? 0 : 1,
        );

  /// Aperçu du mode de tarification (Task 1, retours de recette). Miroir de
  /// resolvePricingMode côté serveur (functions/src/flights/edit.ts) :
  /// - le mode précédent n'est repris que si le vol ENREGISTRÉ (tel qu'ouvert,
  ///   pas une mise à jour live) n'avait pas de passager sans compte, sinon
  ///   un « carburant seulement » imposé par ce passager survivrait à son
  ///   retrait sans qu'aucun instructeur ne l'ait choisi ;
  /// - un non-instructeur n'écoute pas watchCategories (_mayChoose == false),
  ///   donc _categories est vide pour les autres membres : calculer allGap
  ///   sur un équipage avec d'autres personnes reviendrait à traiter leur
  ///   catégorie inconnue comme « non GAP » et ferait retomber le mode en
  ///   Standard sans décision d'instructeur. Si l'équipage et la présence
  ///   d'un passager n'ont pas changé depuis le vol enregistré, on réutilise
  ///   donc simplement son mode stocké ; sinon (la situation a changé : par
  ///   ex. le passager a été retiré), on retombe sur le calcul habituel, qui
  ///   reste correct tant que seule SA propre catégorie (toujours connue)
  ///   entre en jeu.
  String get _pricingMode {
    final stored = widget.flight;
    final storedHadNoPassenger = stored == null || stored.passengers.isEmpty;
    final previous = storedHadNoPassenger ? stored?.pricingMode : null;

    if (stored != null && !_mayChoose) {
      final sameCrew = _crew.length == stored.crew.length &&
          _crew.toSet().containsAll(stored.crew) &&
          stored.crew.toSet().containsAll(_crew);
      final samePassengerSituation = (_passenger != null) == stored.passengers.isNotEmpty;
      if (sameCrew && samePassengerSituation) return stored.pricingMode;
    }

    return resolvePricingMode(
      allGap: _allGap,
      hasPassenger: _passenger != null,
      mayChoose: _mayChoose,
      requested: _showFuelChoice ? (_fuelOnly ? 'fuel_only' : 'standard') : null,
      previous: previous,
    );
  }

  ({RuleFlight candidate, Flight other})? get _conflict {
    if (_aircraftId == null) return null;
    // Révision du 2026-10-01 : conflits en planification seulement (vol à
    // venir non clôturé), jamais en conduite.
    if (!isPlanning(
      start: _start.millisecondsSinceEpoch,
      now: widget.now().millisecondsSinceEpoch,
      closed: _current?.isClosed ?? false,
    )) {
      return null;
    }
    final candidate = RuleFlight(
      id: widget.flight?.id,
      start: _start.millisecondsSinceEpoch,
      end: _end.millisecondsSinceEpoch,
      aircraftId: _aircraftId!,
      crew: _crew,
    );
    final hit = findConflict(candidate, _flights.map((f) => f.toRule()));
    if (hit == null) return null;
    return (candidate: candidate, other: _flights.firstWhere((f) => f.id == hit.id));
  }

  String _statusText(Decision d) {
    if (!d.ok) return 'Impossible : ${d.reason}';
    if (d.status == 'demande') return 'Sera une demande à ${_short(d.instructorUid!)}';
    return switch (_mode) {
      _Mode.validate => 'Sera validé',
      _Mode.edit => 'Sera enregistré (validé)',
      _Mode.create || _Mode.view => _correcting ? 'Sera corrigé' : 'Sera créé (validé)',
    };
  }

  // --- Task 9 (finances) : coût estimé, crédit disponible ---

  /// Compte débité. Pour un vol existant non en cours d'édition (mode
  /// `view`), on lit le champ stocké (`payerUid`, absent avant le plan 3, cas
  /// où il peut différer de `crew.first` — cf. CLAUDE.md) ; sinon (création,
  /// édition, validation), c'est la première personne de l'équipage en
  /// cours de saisie.
  String get _debitedUid {
    final f = widget.flight;
    return (f != null && !_fieldsEditable) ? (f.payerUidField ?? f.crew.first) : _crew.first;
  }

  /// Tarifs à utiliser pour le coût du vol en cours (règle du contrôleur,
  /// miroir de planFlight côté serveur) : le `pricingSnapshot` figé s'il
  /// reste `valide`, sinon les tarifs courants.
  /// En consultation (y compris la clôture par un équipier dont la propre
  /// décision serait `demande`), un vol `valide` garde son snapshot figé.
  Pricing get _pricingForCost {
    final f = _current;
    if (f != null &&
        f.status == FlightStatus.valide &&
        (!_fieldsEditable || _decision.status == 'valide')) {
      return f.pricingSnapshot ?? _pricing;
    }
    return _pricing;
  }

  /// null si l'appartenance du compte débité n'est pas connue ici (élève ou
  /// lâché consultant le vol d'un autre compte : `watchCategories` n'est pas
  /// écouté hors validation/instructeur/admin, spec §3).
  int? get _estimatedCost {
    if (_finance == null) return null;
    final category = _category(_debitedUid);
    if (category == null) return null;
    return computedCost(_pricingMode, _end.difference(_start).inMinutes, category, _pricingForCost);
  }

  /// Abonne l'écran aux vols non clôturés du compte débité courant (appelé
  /// à chaque build : le compte débité suit la saisie de l'équipage).
  void _syncPayerFlights() {
    final finance = _finance;
    final uid = _debitedUid;
    if (finance == null || uid == _payerFlightsUid) return;
    _payerFlightsUid = uid;
    _payerFlights = [];
    _payerFlightsSub?.cancel();
    _payerFlightsSub = finance.watchUnclosedFlightsPaidBy(uid).listen(
      (l) {
        if (mounted && _payerFlightsUid == uid) setState(() => _payerFlights = l);
      },
      onError: (Object _) {}, // l'aperçu reste indicatif
    );
  }

  /// Coût estimé des autres vols `valide`, non clôturés, du même compte
  /// débité (spec §4.4), passés compris, comme le serveur.
  List<int> get _otherCosts {
    final category = _category(_debitedUid);
    if (category == null) return const [];
    return [
      for (final o in _payerFlights)
        if (o.id != widget.flight?.id &&
            o.status == FlightStatus.valide &&
            !o.isClosed &&
            !o.deleted &&
            (o.pricingMode == 'standard' || o.pricingMode == 'fuel_only'))
          estimatedCost(o.pricingMode, o.end.difference(o.start).inMinutes, category,
              o.pricingSnapshot ?? _pricing),
    ];
  }

  /// Spec §4.4/décision utilisateur 1 : le solde n'est lisible ici que pour
  /// son propre compte, ou par un instructeur/admin (watchAccounts).
  bool get _canSeeCredit => _debitedUid == _me.uid || _isStaff;

  int? get _debitedBalance =>
      _debitedUid == _me.uid ? _me.balance : _accounts[_debitedUid]?.balance;

  int? get _availableCredit {
    if (!_canSeeCredit) return null;
    final balance = _debitedBalance;
    if (balance == null) return null;
    return availableCredit(balance, _otherCosts);
  }

  /// Lignes « Coût estimé » / « Crédit disponible », affichées dans l'aperçu
  /// (saisie) ou en tête de fiche (consultation d'un vol non clôturé).
  List<Widget> _financeLines(BuildContext context) {
    final cost = _estimatedCost;
    if (cost == null) return const [];
    final widgets = <Widget>[Text('Coût estimé : ${formatFcfa(cost)}')];
    if (_canSeeCredit) {
      final credit = _availableCredit;
      if (credit != null) {
        final insufficient = credit < cost;
        final errorColor = Theme.of(context).colorScheme.error;
        widgets.add(Text(
          'Crédit disponible de ${_short(_debitedUid)} : ${formatFcfa(credit)}',
          style: insufficient ? TextStyle(color: errorColor) : null,
        ));
        if (insufficient) {
          widgets.add(Text(
            'Crédit insuffisant : il manque ${formatFcfa(cost - credit)}.',
            style: TextStyle(color: errorColor),
          ));
        }
      }
    }
    return widgets;
  }

  // --- Task 10 (finances) : correction admin, régularisation d'un vol clôturé ---

  int? get _correctActualMinutes => int.tryParse(_correctMinutes.text.trim());
  int? get _correctLandingsValue => int.tryParse(_correctLandings.text.trim());

  /// Champ masqué : le vol n'a pas d'amerrissages (0).
  int? get _correctWaterLandingsValue => _showCorrectWaterLandings
      ? int.tryParse(_correctWaterLandings.text.trim())
      : 0;

  /// Miroir de ClosingDialog._needsShortAmount, avec le mode de tarification
  /// et les tarifs du brouillon en cours de correction.
  bool get _correctNeedsShortAmount {
    final m = _correctActualMinutes;
    return _pricingMode == 'standard' && m != null && m < _pricingForCost.minPlannedMinutes;
  }

  /// Régularisation locale (indicative), miroir exact de
  /// `core/pricing.dart#adjustments` (lui-même miroir de
  /// functions/src/rules/pricing.ts) : l'ancienne facture rembourse
  /// intégralement l'ancien compte débité (`payerUidField ?? crew.first` du
  /// vol stocké, avant correction), et la nouvelle facture (calcul local de
  /// closingBill avec la saisie en cours) débite intégralement le nouveau
  /// (`_debitedUid`, `crew.first` en cours d'édition) — un mouvement par
  /// compte impacté, montants nuls omis.
  List<({String uid, int amount})>? get _regularisation {
    final f = _current;
    if (f == null || !f.isClosed) return null;
    final category = _category(_debitedUid);
    if (category == null) return null;
    final minutes = _correctActualMinutes;
    if (minutes == null) return null;
    final shortAmount = _correctNeedsShortAmount ? parseAmount(_correctShortAmount.text) : null;
    if (_correctNeedsShortAmount && shortAmount == null) return null;
    final customAmount = _correctCustomChecked ? parseAmount(_correctCustomAmount.text) : null;
    if (_correctCustomChecked && customAmount == null) return null;
    final ClosingBill bill;
    try {
      bill = closingBill(
        mode: _pricingMode,
        actualMinutes: minutes,
        category: category,
        pricing: _pricingForCost,
        shortFlightAmount: shortAmount,
        customAmount: customAmount,
        hasPassenger: _passenger != null,
      );
    } on ArgumentError {
      return null;
    }
    final oldPayer = f.payerUidField ?? f.crew.first;
    return adjustments(
      (billedTo: f.billedTo, payerUid: oldPayer, amount: f.billedAmount ?? 0),
      (billedTo: bill.billedTo, payerUid: _debitedUid, amount: bill.billedAmount),
    );
  }

  /// `+15 000 FCFA` (crédit/remboursement) ou `−15 000 FCFA` (débit) :
  /// formatFcfa gère déjà le signe négatif, seul le « + » manque ici.
  String _signedFcfa(int amount) => amount > 0 ? '+${formatFcfa(amount)}' : formatFcfa(amount);

  /// Lignes « Régularisation », une par compte impacté (ou « Aucune
  /// régularisation. » si la correction ne change rien), affichées dans
  /// l'aperçu pendant la correction d'un vol clôturé, à la place des lignes
  /// coût estimé/crédit disponible (sans objet une fois le vol réalisé).
  List<Widget> _regularisationLines() {
    if (_category(_debitedUid) == null) {
      return const [Text('Montant calculé par le serveur à la clôture.')];
    }
    final moves = _regularisation;
    if (moves == null) return const [];
    if (moves.isEmpty) return const [Text('Aucune régularisation.')];
    return [
      for (final m in moves)
        Text('Régularisation : ${_signedFcfa(m.amount)} sur le compte de ${_short(m.uid)}'),
    ];
  }

  List<Widget> _previewFinanceLines(BuildContext context) {
    final f = _current;
    if (_correcting && f != null && f.isClosed) return _regularisationLines();
    return _financeLines(context);
  }

  // --- saisie ---

  Future<void> _pickDate() async {
    // Un admin peut saisir un vol oublié (jusqu'à un an en arrière).
    final computedFirst = _me.isAdmin && widget.flight == null
        ? dayOf(widget.now()).subtract(const Duration(days: 365))
        : dayOf(widget.now());
    // En édition/validation, le vol existant peut déjà commencer avant cette
    // borne (ex. vol de la veille) : showDatePicker exige
    // !initialDate.isBefore(firstDate), donc on élargit la borne au besoin.
    final startDay = dayOf(_start);
    final firstDate = startDay.isBefore(computedFirst) ? startDay : computedFirst;
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: firstDate,
      lastDate: widget.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      final length = _end.difference(_start);
      _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
      _end = _start.add(length);
    });
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null) return;
    setState(() {
      final length = _end.difference(_start);
      _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
      _end = _start.add(length);
    });
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end));
    if (t == null) return;
    setState(() => _end = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _addMember() async {
    final candidates = _dir.values.where((m) => m.active && !_crew.contains(m.uid)).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final uid = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ajouter un équipier'),
        children: [
          for (final m in candidates)
            SimpleDialogOption(
              key: Key('pick-${m.uid}'),
              onPressed: () => Navigator.pop(ctx, m.uid),
              child: Row(children: [
                Text('${m.displayName} (${m.shortName})'),
                const SizedBox(width: 6),
                ProfileBadge(profile: m.profile, compact: true),
              ]),
            ),
        ],
      ),
    );
    if (uid != null) setState(() => _crew.add(uid));
  }

  Future<void> _addPassenger() async {
    // Contrôleur possédé par le dialogue lui-même (et non disposé ici juste
    // après le pop) : sinon le TextField est encore affiché pendant
    // l'animation de fermeture et Flutter l'utilise après dispose().
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PassengerDialog(),
    );
    if (name != null && name.isNotEmpty) setState(() => _passenger = name);
  }

  // --- enregistrement / actions ---

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Contrôles communs à un enregistrement normal et à une correction admin
  /// (Task 10) : appareil, destination, durée prévue (min/max). Factorisé
  /// pour éviter la duplication entre [_localError] et [_correctionError].
  String? _commonFieldError() {
    if (_aircraftId == null) return 'Choisissez un appareil.';
    if (_destination.text.trim().isEmpty) return 'Indiquez une destination.';
    final duration = _end.difference(_start);
    if (duration.inMinutes < minPlannedMinutes) {
      return 'Durée prévue minimale : $minPlannedMinutes min.';
    }
    if (duration > const Duration(hours: maxPlannedHours)) {
      return 'Durée prévue maximale : $maxPlannedHours h.';
    }
    return null;
  }

  /// Décision utilisateur 1 : contrôle du crédit (le serveur refuse aussi) —
  /// commun à un enregistrement normal et à une correction admin d'un vol non
  /// clôturé (skipCredit ne vaut que pour un vol déjà clôturé côté serveur).
  /// Blocage local uniquement quand le solde est lisible ici (cf.
  /// _canSeeCredit) ; sinon le serveur refusera l'action avec le même message.
  String? _creditError() {
    final cost = _estimatedCost;
    final credit = _availableCredit;
    if (cost != null && credit != null && credit < cost) {
      return 'Crédit insuffisant : il manque ${formatFcfa(cost - credit)}.';
    }
    return null;
  }

  String? _localError() {
    final common = _commonFieldError();
    if (common != null) return common;
    // Seul un admin crée après coup un vol passé (vol oublié).
    final pastAllowed = _me.isAdmin && widget.flight == null;
    if (!pastAllowed && !_start.isAfter(widget.now())) return 'L\'heure de départ est passée.';
    final d = _decision;
    if (!d.ok) return d.reason;
    // Décision utilisateur : hors validation (équipage figé), le créateur
    // doit rester le compte débité s'il n'est ni instructeur ni admin.
    if (!_validating) {
      final payerError = checkPayer(
        creatorUid: _me.uid,
        creatorProfile: _me.profile?.code,
        creatorIsAdmin: _me.isAdmin,
        crew: _crew,
      );
      if (payerError != null) return payerError;
    }
    return _creditError();
  }

  FlightDraft _draft() => FlightDraft(
        start: _start,
        end: _end,
        destination: _destination.text.trim(),
        aircraftId: _aircraftId!,
        crew: _crew,
        passengers: [if (_passenger != null) _passenger!],
        pricingMode: _showFuelChoice ? (_fuelOnly ? 'fuel_only' : 'standard') : null,
      );

  /// Exécute une action serveur, gère erreurs et succès communs (spec §11-12) :
  /// après tout succès, on referme l'écran (retour au planning).
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.of(context).maybePop(true);
    } on FlightConflict catch (e) {
      if (mounted) _snack(describeConflict(e.conflict, _dir));
    } on FlightFailure catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Enregistrement impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final error = _localError();
    if (error != null) {
      _snack(error);
      return;
    }
    final api = AppServices.of(context).flights!;
    await _run(() async {
      switch (_mode) {
        case _Mode.create:
          await api.create(_draft());
        case _Mode.edit:
          await api.update(widget.flight!.id, _draft());
        case _Mode.validate:
          final d = _draft();
          await api.validate(widget.flight!.id, changes: {
            'start': d.start.millisecondsSinceEpoch,
            'end': d.end.millisecondsSinceEpoch,
            'destination': d.destination,
            'aircraftId': d.aircraftId,
            if (d.pricingMode != null) 'pricingMode': d.pricingMode,
          });
        case _Mode.view:
          break; // bouton absent dans ce mode
      }
    });
  }

  Future<void> _refuse() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RefuseDialog(),
    );
    if (reason == null || !mounted) return;
    final api = AppServices.of(context).flights!;
    await _run(() => api.refuse(widget.flight!.id, reason));
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler ce vol ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = AppServices.of(context).flights!;
    await _run(() => api.cancel(widget.flight!.id));
  }

  /// Clôture (Task 9, spec §4.3) : durée réelle, montant si nécessaire, puis
  /// `closeFlight` et retour au planning (via _run). `category` peut être
  /// `null` (fix round 1, décision utilisateur 2 : tout membre d'équipage ou
  /// un admin clôture, même sans connaître l'appartenance d'un compte débité
  /// qui n'est pas le sien) : le dialogue s'ouvre quand même, seul son
  /// aperçu local du montant est alors indisponible.
  /// Plan 4b : appareil amphibie (amerrissages saisis), d'après la liste de
  /// tous les appareils, inactifs compris ; faux tant qu'elle n'est pas
  /// chargée.
  bool _isAmphibious(String? aircraftId) =>
      _allAircraft.any((a) => a.id == aircraftId && a.amphibious);

  /// Champ « Amerrissages » de la correction : appareil choisi amphibie, ou
  /// vol qui en a déjà (l'admin peut alors les ramener à 0 ; sinon le
  /// serveur refuse « Cet appareil n'est pas amphibie. »).
  bool get _showCorrectWaterLandings =>
      _isAmphibious(_aircraftId) || (_current?.waterLandings ?? 0) > 0;

  Future<void> _openClosing() async {
    final f = _current!;
    final category = _category(_debitedUid);
    final result = await showDialog<ClosingResult>(
      context: context,
      builder: (_) => ClosingDialog(
        plannedMinutes: f.end.difference(f.start).inMinutes,
        mode: f.pricingMode,
        category: category,
        pricing: _pricingForCost,
        hasPassenger: f.passengers.isNotEmpty,
        amphibious: _isAmphibious(f.aircraftId),
      ),
    );
    if (result == null || !mounted) return;
    final finance = AppServices.of(context).finance!;
    await _run(() => finance.closeFlight(
          f.id,
          actualMinutes: result.actualMinutes,
          shortFlightAmount: result.shortFlightAmount,
          customAmount: result.customAmount,
          landings: result.landings,
          waterLandings: result.waterLandings,
        ));
  }

  /// Task 10 (spec §4.5) : correction admin, à tout moment, champs de clôture
  /// compris sur un vol clôturé (les contrôles de la matrice de droits, de
  /// compte/appareil actif et d'heure passée ne s'appliquent pas côté
  /// serveur ; ceux conservés — composition, conflits, crédit hors clôture —
  /// sont vérifiés localement comme pour un enregistrement normal).
  String? _correctionError() {
    final common = _commonFieldError();
    if (common != null) return common;
    final f = _current!;
    if (f.isClosed) {
      final m = _correctActualMinutes;
      if (m == null || m < 1 || m > 720) return 'Durée réelle invalide (1 à 720 min).';
      final countError = landingsError(_correctLandingsValue, _correctWaterLandingsValue);
      if (countError != null) return countError;
      if (_correctNeedsShortAmount) {
        final short = parseAmount(_correctShortAmount.text);
        if (short == null) {
          return 'Montant à facturer obligatoire pour un vol de moins de '
              '${_pricingForCost.minPlannedMinutes} min.';
        }
        if (short > maxManualAmount) {
          return 'Montant trop élevé (${formatFcfa(maxManualAmount)} au maximum).';
        }
      }
      if (_correctCustomChecked) {
        final custom = parseAmount(_correctCustomAmount.text);
        if (custom == null) return 'Indiquez le montant.';
        if (custom > maxManualAmount) {
          return 'Montant trop élevé (${formatFcfa(maxManualAmount)} au maximum).';
        }
      }
      return null;
    }
    return _creditError();
  }

  /// Construit le payload d'`adminUpdateFlight` : les champs du vol comme un
  /// enregistrement normal (`pricingMode` inclus seulement si un choix est
  /// proposé, cf. `_draft`/`_showFuelChoice`, exactement comme un
  /// enregistrement normal), et, sur un vol clôturé, les champs de clôture.
  /// `pricingMode` n'est forcé explicitement que pour revenir d'un montant
  /// différent (`billedTo == 'off_app'`) à une facturation normale sans choix
  /// visible : sans lui, le serveur reprendrait le mode `custom` stocké faute
  /// de `pricingMode` envoyé (validateAdminUpdate). Avec `customAmount`, le
  /// serveur déduit lui-même le mode `custom`.
  Map<String, dynamic> _correctionPayload() {
    final payload = _draft().toPayload();
    final f = _current!;
    if (!f.isClosed) return payload;
    payload['actualMinutes'] = _correctActualMinutes;
    payload['landings'] = _correctLandingsValue;
    if (_showCorrectWaterLandings) payload['waterLandings'] = _correctWaterLandingsValue;
    if (_correctNeedsShortAmount) {
      payload['shortFlightAmount'] = parseAmount(_correctShortAmount.text);
    }
    if (_correctCustomChecked) {
      payload['customAmount'] = parseAmount(_correctCustomAmount.text);
    } else if (f.billedTo == 'off_app' && !payload.containsKey('pricingMode')) {
      payload['pricingMode'] = _pricingMode;
    }
    return payload;
  }

  Future<void> _saveCorrection() async {
    final error = _correctionError();
    if (error != null) {
      _snack(error);
      return;
    }
    final finance = AppServices.of(context).finance!;
    await _run(() => finance.adminUpdateFlight(_current!.id, _correctionPayload()));
  }

  /// Task 10 : suppression admin, à tout moment ; la confirmation mentionne
  /// le remboursement seulement pour un vol clôturé débité sur un compte
  /// (adminDeleteFlight rembourse alors automatiquement, côté serveur).
  Future<void> _deleteFlight() async {
    final f = _current!;
    final refund = f.isClosed && f.billedTo == 'account';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ce vol ?'),
        content: refund ? const Text('Le montant débité sera remboursé.') : null,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, supprimer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final finance = AppServices.of(context).finance!;
    await _run(() => finance.adminDeleteFlight(f.id));
  }

  // --- affichage ---

  @override
  Widget build(BuildContext context) {
    _syncPayerFlights();
    // Task 3 (retours de recette) : un vol existant supprimé ou devenu
    // introuvable pendant la consultation (annulé/effacé ailleurs) n'affiche
    // plus la fiche (champs alors obsolètes) ni aucun bouton.
    if (widget.flight != null && (_current == null || _current!.deleted)) {
      return Scaffold(
        appBar: AppBar(title: Text(formatDay(_start))),
        body: const Center(child: Text('Vol introuvable.')),
      );
    }
    final decision = _decision;
    final conflict = decision.status == 'valide' ? _conflict : null;
    // Calculé une seule fois (au lieu de deux fois dans le libellé ci-dessous).
    final conflictKind =
        conflict == null ? null : conflictCause(conflict.candidate, conflict.other.toRule());
    final aboard = _crew.length + (_passenger == null ? 0 : 1);
    final f = _current;
    final now = widget.now();
    final title = f == null ? 'Nouveau vol' : formatDay(_start);
    final canReorder = _me.isAdmin || _me.isInstructor;

    final buttons = <Widget>[
      if (_mode == _Mode.create || _actions.contains(FlightAction.edit))
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
      if (_actions.contains(FlightAction.validate)) ...[
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Valider')),
        OutlinedButton(onPressed: _saving ? null : _refuse, child: const Text('Refuser')),
      ],
      if (_actions.contains(FlightAction.cancel))
        TextButton(onPressed: _saving ? null : _cancel, child: const Text('Annuler le vol')),
      if (_actions.contains(FlightAction.close))
        FilledButton(
            key: const Key('close-flight'), onPressed: _saving ? null : _openClosing,
            child: const Text('Clôturer')),
      // Task 10 : un admin sans autre droit de modification (vol passé,
      // clôturé, ou vol d'un autre) peut tout de même tout corriger.
      if (_actions.contains(FlightAction.adminEdit) && _mode == _Mode.view && !_correcting)
        OutlinedButton(
          key: const Key('admin-correct'),
          onPressed: _saving ? null : () => setState(() => _correcting = true),
          child: const Text('Corriger'),
        ),
      if (_correcting)
        FilledButton(
          key: const Key('admin-save-correction'),
          onPressed: _saving ? null : _saveCorrection,
          child: const Text('Enregistrer la correction'),
        ),
      if (_actions.contains(FlightAction.adminDelete))
        TextButton(
          key: const Key('admin-delete'),
          onPressed: _saving ? null : _deleteFlight,
          child: const Text('Supprimer le vol'),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: appNavActions(context, widget.me)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (f != null) ...[
            // Task 9 : un vol clôturé n'affiche plus qu'un bilan, en tête de
            // fenêtre, et aucune action pour un non-admin (flightActions le
            // ferme déjà). Task 10 : un admin y garde « Corriger » et
            // « Supprimer le vol ».
            if (f.isClosed)
              ListTile(
                key: const Key('closed-summary'),
                title: Text(closedSummary(
                  actualMinutes: f.actualFlightMinutes ?? 0,
                  billedAmount: f.billedAmount ?? 0,
                  billedTo: f.billedTo ?? 'account',
                  debitedShortName: _short(_debitedUid),
                  landings: f.landings,
                  waterLandings: f.waterLandings,
                )),
              ),
            ListTile(
              title: const Text('Statut'),
              subtitle: Text(
                f.isExpiredRequest(now) ? 'Refusé (non validée avant le départ)' : statusLabel(f.effectiveStatus(now)),
                style: TextStyle(color: statusColor(f.effectiveStatus(now))),
              ),
            ),
            if (f.status == FlightStatus.refuse && f.refusalReason != null)
              ListTile(title: const Text('Motif du refus'), subtitle: Text(f.refusalReason!)),
            if (f.instructorUid != null)
              ListTile(title: Text('Instructeur désigné : ${_short(f.instructorUid!)}')),
            ListTile(title: const Text('Tarification'), subtitle: Text(pricingModeLabel(f.pricingMode))),
            // Task 9 : coût estimé / crédit disponible d'un vol non clôturé,
            // hors mode saisie (l'aperçu ci-dessous les affiche alors à la
            // place, avec les valeurs du brouillon en cours).
            if (!f.isClosed && !_fieldsEditable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _financeLines(context),
                ),
              ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Date'),
            subtitle: Text(formatDay(_start)),
            onTap: _fieldsEditable ? _pickDate : null,
          ),
          Row(children: [
            Expanded(
              child: ListTile(
                title: const Text('Départ'),
                subtitle: Text(formatTime(_start)),
                onTap: _fieldsEditable ? _pickStart : null,
              ),
            ),
            Expanded(
              child: ListTile(
                title: const Text('Fin'),
                subtitle: Text(formatTime(_end)),
                onTap: _fieldsEditable ? _pickEnd : null,
              ),
            ),
          ]),
          DropdownButtonFormField<String>(
            key: const Key('f-aircraft'),
            value: _aircraft.any((a) => a.id == _aircraftId) ? _aircraftId : null,
            decoration: const InputDecoration(labelText: 'Appareil'),
            items: [
              for (final a in _aircraft)
                DropdownMenuItem(value: a.id, child: Text('${a.label} (${a.registration})')),
            ],
            onChanged: _fieldsEditable ? (v) => setState(() => _aircraftId = v) : null,
          ),
          const SizedBox(height: 16),
          Text('Équipage', style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < _crew.length; i++)
            ListTile(
              leading: ProfileBadge(profile: _profile(_crew[i]), compact: true),
              title: Text(_short(_crew[i])),
              subtitle: i == 0 ? const Text(debitedLabel) : null,
              trailing: !_crewEditable
                  ? null
                  : Wrap(children: [
                      if (i > 0 && canReorder)
                        IconButton(
                          tooltip: 'Mettre en premier',
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: () => setState(() => _crew.insert(0, _crew.removeAt(i))),
                        ),
                      if (_crew.length > 1 && (_crew[i] != _me.uid || canReorder))
                        IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _crew.removeAt(i)),
                        ),
                    ]),
            ),
          if (_passenger != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(_passenger!),
              subtitle: const Text('Passager sans compte'),
              trailing: !_crewEditable
                  ? null
                  : IconButton(
                      tooltip: 'Retirer le passager',
                      icon: const Icon(Icons.close),
                      // Task 10 (fix round 1) : sans passager, « Montant
                      // différent » n'a plus de sens (closingBill le refuse) ;
                      // réinitialiser évite d'envoyer customAmount à tort si
                      // la case était restée cochée depuis une correction.
                      onPressed: () => setState(() {
                        _passenger = null;
                        _correctCustomChecked = false;
                      }),
                    ),
            ),
          if (_crewEditable && aboard < 2)
            Wrap(spacing: 8, children: [
              TextButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Ajouter un équipier'),
                onPressed: _addMember,
              ),
              TextButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Ajouter un passager sans compte'),
                onPressed: _addPassenger,
              ),
            ]),
          const SizedBox(height: 16),
          RawAutocomplete<String>(
            textEditingController: _destination,
            focusNode: _destinationFocus,
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              if (q.isEmpty) return const Iterable<String>.empty();
              return _destinations.where((d) => d.toLowerCase().contains(q));
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextField(
              key: const Key('f-destination'),
              controller: controller,
              focusNode: focusNode,
              enabled: _fieldsEditable,
              decoration: const InputDecoration(labelText: 'Destination'),
              onChanged: (_) => setState(() {}),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: SizedBox(
                  height: 200,
                  width: 300,
                  child: ListView(children: [
                    for (final o in options) ListTile(title: Text(o), onTap: () => onSelected(o)),
                  ]),
                ),
              ),
            ),
          ),
          if (_showFuelChoice)
            CheckboxListTile(
              key: const Key('f-fuel'),
              title: const Text('Carburant seulement'),
              value: _fuelOnly,
              onChanged: _fieldsEditable ? (v) => setState(() => _fuelOnly = v ?? false) : null,
            ),
          // Task 10 : champs de clôture modifiables pendant une correction
          // admin d'un vol clôturé (durée réelle, montants), en plus des
          // champs déjà modifiables ci-dessus.
          if (_correcting && f != null && f.isClosed) ...[
            const SizedBox(height: 16),
            Text('Clôture', style: Theme.of(context).textTheme.titleMedium),
            TextField(
              key: const Key('correct-minutes'),
              controller: _correctMinutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Durée réelle (minutes)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('correct-landings'),
              controller: _correctLandings,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Atterrissages'),
            ),
            if (_showCorrectWaterLandings)
              TextField(
                key: const Key('correct-water-landings'),
                controller: _correctWaterLandings,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amerrissages'),
              ),
            if (_correctNeedsShortAmount)
              TextField(
                key: const Key('correct-short-amount'),
                controller: _correctShortAmount,
                keyboardType: TextInputType.number,
                inputFormatters: const [AmountInputFormatter()],
                decoration: const InputDecoration(labelText: 'Montant à facturer'),
                onChanged: (_) => setState(() {}),
              ),
            if (_passenger != null) ...[
              CheckboxListTile(
                key: const Key('correct-custom-check'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Montant différent (facturé hors app)'),
                value: _correctCustomChecked,
                onChanged: (v) => setState(() => _correctCustomChecked = v ?? false),
              ),
              if (_correctCustomChecked)
                TextField(
                  key: const Key('correct-custom-amount'),
                  controller: _correctCustomAmount,
                  keyboardType: TextInputType.number,
                inputFormatters: const [AmountInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Montant'),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ],
          if (_fieldsEditable) ...[
            const SizedBox(height: 16),
            Card(
              key: const Key('preview'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_statusText(decision)),
                  Text('Mode : ${pricingModeLabel(_pricingMode)}'),
                  ..._previewFinanceLines(context),
                  if (conflict != null)
                    Text(
                      describeConflict(
                        ConflictInfo(
                          start: conflict.other.start,
                          end: conflict.other.end,
                          aircraft: conflict.other.aircraft,
                          crew: conflict.other.crew,
                          passengers: conflict.other.passengers,
                          kind: conflictKind!.kind,
                          members: conflictKind.members,
                        ),
                        _dir,
                      ),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    )
                  else if (decision.status == 'valide')
                    const Text('Aucun conflit connu.'),
                  Text('Aperçu indicatif : la décision finale revient au serveur.',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: buttons.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
              ),
            ),
    );
  }
}

/// Dialogue « passager sans compte » : possède son propre contrôleur (dispose
/// naturel à la fermeture, voir _addPassenger ci-dessus).
class _PassengerDialog extends StatefulWidget {
  const _PassengerDialog();

  @override
  State<_PassengerDialog> createState() => _PassengerDialogState();
}

class _PassengerDialogState extends State<_PassengerDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passager sans compte'),
      content: TextField(
        key: const Key('passenger-name'),
        controller: _c,
        decoration: const InputDecoration(labelText: 'Nom'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text.trim()),
            child: const Text('Ajouter')),
      ],
    );
  }
}

/// Dialogue « refuser la demande » : possède son propre contrôleur (dispose
/// naturel à la fermeture, comme _PassengerDialog) plutôt qu'un contrôleur
/// créé dans _refuse et disposé juste après le pop, qui plante pendant
/// l'animation de fermeture ("TextEditingController used after being
/// disposed").
class _RefuseDialog extends StatefulWidget {
  const _RefuseDialog();

  @override
  State<_RefuseDialog> createState() => _RefuseDialogState();
}

class _RefuseDialogState extends State<_RefuseDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refuser la demande'),
      content: TextField(
        key: const Key('refuse-reason'),
        controller: _c,
        decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text), child: const Text('Refuser')),
      ],
    );
  }
}
