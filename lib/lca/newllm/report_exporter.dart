import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
    Map<String, String> scenarioModelByName = const <String, String>{},
    String? generationRouteLabel,
    Map<String, Map<String, dynamic>> generationByModel =
        const <String, Map<String, dynamic>>{},
    DateTime? generatedAt,
  }) async {
    final createdAt = generatedAt ?? DateTime.now();
    final parsed = _ParsedLca.fromRaw(
      lcaResults,
      scenarioModelByName: scenarioModelByName,
    );
    final modelNames = scenarioModelByName.values
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final generationRows = _normalizeGenerationRows(generationByModel);
    final generationFailures = generationRows
        .where((row) => row.status.toLowerCase() != 'success')
        .length;
    final fontBundle = await _PdfFontBundle.load(
      _collectTextSamples(
        prompt: prompt,
        functionsUsed: functionsUsed,
        rawDeltasByScenario: rawDeltasByScenario,
        parsed: parsed,
        productSystemName: productSystemName,
        impactMethodName: impactMethodName,
        scenarioModelByName: scenarioModelByName,
        generationRouteLabel: generationRouteLabel,
        generationByModel: generationByModel,
      ),
    );
    final doc = pw.Document(
      theme: fontBundle.theme,
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
              if (modelNames.isNotEmpty) ...[
                pw.SizedBox(width: 10),
                _metricCard('Models', '${modelNames.length}'),
              ],
              if (generationRows.isNotEmpty) ...[
                pw.SizedBox(width: 10),
                _metricCard('LLM Failures', '$generationFailures'),
              ],
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
              _kvRow(
                'Generation route',
                _fallback(
                  generationRouteLabel,
                  modelNames.length > 1 ? 'Multi-model run' : 'Single model run',
                ),
              ),
              _kvRow(
                'Models in report',
                modelNames.isEmpty ? 'Not annotated' : modelNames.join(', '),
              ),
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
          pw.Text('LLM Generation Status', style: h2),
          pw.SizedBox(height: 6),
          _buildGenerationStatusTable(generationRows, mono),
          pw.SizedBox(height: 14),
          pw.Text('Scenario Change Summary', style: h2),
          pw.SizedBox(height: 6),
          _buildChangeSummaryTable(
            rawDeltasByScenario,
            mono,
            scenarioModelByName: scenarioModelByName,
          ),
          pw.SizedBox(height: 14),
          pw.Text('Detailed Scenario Changes', style: h2),
          pw.SizedBox(height: 6),
          ..._buildDetailedChangeTables(
            rawDeltasByScenario,
            mono,
            scenarioModelByName: scenarioModelByName,
          ),
          if (parsed.scenarios.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('LCA Result Status', style: h2),
            pw.SizedBox(height: 6),
            _buildLcaStatusTable(
              parsed,
              mono,
              includeModelColumn: modelNames.isNotEmpty,
            ),
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

  static Iterable<String> _collectTextSamples({
    required String prompt,
    required List<String> functionsUsed,
    required Map<String, List<Map<String, dynamic>>> rawDeltasByScenario,
    required _ParsedLca parsed,
    String? productSystemName,
    String? impactMethodName,
    required Map<String, String> scenarioModelByName,
    String? generationRouteLabel,
    required Map<String, Map<String, dynamic>> generationByModel,
  }) sync* {
    yield prompt;
    if (generationRouteLabel != null) {
      yield generationRouteLabel;
    }
    for (final fn in functionsUsed) {
      yield fn;
    }
    if (productSystemName != null) {
      yield productSystemName;
    }
    if (impactMethodName != null) {
      yield impactMethodName;
    }
    for (final entry in generationByModel.entries) {
      yield entry.key;
      for (final value in entry.value.values) {
        final text = value?.toString();
        if (text == null || text.isEmpty) continue;
        yield text;
      }
    }

    for (final entry in rawDeltasByScenario.entries) {
      yield entry.key;
      final model = scenarioModelByName[entry.key];
      if (model != null && model.trim().isNotEmpty) {
        yield model;
      }
      for (final change in entry.value) {
        for (final value in change.values) {
          final text = value?.toString();
          if (text == null || text.isEmpty) continue;
          yield text;
        }
      }
    }

    for (final method in parsed.methodNames) {
      yield method;
      final unit = parsed.methodUnits[method];
      if (unit != null && unit.trim().isNotEmpty) {
        yield unit;
      }
    }
    for (final scenario in parsed.scenarios) {
      yield scenario.name;
      if (scenario.error != null) {
        yield scenario.error!;
      }
      for (final warning in scenario.warnings) {
        yield warning;
      }
    }
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
    {required Map<String, String> scenarioModelByName}
  ) {
    final sorted = rawDeltasByScenario.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final includeModel = scenarioModelByName.isNotEmpty;
    final headers = <String>[
      'Scenario',
      if (includeModel) 'Model',
      'Number of changes',
    ];
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: mono,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      headers: headers,
      data: sorted
          .map(
            (e) => <String>[
              e.key,
              if (includeModel) _fallback(scenarioModelByName[e.key], '—'),
              e.value.length.toString(),
            ],
          )
          .toList(),
      columnWidths: includeModel
          ? const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(2),
            }
          : const {
              0: pw.FlexColumnWidth(4),
              1: pw.FlexColumnWidth(2),
            },
    );
  }

  static pw.Widget _buildGenerationStatusTable(
    List<_GenerationStatusRow> rows,
    pw.TextStyle mono,
  ) {
    if (rows.isEmpty) {
      return pw.Text(
        'No model-level generation status metadata was captured.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      );
    }
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: mono,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      headers: const [
        'Model',
        'Status',
        'Scenarios',
        'Reason / Error',
      ],
      data: rows
          .map(
            (row) => <String>[
              row.model,
              row.status,
              row.scenarioCount.toString(),
              row.detail.isEmpty ? '-' : row.detail,
            ],
          )
          .toList(),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(5),
      },
    );
  }

  static List<_GenerationStatusRow> _normalizeGenerationRows(
    Map<String, Map<String, dynamic>> generationByModel,
  ) {
    final rows = <_GenerationStatusRow>[];
    final modelNames = generationByModel.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final model in modelNames) {
      final raw = generationByModel[model] ?? const <String, dynamic>{};
      final status = (raw['status'] ?? 'unknown').toString().trim();
      final scenarioCount = _toInt(raw['scenario_count']);
      final reason = (raw['reason'] ?? '').toString().trim();
      final error = (raw['error'] ?? '').toString().trim();
      final requiredCapability =
          (raw['required_capability'] ?? '').toString().trim();
      final detailParts = <String>[
        if (reason.isNotEmpty) reason,
        if (error.isNotEmpty) error,
        if (requiredCapability.isNotEmpty)
          'required_capability: $requiredCapability',
      ];
      rows.add(
        _GenerationStatusRow(
          model: model,
          status: status.isEmpty ? 'unknown' : status,
          scenarioCount: scenarioCount,
          detail: detailParts.join(' | '),
        ),
      );
    }
    return rows;
  }

  static List<pw.Widget> _buildDetailedChangeTables(
    Map<String, List<Map<String, dynamic>>> rawDeltasByScenario,
    pw.TextStyle mono,
    {required Map<String, String> scenarioModelByName}
  ) {
    final sorted = rawDeltasByScenario.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final out = <pw.Widget>[];
    for (final entry in sorted) {
      final modelName = scenarioModelByName[entry.key];
      final headerText = (modelName == null || modelName.trim().isEmpty)
          ? entry.key
          : '${entry.key}  (${modelName.trim()})';
      out.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(
            headerText,
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
    {required bool includeModelColumn}
  ) {
    final headers = <String>[
      'Scenario',
      if (includeModelColumn) 'Model',
      'Status',
      'Methods',
      'Warnings/Error',
    ];
    return pw.TableHelper.fromTextArray(
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: mono,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
      headers: headers,
      data: parsed.scenarios.map((s) {
        final status = s.success ? 'Success' : 'Failed';
        final methodCount = s.scores.length.toString();
        final detail = s.success
            ? (s.warnings.isEmpty ? '-' : s.warnings.join(' | '))
            : _fallback(s.error, 'Unknown error');
        return <String>[
          s.name,
          if (includeModelColumn) _fallback(s.modelName, '—'),
          status,
          methodCount,
          detail,
        ];
      }).toList(),
      columnWidths: includeModelColumn
          ? const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(4),
            }
          : const {
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

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

class _GenerationStatusRow {
  final String model;
  final String status;
  final int scenarioCount;
  final String detail;

  const _GenerationStatusRow({
    required this.model,
    required this.status,
    required this.scenarioCount,
    required this.detail,
  });
}

class _PdfFontBundle {
  final pw.ThemeData theme;

  const _PdfFontBundle({required this.theme});

  static final Map<String, Future<_PdfFontBundle>> _cache = {};

  static Future<_PdfFontBundle> load(Iterable<String> textSamples) {
    final coverage = _ScriptCoverage.detect(textSamples);
    final key = coverage.cacheKey;
    return _cache.putIfAbsent(key, () => _build(coverage));
  }

  static Future<_PdfFontBundle> _build(_ScriptCoverage coverage) async {
    final base = await _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSans-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansRegular,
        ) ??
        pw.Font.helvetica();
    final bold = await _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSans-Bold.ttf',
          googleLoader: PdfGoogleFonts.notoSansBold,
        ) ??
        pw.Font.helveticaBold();
    final italic = await _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSans-Italic.ttf',
          googleLoader: PdfGoogleFonts.notoSansItalic,
        ) ??
        pw.Font.helveticaOblique();
    final boldItalic = await _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSans-BoldItalic.ttf',
          googleLoader: PdfGoogleFonts.notoSansBoldItalic,
        ) ??
        pw.Font.helveticaBoldOblique();
    final icons = await _loadAssetOrGoogle(
      assetPath: 'assets/fonts/MaterialIcons-Regular.otf',
      googleLoader: PdfGoogleFonts.materialIcons,
    );

    final fallbackLoads = <Future<pw.Font?>>[
      _loadAssetOrGoogle(
        assetPath: 'assets/fonts/NotoSansMath-Regular.ttf',
        googleLoader: PdfGoogleFonts.notoSansMathRegular,
      ),
      _loadAssetOrGoogle(
        assetPath: 'assets/fonts/NotoSansSymbols2-Regular.ttf',
        googleLoader: PdfGoogleFonts.notoSansSymbols2Regular,
      ),
      if (coverage.hasArabic)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansArabic-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansArabicRegular,
        ),
      if (coverage.hasDevanagari)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansDevanagari-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansDevanagariRegular,
        ),
      if (coverage.hasHebrew)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansHebrew-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansHebrewRegular,
        ),
      if (coverage.hasThai)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansThai-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansThaiRegular,
        ),
      if (coverage.hasCjk)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansSC-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansSCRegular,
        ),
      if (coverage.hasKana)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansJP-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansJPRegular,
        ),
      if (coverage.hasHangul)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoSansKR-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoSansKRRegular,
        ),
      if (coverage.hasEmoji)
        _loadAssetOrGoogle(
          assetPath: 'assets/fonts/NotoColorEmoji-Regular.ttf',
          googleLoader: PdfGoogleFonts.notoColorEmojiRegular,
        ),
    ];
    final loadedFallbacks = await Future.wait(fallbackLoads);
    final fallbacks = <pw.Font>[
      for (final font in loadedFallbacks)
        if (font != null) font,
    ];

    return _PdfFontBundle(
      theme: pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
        icons: icons ?? base,
        fontFallback: fallbacks,
      ),
    );
  }

  static Future<pw.Font?> _tryLoad(Future<pw.Font> Function() loader) async {
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Font?> _loadAssetFont(String assetPath) async {
    try {
      final bytes = await rootBundle.load(assetPath);
      return pw.Font.ttf(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<pw.Font?> _loadAssetOrGoogle({
    required String assetPath,
    required Future<pw.Font> Function() googleLoader,
  }) async {
    final local = await _loadAssetFont(assetPath);
    if (local != null) return local;
    return _tryLoad(googleLoader);
  }
}

class _ScriptCoverage {
  final bool hasArabic;
  final bool hasCjk;
  final bool hasDevanagari;
  final bool hasEmoji;
  final bool hasHangul;
  final bool hasHebrew;
  final bool hasKana;
  final bool hasThai;

  const _ScriptCoverage({
    required this.hasArabic,
    required this.hasCjk,
    required this.hasDevanagari,
    required this.hasEmoji,
    required this.hasHangul,
    required this.hasHebrew,
    required this.hasKana,
    required this.hasThai,
  });

  String get cacheKey => [
        hasArabic ? 'a1' : 'a0',
        hasCjk ? 'c1' : 'c0',
        hasDevanagari ? 'd1' : 'd0',
        hasEmoji ? 'e1' : 'e0',
        hasHangul ? 'h1' : 'h0',
        hasHebrew ? 'he1' : 'he0',
        hasKana ? 'k1' : 'k0',
        hasThai ? 't1' : 't0',
      ].join('-');

  static _ScriptCoverage detect(Iterable<String> textSamples) {
    var hasArabic = false;
    var hasCjk = false;
    var hasDevanagari = false;
    var hasEmoji = false;
    var hasHangul = false;
    var hasHebrew = false;
    var hasKana = false;
    var hasThai = false;

    for (final text in textSamples) {
      for (final rune in text.runes) {
        if (!hasArabic &&
            ((rune >= 0x0600 && rune <= 0x06FF) ||
                (rune >= 0x0750 && rune <= 0x077F) ||
                (rune >= 0x08A0 && rune <= 0x08FF))) {
          hasArabic = true;
          continue;
        }
        if (!hasDevanagari && rune >= 0x0900 && rune <= 0x097F) {
          hasDevanagari = true;
          continue;
        }
        if (!hasHebrew && rune >= 0x0590 && rune <= 0x05FF) {
          hasHebrew = true;
          continue;
        }
        if (!hasThai && rune >= 0x0E00 && rune <= 0x0E7F) {
          hasThai = true;
          continue;
        }
        if (!hasKana &&
            ((rune >= 0x3040 && rune <= 0x309F) ||
                (rune >= 0x30A0 && rune <= 0x30FF) ||
                (rune >= 0x31F0 && rune <= 0x31FF))) {
          hasKana = true;
          continue;
        }
        if (!hasHangul &&
            ((rune >= 0x1100 && rune <= 0x11FF) ||
                (rune >= 0x3130 && rune <= 0x318F) ||
                (rune >= 0xAC00 && rune <= 0xD7AF))) {
          hasHangul = true;
          continue;
        }
        if (!hasCjk &&
            ((rune >= 0x3400 && rune <= 0x4DBF) ||
                (rune >= 0x4E00 && rune <= 0x9FFF) ||
                (rune >= 0xF900 && rune <= 0xFAFF) ||
                (rune >= 0x20000 && rune <= 0x2A6DF))) {
          hasCjk = true;
          continue;
        }
        if (!hasEmoji && _isEmojiRune(rune)) {
          hasEmoji = true;
        }
      }
    }

    return _ScriptCoverage(
      hasArabic: hasArabic,
      hasCjk: hasCjk,
      hasDevanagari: hasDevanagari,
      hasEmoji: hasEmoji,
      hasHangul: hasHangul,
      hasHebrew: hasHebrew,
      hasKana: hasKana,
      hasThai: hasThai,
    );
  }

  static bool _isEmojiRune(int rune) {
    return (rune >= 0x1F300 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F);
  }
}

class _ScorePoint {
  final String name;
  final double value;
  _ScorePoint(this.name, this.value);
}

class _ScenarioLcaSummary {
  final String name;
  final String? modelName;
  final bool success;
  final String? error;
  final List<String> warnings;
  final Map<String, double> scores;

  const _ScenarioLcaSummary({
    required this.name,
    required this.modelName,
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

  factory _ParsedLca.fromRaw(
    Map<String, dynamic>? raw, {
    required Map<String, String> scenarioModelByName,
  }) {
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
            modelName: scenarioModelByName[name],
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
          modelName: scenarioModelByName[name],
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
