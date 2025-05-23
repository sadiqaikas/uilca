// lib/models/process_node.dart

import 'uncertainty_level.dart';

/// A single process in the LCA graph, with name & uncertainty.
class ProcessNode {
  final String id;
  final String name;
  final UncertaintyLevel uncertainty;

  ProcessNode({
    required this.id,
    required this.name,
    required this.uncertainty,
  });

  /// Create a modified copy.
  ProcessNode copyWith({
    String? id,
    String? name,
    UncertaintyLevel? uncertainty,
  }) {
    return ProcessNode(
      id: id ?? this.id,
      name: name ?? this.name,
      uncertainty: uncertainty ?? this.uncertainty,
    );
  }

  /// Build from one entry of `result['process_loop']`.
  factory ProcessNode.fromJson(Map<String, dynamic> json) {
    final procName = json['process'] as String? ?? '';
    final uncNum = (json['uncertainty'] as num?)?.toDouble() ?? 0.0;
    return ProcessNode(
      id: procName,
      name: procName,
      uncertainty: UncertaintyLevel.fromValue(uncNum),
    );
  }

  /// Parse all processes out of the LCA result.
  static List<ProcessNode> fromLcaJson(Map<String, dynamic> result) {
    final loop = result['process_loop'] as List<dynamic>? ?? [];
    return loop
        .map((e) => ProcessNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Convert back to JSON (for sending edits to backend).
  Map<String, dynamic> toJson() => {
        'process': id,
        'name': name,
        'uncertainty': uncertaintyValue,
      };

  /// Numeric uncertainty for serialization.
  double get uncertaintyValue {
    switch (uncertainty) {
      case UncertaintyLevel.user:
        return 0.0;
      case UncertaintyLevel.database:
        return 0.1;
      case UncertaintyLevel.adapted:
        return 0.25;
      case UncertaintyLevel.inferred:
        return 0.5;
    }
  }
}
