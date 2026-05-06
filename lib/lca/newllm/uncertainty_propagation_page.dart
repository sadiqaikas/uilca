import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'pdf_download.dart';
import 'uncertainty_report_exporter.dart';

class UncertaintyPropagationPage extends StatefulWidget {
  final Map<String, dynamic>? openLcaProductSystem;
  final String? userPrompt;
  final Map<String, dynamic>? initialPayload;
  final bool autoStart;

  const UncertaintyPropagationPage({
    super.key,
    this.openLcaProductSystem,
    this.userPrompt,
    this.initialPayload,
    this.autoStart = false,
  });

  @override
  State<UncertaintyPropagationPage> createState() =>
      _UncertaintyPropagationPageState();
}

class _UncertaintyPropagationPageState
    extends State<UncertaintyPropagationPage> {
  static const String _openLcaBackendBaseUrl = String.fromEnvironment(
    'OPENLCA_BACKEND_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );
  static const String _openLcaIpcUrl = String.fromEnvironment(
    'OPENLCA_IPC_URL',
    defaultValue: 'http://localhost:8080',
  );

  final List<Map<String, dynamic>> _clientEvents = [];

  Timer? _pollTimer;
  String? _jobId;
  Map<String, dynamic>? _job;
  Map<String, dynamic>? _activePayload;
  bool _isStarting = false;
  bool _isExportingCsv = false;
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    final payload = widget.initialPayload;
    if (payload != null) {
      _activePayload = _deepCopyMap(payload);
      _appendClientEvent(
        'llm_handoff',
        'Received uncertainty propagation payload from the LLM.',
        details: {
          'sample_count': ((payload['sampling'] as Map?)?['n_samples']),
          'parameter_count': ((payload['parameters'] as List?) ?? const []).length,
          'impact_category_count':
              ((payload['impact_categories'] as List?) ?? const []).length,
        },
      );
    }
    if (widget.autoStart && payload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRunWithPayload(payload);
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _guardWebMixedContent(Uri uri) {
    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      throw Exception(
        'The app is running over HTTPS but the OpenLCA backend URL is HTTP.',
      );
    }
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> input) {
    final decoded = jsonDecode(jsonEncode(input));
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }

  void _appendClientEvent(
    String stage,
    String message, {
    Map<String, dynamic>? details,
  }) {
    _clientEvents.add({
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'stage': stage,
      'message': message,
      'source': 'ui',
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }

  Future<void> _startRunWithPayload(Map<String, dynamic> payload) async {
    final normalizedPayload = _deepCopyMap(payload);
    setState(() {
      _isStarting = true;
      _job = null;
      _jobId = null;
      _activePayload = normalizedPayload;
    });
    _appendClientEvent(
      'submit',
      'Submitting uncertainty propagation run to the OpenLCA backend.',
      details: {
        'sample_count':
            ((normalizedPayload['sampling'] as Map?)?['n_samples']) ?? 250,
        'sampling_method':
            ((normalizedPayload['sampling'] as Map?)?['method']) ??
                'latin_hypercube',
      },
    );
    try {
      final uri = Uri.parse(
        '$_openLcaBackendBaseUrl/openlca/uncertainty-propagation/start',
      );
      _guardWebMixedContent(uri);
      final response = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          ...normalizedPayload,
          'ipc_url': (normalizedPayload['ipc_url'] ?? _openLcaIpcUrl).toString(),
          'user_prompt': (widget.userPrompt ?? '').trim(),
        }),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Uncertainty start failed ${response.statusCode}: ${response.body}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Uncertainty start returned invalid JSON.');
      }
      final jobId = (decoded['job_id'] ?? '').toString().trim();
      if (jobId.isEmpty) {
        throw Exception('Uncertainty propagation did not return a job id.');
      }
      setState(() => _jobId = jobId);
      _appendClientEvent(
        'accepted',
        'Backend accepted the uncertainty propagation run.',
        details: {'job_id': jobId},
      );
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollJob());
      await _pollJob();
    } catch (e) {
      _appendClientEvent(
        'submit_failed',
        'Failed to start uncertainty propagation.',
        details: {'error': e.toString()},
      );
      _showSnack('Uncertainty propagation failed to start: $e');
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _pollJob() async {
    final jobId = _jobId;
    if (jobId == null || jobId.isEmpty) return;
    try {
      final uri = Uri.parse(
        '$_openLcaBackendBaseUrl/openlca/uncertainty-propagation/$jobId',
      );
      _guardWebMixedContent(uri);
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) {
        throw Exception('Polling failed ${response.statusCode}: ${response.body}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      if (!mounted) return;
      setState(() => _job = decoded);
      final status = (decoded['status'] ?? '').toString().trim();
      if (status == 'completed' || status == 'failed' || status == 'cancelled') {
        _pollTimer?.cancel();
      }
    } catch (e) {
      _appendClientEvent(
        'poll_failed',
        'Polling the uncertainty job failed.',
        details: {'error': e.toString()},
      );
      _showSnack('Uncertainty propagation polling error: $e');
      _pollTimer?.cancel();
    }
  }

  Future<void> _cancelJob() async {
    final jobId = _jobId;
    if (jobId == null || jobId.isEmpty) return;
    final uri = Uri.parse(
      '$_openLcaBackendBaseUrl/openlca/uncertainty-propagation/$jobId/cancel',
    );
    _guardWebMixedContent(uri);
    await http.post(uri, headers: const {'Accept': 'application/json'});
    await _pollJob();
  }

  void _showPayload() {
    final payload = _activePayload ?? const <String, dynamic>{};
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Uncertainty payload'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(payload),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, dynamic>? _result() {
    final raw = _job?['result'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  List<Map<String, dynamic>> _sampleMatrix() {
    final raw = _result()?['sample_matrix'];
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
  }

  List<Map<String, dynamic>> _executionEvents() {
    final merged = <Map<String, dynamic>>[
      ..._clientEvents.map((event) => Map<String, dynamic>.from(event)),
    ];
    final rawJobEvents = _job?['events'];
    if (rawJobEvents is List) {
      merged.addAll(
        rawJobEvents
            .whereType<Map>()
            .map((event) => Map<String, dynamic>.from(event)),
      );
    }
    merged.sort((a, b) {
      final left = ((a['timestamp'] as num?) ?? 0).toDouble();
      final right = ((b['timestamp'] as num?) ?? 0).toDouble();
      return left.compareTo(right);
    });
    return merged;
  }

  String _formatNumber(dynamic value) {
    final number = (value as num?)?.toDouble();
    if (number == null || !number.isFinite) return value?.toString() ?? 'n/a';
    if (number == 0) return '0';
    final absValue = number.abs();
    if (absValue >= 1000 || absValue < 0.001) {
      return number.toStringAsExponential(3);
    }
    return number.toStringAsPrecision(6);
  }

  String _formatEventTime(dynamic rawTimestamp) {
    final seconds = (rawTimestamp as num?)?.toDouble();
    if (seconds == null || !seconds.isFinite) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: false,
    );
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  String _formatEventDetails(Map<String, dynamic> event) {
    final details = event['details'];
    if (details is! Map || details.isEmpty) return '';
    return '\n${const JsonEncoder.withIndent('  ').convert(details)}';
  }

  Future<void> _exportCsv() async {
    final rows = _sampleMatrix();
    if (rows.isEmpty || _isExportingCsv) return;
    setState(() => _isExportingCsv = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(_buildCsv(rows)));
      await downloadFile(
        bytes: bytes,
        filename: 'uncertainty_propagation_results.csv',
        mimeType: 'text/csv;charset=utf-8',
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingCsv = false);
      }
    }
  }

  Future<void> _exportPdf() async {
    final status = (_job?['status'] ?? '').toString().trim();
    if (_job == null ||
        _activePayload == null ||
        _isExportingPdf ||
        status != 'completed') {
      return;
    }
    setState(() => _isExportingPdf = true);
    try {
      final bytes = await UncertaintyReportExporter.buildPdf(
        job: _job!,
        payload: _activePayload!,
        userPrompt: widget.userPrompt ?? '',
        generatedAt: DateTime.now(),
      );
      await downloadPdf(
        bytes: bytes,
        filename: 'uncertainty_propagation_report.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Uncertainty propagation PDF exported as uncertainty_propagation_report.pdf',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uncertainty PDF export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  String _buildCsv(List<Map<String, dynamic>> rows) {
    final parameterColumns = <String>[];
    final impactColumns = <String>[];
    final seenParameterColumns = <String>{};
    final seenImpactColumns = <String>{};

    for (final row in rows) {
      final parameters = (row['parameter_values'] as List?) ?? const [];
      for (final raw in parameters.whereType<Map>()) {
        final parameter = Map<String, dynamic>.from(raw);
        final label = _parameterLabel(parameter);
        if (seenParameterColumns.add(label)) {
          parameterColumns.add(label);
        }
      }
      final impacts = row['lcia_results'];
      if (impacts is Map) {
        for (final key in impacts.keys) {
          final label = key.toString();
          if (seenImpactColumns.add(label)) {
            impactColumns.add(label);
          }
        }
      }
    }

    final lines = <String>[
      [
        'sample_id',
        'run_status',
        'error_message',
        ...parameterColumns,
        ...impactColumns,
      ].map(_csvEscape).join(','),
    ];

    for (final row in rows) {
      final parameterValues = <String, String>{};
      final parameters = (row['parameter_values'] as List?) ?? const [];
      for (final raw in parameters.whereType<Map>()) {
        final parameter = Map<String, dynamic>.from(raw);
        parameterValues[_parameterLabel(parameter)] =
            _formatNumber(parameter['value']);
      }
      final impacts = <String, String>{};
      final rawImpacts = row['lcia_results'];
      if (rawImpacts is Map) {
        for (final entry in rawImpacts.entries) {
          if (entry.value is Map) {
            final map = Map<String, dynamic>.from(entry.value as Map);
            impacts[entry.key.toString()] = _formatNumber(map['value']);
          }
        }
      }
      lines.add(
        [
          '${row['sample_id'] ?? ''}',
          '${row['run_status'] ?? ''}',
          '${row['error_message'] ?? ''}',
          ...parameterColumns.map((label) => parameterValues[label] ?? ''),
          ...impactColumns.map((label) => impacts[label] ?? ''),
        ].map(_csvEscape).join(','),
      );
    }

    return '${lines.join('\n')}\n';
  }

  String _parameterLabel(Map<String, dynamic> parameter) {
    final scope = (parameter['scope'] ?? '').toString().trim();
    final name = (parameter['name'] ?? '').toString().trim();
    if (scope == 'global') return name;
    final context = parameter['context'];
    if (context is Map) {
      final processName = (context['process_name'] ?? '').toString().trim();
      final processId = (context['process_id'] ?? '').toString().trim();
      return '${processName.isNotEmpty ? processName : processId} / $name';
    }
    return name;
  }

  String _csvEscape(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final escaped = normalized.replaceAll('"', '""');
    if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Widget _metricCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.blueGrey.shade700)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final result = _result();
    final status = (job?['status'] ?? 'not started').toString().trim();
    final parameters =
        (result?['parameters'] as List?)?.whereType<Map>().toList() ?? const [];
    final impactSummaries = (result?['impact_summaries'] as List?)
            ?.whereType<Map>()
            .toList() ??
        const [];
    final warnings =
        (result?['warnings'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final sampleResultsPath =
        (result?['sample_results_path'] ?? '').toString().trim();
    final reportPath = (result?['report_path'] ?? '').toString().trim();
    final reportHtmlPath =
        (result?['report_html_path'] ?? '').toString().trim();
    final reportPdfPath =
        (result?['report_pdf_path'] ?? '').toString().trim();
    final logPath =
        ((result?['log_path'] ?? job?['log_path']) ?? '').toString().trim();
    final events = _executionEvents();
    final canExportArtifacts = status == 'completed' && result != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Uncertainty Propagation'),
        actions: [
          IconButton(
            onPressed: _activePayload == null ? null : _showPayload,
            icon: const Icon(Icons.code),
            tooltip: 'Show payload',
          ),
          if (status == 'queued' || status == 'running')
            IconButton(
              onPressed: _cancelJob,
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Cancel run',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_activePayload != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Product system: ${(widget.openLcaProductSystem?['name'] ?? _activePayload?['product_system'] ?? '').toString()}',
              ),
            ),
          Row(
            children: [
              _metricCard('Status', status),
              const SizedBox(width: 12),
              _metricCard(
                'Requested',
                '${result?['n_requested'] ?? ((_activePayload?['sampling'] as Map?)?['n_samples'] ?? '0')}',
              ),
              const SizedBox(width: 12),
              _metricCard('Successful', '${result?['n_successful'] ?? '0'}'),
              const SizedBox(width: 12),
              _metricCard('Failed', '${result?['n_failed'] ?? '0'}'),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: 'Run Summary',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sampling: ${((_activePayload?['sampling'] as Map?)?['method'] ?? '').toString()}',
                ),
                const SizedBox(height: 6),
                Text(
                  'Impact method: ${(_activePayload?['impact_method'] ?? '').toString()}',
                ),
                if (sampleResultsPath.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText('Sample results path: $sampleResultsPath'),
                ],
                if (reportPath.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText('Report path: $reportPath'),
                ],
                if (reportHtmlPath.isNotEmpty &&
                    reportHtmlPath != reportPath) ...[
                  const SizedBox(height: 6),
                  SelectableText('HTML report path: $reportHtmlPath'),
                ],
                if (reportPdfPath.isNotEmpty &&
                    reportPdfPath != reportPath) ...[
                  const SizedBox(height: 6),
                  SelectableText('PDF report path: $reportPdfPath'),
                ],
                if (logPath.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText('Trace log path: $logPath'),
                ],
                if (job?['error'] != null &&
                    (job?['error'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    'Error: ${(job?['error'] ?? '').toString().trim()}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Warnings',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: warnings
                    .map((warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $warning'),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (parameters.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Parameter Uncertainty',
              child: Column(
                children: parameters.map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  final label = (item['context'] is Map)
                      ? '${(((item['context'] as Map)['process_name'] ?? (item['context'] as Map)['process_id']) ?? '').toString()}: ${(item['name'] ?? '').toString()}'
                      : (item['name'] ?? '').toString();
                  final distribution =
                      (item['distributionType'] ?? '').toString().trim();
                  final detail = Map<String, dynamic>.from(item)
                    ..removeWhere(
                      (key, _) => {
                        'scope',
                        'context',
                        'name',
                        'distributionType',
                      }.contains(key),
                    );
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: Text(
                      '$distribution • ${detail.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (impactSummaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Impact Summaries',
              child: Column(
                children: impactSummaries.map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  final percentiles = item['percentiles'] is Map
                      ? Map<String, dynamic>.from(item['percentiles'] as Map)
                      : const <String, dynamic>{};
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text((item['impact_category'] ?? '').toString()),
                    subtitle: Text(
                      'mean=${_formatNumber(item['mean'])}, '
                      'sd=${_formatNumber(item['sd'])}, '
                      'min=${_formatNumber(item['min'])}, '
                      '${percentiles.entries.map((e) => '${e.key}=${_formatNumber(e.value)}').join(', ')}, '
                      'max=${_formatNumber(item['max'])}'
                      '${(item['unit'] ?? '').toString().trim().isEmpty ? '' : ' ${(item['unit'] ?? '').toString().trim()}'}',
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _sectionCard(
            title: 'Execution Events',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: events.isEmpty
                  ? const [Text('No execution events recorded yet.')]
                  : events
                      .take(events.length > 12 ? 12 : events.length)
                      .map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SelectableText(
                            '[${_formatEventTime(event['timestamp'])}] '
                            '${event['stage']}: ${event['message']}'
                            '${_formatEventDetails(event)}',
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _activePayload == null ? null : _showPayload,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Show Payload'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: !canExportArtifacts ||
                        _sampleMatrix().isEmpty ||
                        _isExportingCsv
                    ? null
                    : _exportCsv,
                icon: const Icon(Icons.download_outlined),
                label: Text(_isExportingCsv ? 'Exporting...' : 'Export CSV'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    !canExportArtifacts || _isExportingPdf ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(_isExportingPdf ? 'Exporting...' : 'Export PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
