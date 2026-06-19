import '../../../core/models/timeline_models.dart';

class NestedSequenceManager {
  final List<NestedSequence> sequences = [];

  NestedSequence create(String name) {
    final seq = NestedSequence.empty('seq_${DateTime.now().millisecondsSinceEpoch}', name);
    sequences.add(seq);
    return seq;
  }

  void remove(String id) => sequences.removeWhere((s) => s.id == id);

  NestedSequence? get(String id) {
    try { return sequences.firstWhere((s) => s.id == id); }
    catch (_) { return null; }
  }

  List<Map<String, dynamic>> toJson() => sequences.map((s) => s.toJson()).toList();

  void fromJson(List<Map<String, dynamic>> json) {
    sequences.clear();
    for (final j in json) {
      sequences.add(NestedSequence.fromJson(j));
    }
  }
}

class Marker {
  final String id;
  final String name;
  final double time;
  final String color;
  final String? note;
  final MarkerType type;

  Marker({
    required this.id,
    required this.name,
    required this.time,
    this.color = '#FFD700',
    this.note,
    this.type = MarkerType.standard,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'time': time,
    'color': color, 'note': note, 'type': type.name,
  };

  factory Marker.fromJson(Map<String, dynamic> json) => Marker(
    id: json['id'] as String,
    name: json['name'] as String,
    time: (json['time'] as num).toDouble(),
    color: json['color'] as String? ?? '#FFD700',
    note: json['note'] as String?,
    type: MarkerType.values.firstWhere((t) => t.name == json['type'], orElse: () => MarkerType.standard),
  );
}

enum MarkerType { standard, chapter, todo, highlight }

class MarkerManager {
  final List<Marker> markers = [];

  void add(Marker marker) {
    markers.add(marker);
    markers.sort((a, b) => a.time.compareTo(b.time));
  }

  void remove(String id) => markers.removeWhere((m) => m.id == id);

  void clear() => markers.clear();

  List<Marker> atTime(double time, {double tolerance = 0.1}) =>
    markers.where((m) => (m.time - time).abs() < tolerance).toList();

  List<Map<String, dynamic>> toJson() => markers.map((m) => m.toJson()).toList();

  void fromJson(List<Map<String, dynamic>> json) {
    markers.clear();
    for (final j in json) markers.add(Marker.fromJson(j));
  }
}
