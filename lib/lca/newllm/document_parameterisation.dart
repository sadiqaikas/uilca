import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class LlmDocumentReference {
  final String id;
  final String name;
  final String kind;
  final int pageCount;
  final int detectedTableCount;
  final List<int> detectedTablePages;
  final String? uploadedAt;

  const LlmDocumentReference({
    required this.id,
    required this.name,
    required this.kind,
    required this.pageCount,
    required this.detectedTableCount,
    this.detectedTablePages = const [],
    this.uploadedAt,
  });

  factory LlmDocumentReference.fromJson(Map<String, dynamic> json) {
    final rawPages = json['detected_table_pages'];
    return LlmDocumentReference(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      kind: (json['kind'] ?? 'pdf').toString(),
      pageCount: _toInt(json['page_count']) ?? 0,
      detectedTableCount: _toInt(json['detected_table_count']) ?? 0,
      detectedTablePages: rawPages is List
          ? rawPages
              .map(_toInt)
              .whereType<int>()
              .where((value) => value > 0)
              .toList()
          : const <int>[],
      uploadedAt: (json['uploaded_at'] ?? '').toString().trim().isEmpty
          ? null
          : (json['uploaded_at'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toPromptContextJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'page_count': pageCount,
        'detected_table_count': detectedTableCount,
        if (detectedTablePages.isNotEmpty)
          'detected_table_pages': detectedTablePages,
      };

  String get displayName => name.trim().isEmpty ? id : name.trim();

  String get promptInsertionText => 'from uploaded document $displayName';

  String get summaryText {
    final parts = <String>[
      if (pageCount > 0) '$pageCount page${pageCount == 1 ? '' : 's'}',
      if (detectedTableCount > 0)
        '$detectedTableCount table${detectedTableCount == 1 ? '' : 's'}',
      if (detectedTablePages.isNotEmpty)
        'table pages ${detectedTablePages.take(6).join(', ')}',
    ];
    return parts.isEmpty ? kind.toUpperCase() : parts.join(' • ');
  }
}

class DocumentExtractionRecord {
  final LlmDocumentReference document;
  final String query;
  final List<String> assumptions;
  final List<Map<String, dynamic>> matches;
  final List<Map<String, dynamic>> fallbackTextMatches;

  const DocumentExtractionRecord({
    required this.document,
    required this.query,
    required this.assumptions,
    required this.matches,
    required this.fallbackTextMatches,
  });

  factory DocumentExtractionRecord.fromToolResult(
    Map<String, dynamic> result,
  ) {
    final rawDocument = result['document'];
    final document = rawDocument is Map
        ? LlmDocumentReference.fromJson(rawDocument.cast<String, dynamic>())
        : LlmDocumentReference.fromJson(const <String, dynamic>{});

    return DocumentExtractionRecord(
      document: document,
      query: (result['query'] ?? '').toString().trim(),
      assumptions: _stringList(result['assumptions']),
      matches: _mapList(result['matches']),
      fallbackTextMatches: _mapList(result['fallback_text_matches']),
    );
  }

  Map<String, dynamic> toReportJson() => {
        'document': document.toPromptContextJson(),
        'query': query,
        'assumptions': assumptions,
        'matches': matches,
        if (fallbackTextMatches.isNotEmpty)
          'fallback_text_matches': fallbackTextMatches,
      };

  String get sourceLabel => document.displayName;

  String get sourceSummary {
    final pieces = <String>[
      sourceLabel,
      if (document.pageCount > 0) '${document.pageCount} pages',
      if (document.detectedTableCount > 0)
        '${document.detectedTableCount} tables detected',
    ];
    return pieces.join(' • ');
  }
}

class DocumentParameterisationService {
  static const String _defaultBackendBaseUrl = String.fromEnvironment(
    'DOCUMENT_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  final String backendBaseUrl;

  const DocumentParameterisationService({
    this.backendBaseUrl = _defaultBackendBaseUrl,
  });

  Future<LlmDocumentReference> uploadPdf({
    required Uint8List bytes,
    required String filename,
  }) async {
    final uri = _resolveUri('/documents/pdf');
    _guardWebMixedContent(uri);

    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename.trim().isEmpty ? 'uploaded.pdf' : filename.trim(),
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        'Document upload failed (${response.statusCode}): '
        '${_messageFromResponse(decoded, response.body)}',
      );
    }

    final rawDocument = decoded['document'];
    if (rawDocument is! Map) {
      throw Exception('Document upload succeeded but no document metadata returned.');
    }
    return LlmDocumentReference.fromJson(rawDocument.cast<String, dynamic>());
  }

  Future<void> deleteDocument(String documentId) async {
    final uri = _resolveUri('/documents/$documentId');
    _guardWebMixedContent(uri);
    final response = await http.delete(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode == 404) {
      return;
    }
    if (response.statusCode != 200) {
      final decoded = _decodeJsonMap(response.body);
      throw Exception(
        'Document delete failed (${response.statusCode}): '
        '${_messageFromResponse(decoded, response.body)}',
      );
    }
  }

  Future<Map<String, dynamic>> queryDocument({
    required String documentId,
    required String query,
    List<int>? pageNumbers,
    int maxTables = 5,
    int maxRows = 15,
  }) async {
    final uri = _resolveUri('/documents/pdf/query');
    _guardWebMixedContent(uri);
    final response = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'document_id': documentId,
        'query': query,
        if (pageNumbers != null && pageNumbers.isNotEmpty)
          'page_numbers': pageNumbers,
        'max_tables': maxTables,
        'max_rows': maxRows,
      }),
    );

    final decoded = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        'Document query failed (${response.statusCode}): '
        '${_messageFromResponse(decoded, response.body)}',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> queryDocumentBatch({
    required String documentId,
    required List<Map<String, dynamic>> queries,
    int? maxTables,
    int? maxRows,
  }) async {
    final uri = _resolveUri('/documents/pdf/query');
    _guardWebMixedContent(uri);
    final sanitized = <Map<String, dynamic>>[];
    for (final item in queries.take(5)) {
      final q = (item['query'] ?? '').toString().trim();
      if (q.isEmpty) continue;
      sanitized.add({
        'query': q,
        if (item['page_numbers'] is List) 'page_numbers': item['page_numbers'],
        if (item['max_tables'] != null) 'max_tables': item['max_tables'],
        if (item['max_rows'] != null) 'max_rows': item['max_rows'],
      });
    }
    final response = await http.post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'document_id': documentId,
        if (maxTables != null) 'max_tables': maxTables,
        if (maxRows != null) 'max_rows': maxRows,
        'queries': sanitized,
      }),
    );
    final decoded = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        'Document batch query failed (${response.statusCode}): '
        '${_messageFromResponse(decoded, response.body)}',
      );
    }
    return decoded;
  }

  Uri _resolveUri(String path) {
    final trimmed = backendBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('$trimmed$path');
  }

  void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'Document backend URL uses HTTP while the app is running on HTTPS. '
        'Use an HTTPS document backend or run the app locally over HTTP.',
      );
    }
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Backend returned invalid JSON.');
  }

  String _messageFromResponse(Map<String, dynamic> decoded, String fallbackBody) {
    final detail = decoded['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    return fallbackBody.trim().isEmpty ? 'unknown error' : fallbackBody.trim();
  }
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is Map) {
      out.add(item.cast<String, dynamic>());
    }
  }
  return out;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
