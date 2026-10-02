class Aircraft {
  const Aircraft({
    required this.id,
    required this.registration,
    required this.label,
    required this.active,
    this.amphibious = false,
    this.fuelLiters,
    this.fuelFlightId,
  });

  final String id;
  final String registration;
  final String label;
  final bool active;

  /// Plan 4b : amerrissages saisis à la clôture.
  final bool amphibious;

  /// Plan 7 : carburant actuel (spec §9.2) et vol qui l'a fixé.
  final int? fuelLiters;
  final String? fuelFlightId;

  factory Aircraft.fromMap(String id, Map<String, dynamic> m) => Aircraft(
        id: id,
        registration: (m['registration'] as String?) ?? '',
        label: (m['label'] as String?) ?? '',
        active: m['active'] == true,
        amphibious: m['amphibious'] == true,
        fuelLiters: (m['fuelLiters'] as num?)?.toInt(),
        fuelFlightId: m['fuelFlightId'] as String?,
      );
}
