// lib/controllers/lca_controller.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Central place to invoke backend LCA runs.
///
/// Replace `_endpoint` with your actual LCA API URL.
class LcaController {
  // TODO: update with your backend API endpoint
  static const _endpoint = 'https://api.yourdomain.com/lca';

  /// Sends the current LCA JSON payload to the backend,
  /// runs the LCA pipeline there, and returns the updated result.
  static Future<Map<String, dynamic>> run(
      Map<String, dynamic> lcaJson) async {
    final uri = Uri.parse(_endpoint);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(lcaJson),
    );

    if (response.statusCode == 200) {
      // Expect the backend to return updated LCA JSON
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'LCA run failed (HTTP ${response.statusCode}): ${response.body}');
    }
  }
}
