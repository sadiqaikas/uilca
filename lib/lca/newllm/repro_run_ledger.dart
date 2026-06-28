import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ReproLedgerArtifacts {
  final String snapshotCsv;
  final Uint8List sqliteBytes;

  const ReproLedgerArtifacts({
    required this.snapshotCsv,
    required this.sqliteBytes,
  });
}

class ReproRunLedger {
  static const String _openLcaBackendBaseUrl = String.fromEnvironment(
    'OPENLCA_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );

  static int _runUidNonce = 0;

  static String promptHash(String prompt) {
    return sha256.convert(utf8.encode(prompt)).toString();
  }

  static String newRunUid({
    required String bundleName,
    required String modelName,
    required String promptHash,
  }) {
    _runUidNonce += 1;
    final raw = [
      bundleName.trim(),
      modelName.trim(),
      promptHash.trim(),
      DateTime.now().toUtc().toIso8601String(),
      _runUidNonce.toString(),
    ].join('|');
    return sha256.convert(utf8.encode(raw)).toString();
  }

  static Future<int> registerRun({
    required String bundleName,
    required String modelName,
    required String promptHash,
    required String status,
    required String runUid,
    String? providerLabel,
    String? createdAt,
    Map<String, dynamic>? metadata,
  }) async {
    final uri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/reproducibility-ledger/runs',
    );
    _guardWebMixedContent(uri);
    final response = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'bundle_name': bundleName,
        'model_name': modelName,
        'prompt_hash': promptHash,
        'status': status,
        'run_uid': runUid,
        if ((providerLabel ?? '').trim().isNotEmpty)
          'provider_label': providerLabel!.trim(),
        if ((createdAt ?? '').trim().isNotEmpty) 'created_at': createdAt!.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      }),
    );
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw Exception(
          'Sequential ledger endpoint is not available on the OpenLCA backend '
          'at $_openLcaBackendBaseUrl. Restart the backend, then rerun this experiment.',
        );
      }
      throw Exception(
        'Ledger registration failed ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Ledger registration returned invalid JSON.');
    }
    final run = decoded['run'];
    if (run is! Map<String, dynamic>) {
      throw Exception('Ledger registration response did not contain a run row.');
    }
    final ledgerId = run['ledger_id'];
    if (ledgerId is int) return ledgerId;
    if (ledgerId is num) return ledgerId.toInt();
    throw Exception('Ledger registration response did not contain a ledger id.');
  }

  static Future<ReproLedgerArtifacts> fetchBundleArtifacts(
    String bundleName, {
    int? upToLedgerId,
  }) async {
    final snapshotUri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/reproducibility-ledger/'
      '$bundleName/snapshot.csv',
    ).replace(
      queryParameters: upToLedgerId == null
          ? null
          : {'up_to_ledger_id': '$upToLedgerId'},
    );
    final sqliteUri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/reproducibility-ledger/database.sqlite',
    );
    _guardWebMixedContent(snapshotUri);
    _guardWebMixedContent(sqliteUri);

    final snapshotResponse = await http.get(
      snapshotUri,
      headers: const {'Accept': 'text/csv'},
    );
    if (snapshotResponse.statusCode != 200) {
      if (snapshotResponse.statusCode == 404) {
        throw Exception(
          'Sequential ledger snapshot endpoint is not available on the OpenLCA backend '
          'at $_openLcaBackendBaseUrl. Restart the backend, then rerun this experiment.',
        );
      }
      throw Exception(
        'Ledger snapshot download failed '
        '${snapshotResponse.statusCode}: ${snapshotResponse.body}',
      );
    }

    final sqliteResponse = await http.get(
      sqliteUri,
      headers: const {'Accept': 'application/octet-stream'},
    );
    if (sqliteResponse.statusCode != 200) {
      if (sqliteResponse.statusCode == 404) {
        throw Exception(
          'Sequential ledger database endpoint is not available on the OpenLCA backend '
          'at $_openLcaBackendBaseUrl. Restart the backend, then rerun this experiment.',
        );
      }
      throw Exception(
        'Ledger database download failed '
        '${sqliteResponse.statusCode}: ${sqliteResponse.body}',
      );
    }

    return ReproLedgerArtifacts(
      snapshotCsv: snapshotResponse.body,
      sqliteBytes: sqliteResponse.bodyBytes,
    );
  }

  static void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'The app is running over HTTPS but the OpenLCA backend URL is HTTP.',
      );
    }
  }
}
