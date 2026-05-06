import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class UncertaintyReportExporter {
  static const String _title = 'Uncertainty Propagation Report';

  static Future<Uint8List> buildPdf({
    required Map<String, dynamic> job,
    required Map<String, dynamic> payload,
    required String userPrompt,
    DateTime? generatedAt,
  }) async {
    final theme = await _loadTheme();
    final logo = await _loadLogo();
    final createdAt = generatedAt ?? DateTime.now();
    final result = job['result'] is Map
        ? Map<String, dynamic>.from(job['result'] as Map)
        : const <String, dynamic>{};
    final parameters =
        (result['parameters'] as List?)?.whereType<Map>().toList() ?? const [];
    final impactSummaries =
        (result['impact_summaries'] as List?)?.whereType<Map>().toList() ??
            const [];
    final warnings =
        (result['warnings'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];

    final doc = pw.Document(
      theme: theme,
      title: _title,
      author: 'EarlyLCA',
      creator: 'EarlyLCA Uncertainty Propagation',
    );

    final h1 = pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold);
    final h2 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);
    const body = pw.TextStyle(fontSize: 10.5);
    const muted = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber}', style: muted),
        ),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.SizedBox(width: 34, height: 34, child: pw.Image(logo)),
              if (logo != null) pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_title, style: h1),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated on ${_formatDateTime(createdAt)}',
                      style: muted,
                    ),
                  ],
                ),
              ),
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
              border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Text(
              userPrompt.trim().isEmpty ? 'Not supplied' : userPrompt.trim(),
              style: body,
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Run Context', style: h2),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(5),
            },
            children: [
              _kvRow(
                'Status',
                (job['status'] ?? 'unknown').toString(),
              ),
              _kvRow(
                'Product system',
                (payload['product_system'] ?? '').toString(),
              ),
              _kvRow(
                'Impact method',
                (payload['impact_method'] ?? '').toString(),
              ),
              _kvRow(
                'Sampling method',
                ((payload['sampling'] as Map?)?['method'] ?? '').toString(),
              ),
              _kvRow(
                'Requested / successful / failed',
                '${result['n_requested'] ?? ((payload['sampling'] as Map?)?['n_samples'] ?? 0)} / '
                    '${result['n_successful'] ?? 0} / ${result['n_failed'] ?? 0}',
              ),
              _kvRow(
                'Sample results path',
                (result['sample_results_path'] ?? '').toString(),
              ),
              _kvRow(
                'Report path',
                (result['report_path'] ?? '').toString(),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('Parameter Uncertainty', style: h2),
          pw.SizedBox(height: 6),
          _table(
            headers: const ['Scope', 'Parameter', 'Distribution', 'Specification'],
            rows: [
              for (final raw in parameters)
                _parameterRow(Map<String, dynamic>.from(raw)),
            ],
            emptyHint: 'No parameter uncertainty rows were recorded.',
          ),
          pw.SizedBox(height: 14),
          pw.Text('Impact Summaries', style: h2),
          pw.SizedBox(height: 6),
          _table(
            headers: const [
              'Impact category',
              'Unit',
              'Mean',
              'SD',
              'Min',
              'P5',
              'P50',
              'P95',
              'Max',
            ],
            rows: [
              for (final raw in impactSummaries)
                _impactSummaryRow(Map<String, dynamic>.from(raw)),
            ],
            emptyHint: 'No successful impact summaries were recorded.',
          ),
          if (warnings.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Warnings', style: h2),
            pw.SizedBox(height: 6),
            ...warnings.map(
              (warning) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text('• $warning', style: body),
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'Uncertainty distributions were supplied by the user or source document. '
            'The framework did not infer uncertainty distributions automatically.',
            style: body,
          ),
        ],
      ),
    );

    return doc.save();
  }

  static List<String> _parameterRow(Map<String, dynamic> parameter) {
    final context = parameter['context'];
    String label = (parameter['name'] ?? '').toString();
    if (context is Map) {
      final processName = (context['process_name'] ?? '').toString().trim();
      final processId = (context['process_id'] ?? '').toString().trim();
      final prefix = processName.isNotEmpty ? processName : processId;
      if (prefix.isNotEmpty) {
        label = '$prefix: $label';
      }
    }
    final details = <String>[];
    for (final key in [
      'minimum',
      'mode',
      'maximum',
      'mean',
      'sd',
      'geomMean',
      'geomSd',
      'lower_bound',
      'upper_bound',
    ]) {
      if (parameter.containsKey(key)) {
        details.add('$key=${parameter[key]}');
      }
    }
    return [
      (parameter['scope'] ?? '').toString(),
      label,
      (parameter['distributionType'] ?? '').toString(),
      details.join(', '),
    ];
  }

  static List<String> _impactSummaryRow(Map<String, dynamic> summary) {
    return [
      (summary['impact_category'] ?? '').toString(),
      (summary['unit'] ?? '').toString(),
      _fmt(summary['mean']),
      _fmt(summary['sd']),
      _fmt(summary['min']),
      _fmt(summary['p5']),
      _fmt(summary['p50']),
      _fmt(summary['p95']),
      _fmt(summary['max']),
    ];
  }

  static pw.TableRow _kvRow(String key, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(
            key,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(value.isEmpty ? 'n/a' : value, style: const pw.TextStyle(fontSize: 10)),
        ),
      ],
    );
  }

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required String emptyHint,
  }) {
    if (rows.isEmpty) {
      return pw.Text(emptyHint, style: const pw.TextStyle(fontSize: 10));
    }
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9.5,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      cellPadding: const pw.EdgeInsets.all(6),
    );
  }

  static String _fmt(dynamic value) {
    final number = (value as num?)?.toDouble();
    if (number == null || !number.isFinite) return 'n/a';
    if (number == 0) return '0';
    final absValue = number.abs();
    if (absValue >= 1000 || absValue < 0.001) {
      return number.toStringAsExponential(3);
    }
    return number.toStringAsPrecision(6);
  }

  static String _formatDateTime(DateTime value) {
    final two = (int item) => item.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static Future<pw.ThemeData> _loadTheme() async {
    try {
      final base = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      final italic = await PdfGoogleFonts.notoSansItalic();
      final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();
      return pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      );
    } catch (_) {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      );
    }
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}
