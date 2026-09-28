class Aircraft {
  const Aircraft({
    required this.id,
    required this.registration,
    required this.label,
    required this.active,
  });

  final String id;
  final String registration;
  final String label;
  final bool active;

  factory Aircraft.fromMap(String id, Map<String, dynamic> m) => Aircraft(
        id: id,
        registration: (m['registration'] as String?) ?? '',
        label: (m['label'] as String?) ?? '',
        active: m['active'] == true,
      );
}
