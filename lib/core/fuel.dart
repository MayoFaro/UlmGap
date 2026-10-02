// Suivi carburant (spec §9) : contrôles de saisie (mêmes messages que le
// serveur) et consommation estimée, indicative. Module pur.
import '../data/flight.dart';

const maxFuelLiters = 100;

bool _ok(int? v) => v != null && v >= 0 && v <= maxFuelLiters;

/// null si les trois valeurs sont valides.
String? fuelError({required int? start, required int? added, required int? end}) {
  if (!_ok(start)) return 'Carburant au départ invalide (0 à $maxFuelLiters L).';
  if (!_ok(added)) return 'Carburant ajouté invalide (0 à $maxFuelLiters L).';
  if (!_ok(end)) return 'Carburant rangé invalide (0 à $maxFuelLiters L).';
  return null;
}

String fuelText(int? liters) => liters == null ? 'inconnu' : '$liters L';

/// Écart au départ : valeur déclarée différente de la valeur prévue, ou
/// prévue inconnue.
bool fuelGap(Flight f) =>
    f.fuelStartExpectedLiters == null || f.fuelStartExpectedLiters != f.fuelStartLiters;

class FuelStats {
  const FuelStats(this.litersPerHour, this.flights, this.minutes);
  final double litersPerHour;
  final int flights;
  final int minutes;
}

/// Consommation estimée : Σ (départ + ajouté − rangé) / Σ durée réelle, sur
/// les vols clôturés non supprimés avec carburant ; null sans vol utile.
FuelStats? fuelStats(Iterable<Flight> flights) {
  var liters = 0;
  var minutes = 0;
  var count = 0;
  for (final f in flights) {
    final m = f.actualFlightMinutes;
    if (!f.isClosed || f.deleted || !f.hasFuel || m == null || m <= 0) continue;
    liters += f.fuelStartLiters! + f.fuelAddedLiters! - f.fuelEndLiters!;
    minutes += m;
    count++;
  }
  if (count == 0) return null;
  return FuelStats(liters * 60 / minutes, count, minutes);
}

String formatLitersPerHour(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} L/h';
