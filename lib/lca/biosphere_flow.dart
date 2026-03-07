
class BiosphereFlow {
  final String id;               // UUID from biosphere3
  final String name;             // Flow name
  final String unit;             // e.g. "kilogram"
  final List<String> categories; // e.g. ["air", "non-urban air or from high stacks"]

  const BiosphereFlow({
    required this.id,
    required this.name,
    required this.unit,
    required this.categories,
  });

  factory BiosphereFlow.fromJson(Map<String, dynamic> json) => BiosphereFlow(
        id: json['id'] as String,
        name: json['name'] as String,
        unit: json['unit'] as String,
        categories: List<String>.from(json['categories'] as List),
      );
}
