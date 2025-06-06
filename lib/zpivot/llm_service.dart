import 'dart:convert';
import 'package:http/http.dart' as http;
import 'canvas.dart';

/// Represents the LLM’s prediction for the canvas:
/// - A list of process labels (in order)
/// - A list of flows, each pointing by index into that list
class CanvasPrediction {
  final List<String> processes;
  final List<FlowPrediction> flows;
  CanvasPrediction({required this.processes, required this.flows});

  factory CanvasPrediction.fromJson(Map<String, dynamic> j) => CanvasPrediction(
        processes: List<String>.from(j['processes'] as List),
        flows: (j['flows'] as List)
            .map((f) => FlowPrediction.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

class FlowPrediction {
  final int fromIndex;
  final int toIndex;
  final String label;
  FlowPrediction({
    required this.fromIndex,
    required this.toIndex,
    required this.label,
  });

  factory FlowPrediction.fromJson(Map<String, dynamic> j) => FlowPrediction(
        fromIndex: j['from'] as int,
        toIndex: j['to'] as int,
        label: j['label'] as String,
      );
}

class LlmService {
  final Uri endpoint;
  final http.Client _client;

  LlmService({required this.endpoint}) : _client = http.Client();

  /// Send prompt + freedom + existing canvas state → predicted new canvas
  Future<CanvasPrediction> predictCanvas({
    required String prompt,
    required double freedom,
    required List<ProcessNode> existingNodes,
    required List<Connection> existingConnections,
  }) async {
    final body = {
      'prompt': prompt,
      'freedom': freedom,
      'existing_processes':
          existingNodes.map((n) => {'label': n.label}).toList(),
      'existing_flows': existingConnections
          .map((c) => {
                'from': existingNodes
                    .indexWhere((n) => n.id == c.fromId),
                'to': existingNodes
                    .indexWhere((n) => n.id == c.toId),
                'label': c.label
              })
          .toList(),
    };
    final resp = await _client.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode == 200) {
      return CanvasPrediction.fromJson(jsonDecode(resp.body));
    } else {
      throw Exception('LLM HTTP ${resp.statusCode}: ${resp.body}');
    }
  }
}
