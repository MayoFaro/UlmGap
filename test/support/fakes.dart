import 'dart:async';

import 'package:ulmgap/core/pricing.dart';
import 'package:ulmgap/core/profiles.dart';
import 'package:ulmgap/data/account_movement.dart';
import 'package:ulmgap/data/admin_api.dart';
import 'package:ulmgap/data/aircraft.dart';
import 'package:ulmgap/data/app_user.dart';
import 'package:ulmgap/data/auth_service.dart';
import 'package:ulmgap/data/crew_member.dart';
import 'package:ulmgap/data/finance_api.dart';
import 'package:ulmgap/data/flight.dart';
import 'package:ulmgap/data/flight_api.dart';
import 'package:ulmgap/data/user_repository.dart';

/// Émet [initial] puis relaie [rest] (même schéma que FakeAuthService.changes :
/// une valeur de départ suivie d'un flux contrôlable, pour simuler une
/// écoute Firestore qui reçoit sa valeur courante puis les mises à jour).
Stream<T> _seeded<T>(T initial, Stream<T> rest) async* {
  yield initial;
  yield* rest;
}

class FakeAuthService implements AuthService {
  final _ctrl = StreamController<AuthSnapshot?>.broadcast();
  AuthSnapshot? current;
  final calls = <String>[];
  String? failWith; // message d'AuthFailure à lever sur signIn

  void emit(AuthSnapshot? s) {
    current = s;
    _ctrl.add(s);
  }

  @override
  Stream<AuthSnapshot?> changes() async* {
    yield current;
    yield* _ctrl.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    if (failWith != null) throw AuthFailure(failWith!);
  }

  @override
  Future<void> signOut() async => calls.add('signOut');
  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset:$email');
  @override
  Future<void> sendEmailVerification() async => calls.add('verify');
  @override
  Future<void> reload() async => calls.add('reload');
}

class FakeUserRepository implements UserRepository {
  final users = <String, AppUser>{};
  int watchCalls = 0;

  /// Si défini, watchUser renvoie ce flux (pour simuler erreurs et mises à jour).
  StreamController<AppUser?>? live;

  @override
  Stream<AppUser?> watchUser(String uid) {
    watchCalls++;
    return live?.stream ?? Stream.value(users[uid]);
  }
}

AppUser testUser({
  String uid = 'u1',
  bool active = true,
  bool isAdmin = false,
  String? profile = 'eleve',
  String category = 'EXT',
  String shortName = 'JDU',
  int balance = 0,
}) =>
    AppUser.fromMap(uid, {
      'displayName': 'Jean Dupont',
      'shortName': shortName,
      'email': 'jean@club.fr',
      'profile': profile,
      'category': category,
      'isAdmin': isAdmin,
      'active': active,
      'balance': balance,
    });

// --- ajouts Task 8 ---
class FakeAdminApi implements AdminApi {
  final usersCtrl = StreamController<List<AppUser>>.broadcast();
  final aircraftCtrl = StreamController<List<Aircraft>>.broadcast();
  List<AppUser> users = [];
  List<Aircraft> aircraft = [];
  final created = <Map<String, dynamic>>[];
  final updated = <String, Map<String, dynamic>>{};
  final upserted = <Map<String, dynamic>>[];
  Object? error; // si défini, les flux de listes échouent
  bool hold = false; // si vrai, les flux n'émettent rien (chargement)

  @override
  Stream<List<AppUser>> watchAllUsers() async* {
    if (error != null) throw error!;
    if (!hold) yield users;
    yield* usersCtrl.stream;
  }

  bool failPasswordLink = false;
  final linksSent = <String>[];

  @override
  Future<String> createUser(Map<String, dynamic> input) async {
    created.add(input);
    if (failPasswordLink) throw const PasswordLinkNotSent('new-uid');
    return 'new-uid';
  }

  @override
  Future<void> sendPasswordLink(String email) async => linksSent.add(email);

  @override
  Future<void> updateUser(String uid, Map<String, dynamic> patch) async => updated[uid] = patch;

  @override
  Stream<List<Aircraft>> watchAircraft() async* {
    if (error != null) throw error!;
    if (!hold) yield aircraft;
    yield* aircraftCtrl.stream;
  }

  @override
  Future<String> upsertAircraft(Map<String, dynamic> input) async {
    upserted.add(input);
    return 'a-new';
  }
}

// --- ajouts plan 2 ---
Flight testFlight({
  String id = 'f1',
  DateTime? start,
  DateTime? end,
  String status = 'valide',
  List<String> crew = const ['u1'],
  List<String> passengers = const [],
  String createdBy = 'u1',
  String? instructorUid,
  String aircraftId = 'a1',
  String aircraft = 'F-JABC',
  String destination = 'Lomé',
  String pricingMode = 'standard',
  String? refusalReason,
  bool deleted = false,
  bool isClosed = false,
  int? actualFlightMinutes,
  int? billedAmount,
  String? billedTo,
  String? payerUidField,
}) {
  final s = start ?? DateTime(2026, 10, 13, 9);
  return Flight.fromMap(id, {
    'start': s,
    'end': end ?? s.add(const Duration(hours: 1)),
    'destination': destination,
    'aircraftId': aircraftId,
    'aircraft': aircraft,
    'crew': crew,
    'passengers': passengers,
    'instructorUid': instructorUid,
    'status': status,
    'refusalReason': refusalReason,
    'createdBy': createdBy,
    'pricingMode': pricingMode,
    'isClosed': isClosed,
    'deleted': deleted,
    'actualFlightMinutes': actualFlightMinutes,
    'billedAmount': billedAmount,
    'billedTo': billedTo,
    'payerUid': payerUidField,
  });
}

CrewMember member(String uid, String short, String? profile, {bool active = true}) =>
    CrewMember.fromMap(uid, {
      'displayName': 'Nom $short',
      'shortName': short,
      'profile': profile,
      'active': active,
    });

Flight? _byId(List<Flight> l, String id) {
  for (final f in l) {
    if (f.id == id) return f;
  }
  return null;
}

class FakeFlightApi implements FlightApi {
  List<Flight> flights = [];
  List<CrewMember> directory = [];
  List<Aircraft> aircraft = [];
  Map<String, UserCategory> categories = {};
  List<String> destinations = [];
  Object? error; // si défini, watchFrom échoue
  Object? flightError; // si défini, watchFlight échoue
  Object? failWith; // si défini, les actions échouent (FlightFailure ou toute autre erreur)
  final flightsCtrl = StreamController<List<Flight>>.broadcast();

  final created = <Map<String, dynamic>>[];
  final updated = <String, Map<String, dynamic>>{};
  final validated = <String, Map<String, dynamic>>{};
  final refused = <String, String?>{};
  final cancelled = <String>[];

  void _fail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<List<Flight>> watchFrom(DateTime from) async* {
    if (error != null) throw error!;
    yield flights;
    yield* flightsCtrl.stream;
  }

  @override
  Stream<Flight?> watchFlight(String id) async* {
    if (flightError != null) throw flightError!;
    yield _byId(flights, id);
    yield* flightsCtrl.stream.map((l) => _byId(l, id));
  }

  @override
  Stream<List<CrewMember>> watchDirectory() => Stream.value(directory);
  @override
  Stream<Map<String, UserCategory>> watchCategories() => Stream.value(categories);
  @override
  Stream<List<Aircraft>> watchAircraft() => Stream.value(aircraft);
  @override
  Future<List<String>> recentDestinations() async => destinations;

  @override
  Future<String> create(FlightDraft draft) async {
    _fail();
    created.add(draft.toPayload());
    return 'f-new';
  }

  @override
  Future<void> update(String id, FlightDraft draft) async {
    _fail();
    updated[id] = draft.toPayload();
  }

  @override
  Future<void> validate(String id, {Map<String, dynamic> changes = const {}}) async {
    _fail();
    validated[id] = changes;
  }

  @override
  Future<void> refuse(String id, String? reason) async {
    _fail();
    refused[id] = reason;
  }

  @override
  Future<void> cancel(String id) async {
    _fail();
    cancelled.add(id);
  }
}

// --- ajouts Task 8 (finances) ---
class FakeFinanceApi implements FinanceApi {
  Pricing pricing = defaultPricing;
  List<AppUser> accounts = [];
  final Map<String, List<AccountMovement>> movements = {};
  List<Flight> flights = [];
  int balance = 0; // rendu par credit/correct
  Object? failWith; // si défini, les actions échouent

  /// Si défini, watchAccounts reste en direct (fix round 1, Task 11) : chaque
  /// abonnement reçoit d'abord `accounts`, puis les émissions ajoutées ici
  /// (mêmes solde/liste pour tous les écrans, comme un flux Firestore).
  StreamController<List<AppUser>>? accountsLive;

  Pricing? updatedPricing;
  final credited = <Map<String, dynamic>>[];
  final corrected = <Map<String, dynamic>>[];
  final closed = <Map<String, dynamic>>[];
  final adminUpdated = <String, Map<String, dynamic>>{};
  final adminDeleted = <String>[];

  void _fail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<Pricing> watchPricing() => Stream.value(pricing);

  @override
  Future<void> updatePricing(Pricing p) async {
    _fail();
    updatedPricing = p;
  }

  @override
  Stream<List<AccountMovement>> watchMovements(String uid) =>
      Stream.value(movements[uid] ?? const []);

  @override
  Stream<List<AppUser>> watchAccounts() {
    final ctrl = accountsLive;
    if (ctrl == null) return Stream.value(accounts);
    return _seeded(accounts, ctrl.stream);
  }

  @override
  Future<int> credit(String uid, int amount, String? reason) async {
    _fail();
    credited.add({'uid': uid, 'amount': amount, 'reason': reason});
    return balance;
  }

  @override
  Future<int> correct(String uid, int amount, String reason) async {
    _fail();
    corrected.add({'uid': uid, 'amount': amount, 'reason': reason});
    return balance;
  }

  @override
  Future<void> closeFlight(
    String flightId, {
    required int actualMinutes,
    int? shortFlightAmount,
    int? customAmount,
  }) async {
    _fail();
    closed.add({
      'flightId': flightId,
      'actualMinutes': actualMinutes,
      'shortFlightAmount': shortFlightAmount,
      'customAmount': customAmount,
    });
  }

  @override
  Future<void> adminUpdateFlight(String flightId, Map<String, dynamic> payload) async {
    _fail();
    adminUpdated[flightId] = payload;
  }

  @override
  Future<void> adminDeleteFlight(String flightId) async {
    _fail();
    adminDeleted.add(flightId);
  }

  @override
  Stream<List<Flight>> watchFlightsBetween(DateTime from, DateTime to) => Stream.value(
        flights.where((f) => !f.start.isBefore(from) && f.start.isBefore(to)).toList(),
      );
}
