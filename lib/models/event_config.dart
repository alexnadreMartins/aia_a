class EventConfig {
  final Map<int, String> eventMap;

  EventConfig({required this.eventMap});

  // Default Configuration
  factory EventConfig.defaultConfig() {
    return EventConfig(eventMap: {
      1: "Foto convite",
      2: "Festa junina",
      3: "Dia da familia",
      4: "Dia das maes",
      5: "Dias dos pais",
      6: "Dia das crianças",
      7: "Festas",
      8: "Colação",
      9: "Baile/jantar",
      10: "Culto",
      11: "Missa",
    });
  }

  Map<String, dynamic> toJson() {
    // Convert int keys to String for JSON compatibility (Firestore Map keys must be strings)
    return eventMap.map((key, value) => MapEntry(key.toString(), value));
  }

  factory EventConfig.fromJson(Map<String, dynamic> json) {
    final map = <int, String>{};
    json.forEach((key, value) {
      final intKey = int.tryParse(key);
      if (intKey != null) {
        map[intKey] = value.toString();
      }
    });
    return EventConfig(eventMap: map);
  }
}
