/// Type-safe accessors for network message fields.
extension SafeMsg on Map<String, dynamic> {
  int? intVal(String key) { final v = this[key]; return v is int ? v : null; }
  String? strVal(String key) { final v = this[key]; return v is String ? v : null; }
  bool? boolVal(String key) { final v = this[key]; return v is bool ? v : null; }
  List<int>? intList(String key) {
    final v = this[key];
    if (v is! List) return null;
    try { return v.cast<int>(); } catch (_) { return null; }
  }
  List<String>? strList(String key) {
    final v = this[key];
    if (v is! List) return null;
    try { return v.cast<String>(); } catch (_) { return null; }
  }
}
