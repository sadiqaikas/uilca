import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

class ReproBundleHelper {
  static Uint8List buildBundle({
    required String schemaVersion,
    required String readme,
    required Map<String, dynamic> summary,
    required Map<String, Uint8List> files,
    DateTime? generatedAt,
  }) {
    final createdAt = generatedAt ?? DateTime.now();
    final out = <String, Uint8List>{
      ...files,
      'README.md': utf8Bytes(readme),
      'manifest.json': Uint8List(0),
    };
    out['manifest.json'] = jsonBytes({
      'schema_version': schemaVersion,
      'generated_at': createdAt.toUtc().toIso8601String(),
      'summary': stableJsonValue(summary),
      'files': [
        for (final name in (out.keys.where((name) => name != 'manifest.json').toList()
              ..sort()))
          {
            'path': name,
            'bytes': out[name]!.length,
            'sha256': sha256.convert(out[name]!).toString(),
          },
      ],
    });
    out['checksums.sha256'] = utf8Bytes(_checksums(out));

    final archive = Archive();
    final names = out.keys.toList()..sort();
    for (final name in names) {
      final bytes = out[name]!;
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static Uint8List utf8Bytes(String value) =>
      Uint8List.fromList(utf8.encode(value));

  static Uint8List jsonBytes(Object? value) {
    const encoder = JsonEncoder.withIndent('  ');
    return utf8Bytes('${encoder.convert(stableJsonValue(value))}\n');
  }

  static Object? stableJsonValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): stableJsonValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(stableJsonValue).toList();
    }
    return value;
  }

  static String csv(List<List<String>> rows) {
    return rows.map((row) => row.map(_csvCell).join(',')).join('\n') + '\n';
  }

  static String _csvCell(String value) {
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _checksums(Map<String, Uint8List> files) {
    final names = files.keys.toList()..sort();
    return names
            .map((name) => '${sha256.convert(files[name]!).toString()}  $name')
            .join('\n') +
        '\n';
  }
}
