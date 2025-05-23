// lib/models/flow_link.dart

/// Material vs emission flows.
enum FlowType { material, emission }

/// A directed flow between two processes.
class FlowLink {
  final String id;
  final String name;
  final String from;
  final String to;
  final double quantity;
  final String unit;
  final FlowType type;

  FlowLink({
    required this.id,
    required this.name,
    required this.from,
    required this.to,
    required this.quantity,
    required this.unit,
    required this.type,
  });

  /// Create a modified copy.
  FlowLink copyWith({
    String? id,
    String? name,
    String? from,
    String? to,
    double? quantity,
    String? unit,
    FlowType? type,
  }) {
    return FlowLink(
      id: id ?? this.id,
      name: name ?? this.name,
      from: from ?? this.from,
      to: to ?? this.to,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      type: type ?? this.type,
    );
  }

  /// Build from one entry of `flows_enriched` or `flows_linked`.
  factory FlowLink.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final from = json['from_process'] as String? ?? '';
    final to = json['to_process'] as String? ?? '';
    final qty = (json['quantity'] as num?)?.toDouble() ?? 0.0;
    final unit = json['unit'] as String? ?? '';
    final flowType = (json['flow_type'] as String? ?? 'material') == 'emission'
        ? FlowType.emission
        : FlowType.material;
    // Unique ID so you can diff/update them
    final id = '$from→$to:$name';
    return FlowLink(
      id: id,
      name: name,
      from: from,
      to: to,
      quantity: qty,
      unit: unit,
      type: flowType,
    );
  }

  /// Parse all flows out of the LCA result.
  static List<FlowLink> fromLcaJson(Map<String, dynamic> result) {
    final raw = result['flows_enriched'] as List<dynamic>? ??
        result['flows_linked'] as List<dynamic>? ??
        [];
    return raw.map((e) => FlowLink.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Convert back to JSON (for backend updates).
  Map<String, dynamic> toJson() => {
        'name': name,
        'from_process': from,
        'to_process': to,
        'quantity': quantity,
        'unit': unit,
        'flow_type': type == FlowType.emission ? 'emission' : 'material',
      };
}
