import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a professional PDF report for LLM scenarios and LCA outputs.
class ReportExporter {
  static const _reportTitle = 'EarlyLCA Scenario Analysis Report';

  /// Builds the report and returns PDF bytes.
  static Future<Uint8List> buildPdf({
    required String prompt,
    required List<String> functionsUsed,
    required Map<String, List<Map<String, dynamic>>> rawDeltasByScenario,
    required Map<String, Uint8List> graphPngByScenario,
    Map<String, Uint8List> resultGraphPngByMethod = const {},
    Map<String, dynamic>? lcaResults,
    String? productSystemName,
    String? impactMethodName,
    DateTime? generatedAt,
  }) async {
    final createdAt = generatedAt ?? DateTime.now();
    final parsed = _ParsedLca.fromRaw(lcaResults);
    final doc = pw.Document(
      title: _reportTitle,
      author: 'EarlyLCA',
      creator: 'EarlyLCA LLM Scenario Generator',
    );

    final h1 = pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold);
    final h2 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);
    const muted = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
    const mono = pw.TextStyle(fontSize: 9);

    final totalChanges = rawDeltasByScenario.values.fold<int>(
      0,
      (sum, rows) => sum + rows.length,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber}',
            style: muted,
          ),
        ),
        build: (_) => [
          pw.Text(_reportTitle, style: h1),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated on ${_fmtDateTime(createdAt)}',
            style: muted,
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _metricCard('Scenarios', '${rawDeltasByScenario.length}'),
              pw.SizedBox(width: 10),
              _metricCard('Total Changes', '$totalChanges'),
              pw.SizedBox(width: 10),
              _metricCard('Impact Methods', '${parsed.methodNames.length}'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('Prompt', style: h2),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(5),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
            ),
            child: pw.Text(prompt),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Run Context', style: h2),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(5),
            },
            children: [
              _kvRow('Functions used',
                  functionsUsed.isEmpty ? 'None' : functionsUsed.join(', ')),
              _kvRow('Product system',
                  _fallback(productSystemName, 'Not selected')),
              _kvRow(
                  'Impact method', _fallback(impactMethodName, 'Not selected')),
              _kvRow(
                'LCA run in this report',
                parsed.scenarios.isEmpty
                    ? 'No'
                    : 'Yes (${parsed.successCount}/${parsed.scenarios.length} successful)',
              ),
              _kvRow(
                'Result graph snapshots',
                resultGraphPngByMethod.isEmpty
                    ? 'No'
                    : '${resultGraphPngByMethod.length} captured',
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('Scenario Change Summary', style: h2),
          pw.SizedBox(height: 6),
          _buildChangeSummaryTable(rawDeltasByScenario, mono),
          pw.SizedBox(height: 14),
          pw.Text('Detailed Scenario Changes', style: h2),
          pw.SizedBox(height: 6),
          ..._buildDetailedChangeTables(rawDeltasByScenario, mono),
          if (parsed.scenarios.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('LCA Result Status', style: h2),
            pw.SizedBox(height: 6),
            _buildLcaStatusTable(parsed, mono),
            pw.SizedBox(height: 14),
            pw.Text('Impact Score Matrix', style: h2),
            pw.SizedBox(height: 6),
            _buildImpactMatrix(parsed, mono),
            pw.SizedBox(height: 14),
            pw.Text('Method Comparison Charts', style: h2),
            pw.SizedBox(height: 6),
            ...parsed.methodNames.map((m) => _buildMethodComparison(m, parsed)),
          ] else ...[
            pw.SizedBox(height: 14),
            pw.Text('LCA Results', style: h2),
            pw.SizedBox(height: 6),
            pw.Text(
              'No LCA result payload is available yet. Run LCA and export again to include result tables and comparison charts.',
              style: muted,
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Text('Process Diagrams', style: h2),
          pw.SizedBox(height: 6),
          pw.Text(
            graphPngByScenario.isEmpty
                ? 'No process diagram snapshots were captured.'
                : 'Diagram pages are attached after this summary section.',
            style: muted,
          ),
          pw.SizedBox(height: 12),
          pw.Text('Result Graph Snapshots', style: h2),
          pw.SizedBox(height: 6),
          pw.Text(
            resultGraphPngByMethod.isEmpty
                ? 'No on-screen result graph snapshots were captured. '
                    'The method comparison charts above are included.'
                : 'Result graph pages are attached after this summary section.',
            style: muted,
          ),
        ],
      ),
    );

    final sortedGraphEntries = graphPngByScenario.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    for (final entry in sortedGraphEntries) {
      final image = pw.MemoryImage(entry.value);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Process Diagram - ${entry.key}',
                style: h2.copyWith(fontSize: 16),
              ),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: pw.Container(
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                  ),
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sortedMethodGraphEntries = resultGraphPngByMethod.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    for (final entry in sortedMethodGraphEntries) {
      final image = pw.MemoryImage(entry.value);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Result Graph - ${entry.key}',
                style: h2.copyWith(fontSize: 16),
              ),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: pw.Container(
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                  ),
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static pw.TableRow _kvRow(String k, String v) {
    return pw.TableRow(
      children: [
        pw.Container(
          color: PdfColors.grey100,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: pw.Text(
            k,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    );
  }

  static pw.Widget _metricCard(String title, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: pw.BoxDecoration(
          color: PdfColors.blue50,
          borderRadius: pw.BorderRadius.circular(5),
          border: pw.Border.all(color: PdfColors.blue200, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColors.blue900,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 15,
                color: PdfColors.blue900,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildChangeSummaryTable(
    Map<String, List<Map<String, dynamic>>> rawDeltasByScenario,
    pw.TextStyle mono,
  ) {
    final sorted = rawDeltasByScenario.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: mono,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      headers: const ['Scenario', 'Number of changes'],
      data: sorted
          .map(
            (e) => <String>[
              e.key,
              e.value.length.toString(),
            ],
          )
          .toList(),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(2),
      },
    );
  }

  static List<pw.Widget> _buildDetailedChangeTables(
    Map<String, List<Map<String, dynamic>>> rawDeltasByScenario,
    pw.TextStyle mono,
  ) {
    final sorted = rawDeltasByScenario.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final out = <pw.Widget>[];
    for (final entry in sorted) {
      out.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(
            entry.key,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
      if (entry.value.isEmpty) {
        out.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text('(no changes)',
                style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
          ),
        );
        continue;
      }
      out.add(
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          headerStyle:
              pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: mono,
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.45),
          headers: const ['Target', 'Field', 'New Value'],
          data: entry.value.map((c) {
            final field = (c['field'] ?? '(field missing)').toString();
            final target = c.containsKey('process_id')
                ? c['process_id'].toString()
                : c.containsKey('flow_id')
                    ? c['flow_id'].toString()
                    : field.startsWith('parameters.global.')
                        ? '(global)'
                        : '(unknown)';
            return <String>[
              target,
              field,
              (c['new_value'] ?? '-').toString(),
            ];
          }).toList(),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(4),
            2: pw.FlexColumnWidth(2),
          },
        ),
      );
      out.add(pw.SizedBox(height: 10));
    }
    return out;
  }

  static pw.Widget _buildLcaStatusTable(
    _ParsedLca parsed,
    pw.TextStyle mono,
  ) {
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: mono,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      headers: const ['Scenario', 'Status', 'Methods', 'Warnings/Error'],
      data: parsed.scenarios.map((s) {
        final status = s.success ? 'Success' : 'Failed';
        final methodCount = s.scores.length.toString();
        final detail = s.success
            ? (s.warnings.isEmpty ? '-' : s.warnings.join(' | '))
            : _fallback(s.error, 'Unknown error');
        return <String>[s.name, status, methodCount, detail];
      }).toList(),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(4),
      },
    );
  }

  static pw.Widget _buildImpactMatrix(
    _ParsedLca parsed,
    pw.TextStyle mono,
  ) {
    if (parsed.methodNames.isEmpty) {
      return pw.Text(
        'No impact score entries were found.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      );
    }
    if (parsed.scenarios.isEmpty) {
      return pw.Text(
        'No scenarios are available for the score matrix.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      );
    }

    final headers = <String>[
      'Impact category',
      ...parsed.scenarios.map((s) => _shorten(s.name, 16)),
    ];
    final data = parsed.methodNames.map((method) {
      final label = _withUnit(method, parsed.methodUnits[method]);
      return <String>[
        label,
        ...parsed.scenarios.map((s) {
          if (!s.success) return '—';
          final v = s.scores[method];
          return v == null ? '—' : _fmtNum(v);
        }),
      ];
    }).toList();

    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(3),
      for (var i = 1; i < headers.length; i += 1)
        i: const pw.FlexColumnWidth(2),
    };

    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
      cellStyle: mono.copyWith(fontSize: 8.5),
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.45),
      headers: headers,
      data: data,
      columnWidths: widths,
      cellAlignments: {
        for (var i = 1; i < headers.length; i += 1) i: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _buildMethodComparison(String method, _ParsedLca parsed) {
    final points = <_ScorePoint>[];
    for (final s in parsed.scenarios) {
      if (!s.success) continue;
      final v = s.scores[method];
      if (v == null) continue;
      points.add(_ScorePoint(s.name, v));
    }
    if (points.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text(
          '$method: no numeric points available.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      );
    }

    points.sort((a, b) => a.value.compareTo(b.value));
    final bestName = points.first.name;
    final maxAbs = points.fold<double>(
      0,
      (m, p) => p.value.abs() > m ? p.value.abs() : m,
    );
    final denom = maxAbs <= 0 ? 1.0 : maxAbs;

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _withUnit(method, parsed.methodUnits[method]),
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          ...points.map((p) {
            final ratio = (p.value.abs() / denom).clamp(0.0, 1.0);
            final barColor =
                p.name == bestName ? PdfColors.green500 : PdfColors.blue500;
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 92,
                    child: pw.Text(
                      _shorten(p.name, 24),
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                  pw.Container(
                    width: 220,
                    height: 9,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                    child: pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Container(
                        width: 220 * ratio,
                        decoration: pw.BoxDecoration(
                          color: barColor,
                          borderRadius: pw.BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.SizedBox(
                    width: 78,
                    child: pw.Text(
                      _fmtNum(p.value),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 8.5),
                    ),
                  ),
                ],
              ),
            );
          }),
          pw.Text(
            'Best (lowest): $bestName',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static String _fmtDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  static String _fmtNum(double value) {
    final abs = value.abs();
    if (abs >= 1000000 || (abs > 0 && abs < 0.0001)) {
      return value.toStringAsExponential(3);
    }
    if (abs >= 1000) return value.toStringAsFixed(2);
    if (abs >= 1) return value.toStringAsFixed(4);
    return value.toStringAsPrecision(5);
  }

  static String _fallback(String? value, String fallback) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? fallback : v;
  }

  static String _shorten(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    if (maxChars < 4) return text.substring(0, maxChars);
    return '${text.substring(0, maxChars - 1)}…';
  }

  static String _withUnit(String method, String? unit) {
    final cleaned = unit?.trim() ?? '';
    if (cleaned.isEmpty) return method;
    return '$method ($cleaned)';
  }
}

class _ScorePoint {
  final String name;
  final double value;
  _ScorePoint(this.name, this.value);
}

class _ScenarioLcaSummary {
  final String name;
  final bool success;
  final String? error;
  final List<String> warnings;
  final Map<String, double> scores;

  const _ScenarioLcaSummary({
    required this.name,
    required this.success,
    required this.error,
    required this.warnings,
    required this.scores,
  });
}

class _ParsedLca {
  final List<_ScenarioLcaSummary> scenarios;
  final List<String> methodNames;
  final Map<String, String> methodUnits;

  const _ParsedLca({
    required this.scenarios,
    required this.methodNames,
    required this.methodUnits,
  });

  int get successCount => scenarios.where((s) => s.success).length;

  factory _ParsedLca.fromRaw(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return const _ParsedLca(
        scenarios: [],
        methodNames: [],
        methodUnits: {},
      );
    }

    final scenarios = <_ScenarioLcaSummary>[];
    final methodNames = <String>{};
    final methodUnits = <String, String>{};

    final names = raw.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in names) {
      final payload = raw[name];
      if (payload is! Map) {
        scenarios.add(
          _ScenarioLcaSummary(
            name: name,
            success: false,
            error: 'Invalid result payload format.',
            warnings: const [],
            scores: const {},
          ),
        );
        continue;
      }

      final map = Map<String, dynamic>.from(payload);
      final success = map['success'] == true;
      final error = map['error']?.toString();
      final result = map['result'];
      final scores = <String, double>{};
      final warnings = <String>[];

      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        final rawScores = resultMap['scores'];
        if (rawScores is Map) {
          for (final entry in rawScores.entries) {
            final parsed = _toDouble(entry.value);
            if (parsed == null) continue;
            final method = entry.key.toString();
            scores[method] = parsed;
            methodNames.add(method);
            final existingUnit = methodUnits[method];
            if (existingUnit == null || existingUnit.trim().isEmpty) {
              final detected = _extractUnitForMethod(resultMap, method);
              if (detected != null && detected.trim().isNotEmpty) {
                methodUnits[method] = detected;
              }
            }
          }
        }
        final rawWarnings = resultMap['warnings'];
        if (rawWarnings is List) {
          for (final w in rawWarnings) {
            final text = w.toString().trim();
            if (text.isEmpty) continue;
            warnings.add(text);
          }
        }
      }

      scenarios.add(
        _ScenarioLcaSummary(
          name: name,
          success: success,
          error: error,
          warnings: warnings,
          scores: scores,
        ),
      );
    }

    final methods = methodNames.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _ParsedLca(
      scenarios: scenarios,
      methodNames: methods,
      methodUnits: methodUnits,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static String? _extractUnitForMethod(
    Map<String, dynamic> resultMap,
    String method,
  ) {
    for (final key in const [
      'score_units',
      'method_units',
      'unit_by_method',
      'units',
    ]) {
      final raw = resultMap[key];
      if (raw is! Map) continue;

      final map = raw.cast<dynamic, dynamic>();
      final direct = map[method];
      final directUnit = _sanitizeUnit(direct?.toString());
      if (directUnit != null) return directUnit;

      final needle = method.toLowerCase().trim();
      for (final entry in map.entries) {
        if (entry.key.toString().toLowerCase().trim() != needle) continue;
        final unit = _sanitizeUnit(entry.value?.toString());
        if (unit != null) return unit;
      }
    }

    final unit = _sanitizeUnit(resultMap['unit']?.toString());
    if (unit != null) {
      final scores = resultMap['scores'];
      if (scores is Map && scores.length == 1) {
        return unit;
      }
    }
    return null;
  }

  static String? _sanitizeUnit(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'null' || lower == 'none' || lower == 'n/a') {
      return null;
    }
    return text;
  }
}
