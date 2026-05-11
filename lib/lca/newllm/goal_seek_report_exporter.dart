import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

typedef GoalSeekParameterLabelBuilder =
    String Function(Map<String, dynamic> parameter);
typedef GoalSeekConstraintLabelBuilder =
    String Function(Map<String, dynamic> constraint);
typedef GoalSeekNumberFormatter = String Function(dynamic value);

class GoalSeekReportVariable {
  final String label;
  final String lower;
  final String upper;

  const GoalSeekReportVariable({
    required this.label,
    required this.lower,
    required this.upper,
  });
}

class GoalSeekReportConstraint {
  final String label;
  final String operator;
  final String target;

  const GoalSeekReportConstraint({
    required this.label,
    required this.operator,
    required this.target,
  });
}

class GoalSeekReportExporter {
  static const String _title = 'Goal-Seek Optimisation Report';

  static final PdfColor _ink = PdfColor.fromHex('#15323B');
  static final PdfColor _brand = PdfColor.fromHex('#5B9BD5');
  static final PdfColor _brandDark = PdfColor.fromHex('#2F6FA3');
  static final PdfColor _accent = PdfColor.fromHex('#7FAEDC');
  static final PdfColor _surface = PdfColor.fromHex('#F7FAFD');
  static final PdfColor _surfaceStrong = PdfColor.fromHex('#EAF2FB');
  static final PdfColor _line = PdfColor.fromHex('#D5E1EE');
  static final PdfColor _muted = PdfColor.fromHex('#60758A');
  static final PdfColor _success = PdfColor.fromHex('#18794E');
  static final PdfColor _successSoft = PdfColor.fromHex('#E7F6EC');
  static final PdfColor _danger = PdfColor.fromHex('#B42318');
  static final PdfColor _dangerSoft = PdfColor.fromHex('#FEECEC');
  static final PdfColor _warningSoft = PdfColor.fromHex('#FFF4E5');
  static const int _portraitTableRows = 12;
  static const int _portraitTextChars = 1800;

  static Future<Uint8List> buildPdf({
    required Map<String, dynamic> job,
    required List<GoalSeekReportVariable> variables,
    required List<GoalSeekReportConstraint> constraints,
    required String productSystemName,
    required String toolName,
    required String goalModeLabel,
    required String objectiveSummary,
    required String selectedImpactMethodSummary,
    required String userPrompt,
    required GoalSeekParameterLabelBuilder parameterLabelBuilder,
    required GoalSeekConstraintLabelBuilder constraintLabelBuilder,
    required GoalSeekNumberFormatter formatNumber,
    DateTime? generatedAt,
  }) async {
    final theme = await _loadTheme();
    final logo = await _loadLogo();
    final doc = pw.Document(
      theme: theme,
      title: _title,
      author: 'EarlyLCA',
      creator: 'EarlyLCA Goal Seek',
    );

    final createdAt = generatedAt ?? DateTime.now();
    final status = _asString(job['status'], fallback: 'unknown');
    final evaluations = _listOfMaps(job['evaluations']);
    final request = _mapOrNull(job['request']);
    final baseline = _mapOrNull(job['baseline']);
    final solverInitial = _mapOrNull(job['solver_initial']);
    final best = _mapOrNull(job['best']);
    final optimizer = _mapOrNull(job['optimizer']);
    final error = _asString(job['error']);
    final recordedPrompt = request?['prompt']?.toString() ?? '';
    final promptText =
        userPrompt.trim().isNotEmpty ? userPrompt : recordedPrompt;
    final feasibleCount =
        evaluations.where((evaluation) => evaluation['feasible'] == true).length;
    final warningCount = evaluations.fold<int>(
      0,
      (sum, evaluation) =>
          sum + _listOfDynamic(evaluation['warnings']).whereType<String>().length,
    );

    doc.addPage(
      _buildCoverPage(
        logo: logo,
        generatedAt: createdAt,
        status: status,
        productSystemName: productSystemName,
        goalModeLabel: goalModeLabel,
        objectiveSummary: objectiveSummary,
        selectedImpactMethodSummary: selectedImpactMethodSummary,
        evaluationCount: evaluations.length,
        feasibleCount: feasibleCount,
        warningCount: warningCount,
        toolName: toolName,
        best: best,
        baseline: baseline,
        solverInitial: solverInitial,
        formatNumber: formatNumber,
      ),
    );

    doc.addPage(
      _buildPortraitPage(
        title: 'Run Brief',
        description:
            'Summary of the optimisation run.',
        children: [
          _buildRunDetailsCard(
            status: status,
            toolName: toolName,
            productSystemName: productSystemName,
            goalModeLabel: goalModeLabel,
            objectiveSummary: objectiveSummary,
            selectedImpactMethodSummary: selectedImpactMethodSummary,
            evaluations: evaluations,
            feasibleCount: feasibleCount,
            formatNumber: formatNumber,
            baseline: baseline,
            solverInitial: solverInitial,
            best: best,
            generatedAt: createdAt,
            job: job,
            optimizer: optimizer,
          ),
        ],
      ),
    );

    doc.addPage(
      _buildPortraitPage(
        title: 'Optimisation Definition',
        description:
            'Core optimisation setup used for this run: objective, variables, and constraints.',
        children: [
          _panel(
            title: 'Objective',
            child: _kvTable([
              ['Mode', goalModeLabel],
              ['Objective', objectiveSummary],
              [
                'LCIA method(s)',
                selectedImpactMethodSummary.trim().isEmpty
                    ? 'Not resolved'
                    : selectedImpactMethodSummary.trim(),
              ],
            ]),
          ),
          _buildConfigurationCard(
            variables: variables,
            constraints: constraints,
          ),
        ],
      ),
    );

    _addPromptPages(doc, promptText: promptText);

    if (error.isNotEmpty) {
      doc.addPage(
        _buildPortraitPage(
          title: 'Failure Diagnostic',
          description:
              'Reported failure details from the optimisation run.',
          children: [
            _buildAlertCard('Failure Diagnostic', error),
          ],
        ),
      );
    }

    doc.addPage(
      _buildPortraitPage(
        title: 'Result Summary',
        description:
            'Summary of the reference case and the best feasible solution found.',
        children: [
          _buildResultSummaryCard(
            best: best,
            baseline: baseline,
            solverInitial: solverInitial,
            formatNumber: formatNumber,
            parameterLabelBuilder: parameterLabelBuilder,
            constraintLabelBuilder: constraintLabelBuilder,
          ),
        ],
      ),
    );

    return doc.save();
  }

  static void _addLongTextPages(
    pw.Document doc, {
    required String title,
    required String description,
    required String body,
    bool alert = false,
  }) {
    final cleaned = _cleanText(body);
    if (cleaned.isEmpty) return;
    final chunks = _chunkText(cleaned, _portraitTextChars);
    for (var i = 0; i < chunks.length; i += 1) {
      doc.addPage(
        _buildPortraitPage(
          title: chunks.length == 1 ? title : '$title ${i + 1}/${chunks.length}',
          description: description,
          children: [
            alert ? _buildAlertCard(title, chunks[i]) : _buildTextCard(title, chunks[i]),
          ],
        ),
      );
    }
  }

  static void _addPromptPages(
    pw.Document doc, {
    required String promptText,
  }) {
    final chunks = _chunkPromptText(promptText, _portraitTextChars);
    if (chunks.isEmpty) {
      doc.addPage(
        _buildPortraitPage(
          title: 'User Prompt',
          description: 'Exact prompt submitted for this optimisation run.',
          children: [
            _buildTextCard(
              'User prompt',
              'Prompt not recorded in the submitted optimization request.',
            ),
          ],
        ),
      );
      return;
    }

    for (var i = 0; i < chunks.length; i += 1) {
      doc.addPage(
        _buildPortraitPage(
          title: chunks.length == 1
              ? 'User Prompt'
              : 'User Prompt ${i + 1}/${chunks.length}',
          description: 'Exact prompt submitted for this optimisation run.',
          children: [
            _buildTextCard(
              'User prompt',
              chunks[i],
              preserveWhitespace: true,
            ),
          ],
        ),
      );
    }
  }

  static void _addConfigurationPages(
    pw.Document doc, {
    required List<GoalSeekReportVariable> variables,
    required List<GoalSeekReportConstraint> constraints,
  }) {
    final variableRows = [
      for (final variable in variables) [variable.label, variable.lower, variable.upper],
    ];
    final constraintRows = [
      for (final constraint in constraints)
        [constraint.label, constraint.operator, constraint.target],
    ];

    final variableChunks = variableRows.isEmpty
        ? [<List<String>>[]]
        : _chunk(variableRows, _portraitTableRows);
    for (var i = 0; i < variableChunks.length; i += 1) {
      doc.addPage(
        _buildPortraitPage(
          title: variableChunks.length == 1
              ? 'Variable Bounds'
              : 'Variable Bounds ${i + 1}/${variableChunks.length}',
          description:
              'Defined optimisation variable ranges.',
          children: [
            _panel(
              title: 'Variables',
              child: _textTable(
                headers: const ['Variable', 'Lower bound', 'Upper bound'],
                rows: variableChunks[i],
                emptyHint: 'No optimisation variables were defined.',
              ),
            ),
          ],
        ),
      );
    }

    final constraintChunks = constraintRows.isEmpty
        ? [<List<String>>[]]
        : _chunk(constraintRows, _portraitTableRows);
    for (var i = 0; i < constraintChunks.length; i += 1) {
      doc.addPage(
        _buildPortraitPage(
          title: constraintChunks.length == 1
              ? 'Constraint Targets'
              : 'Constraint Targets ${i + 1}/${constraintChunks.length}',
          description:
              'Defined LCIA constraint targets.',
          children: [
            _panel(
              title: 'Constraints',
              child: _textTable(
                headers: const ['Constraint', 'Operator', 'Target'],
                rows: constraintChunks[i],
                emptyHint: 'No LCIA constraints were defined.',
              ),
            ),
          ],
        ),
      );
    }
  }

  static void _addResultSummaryPages(
    pw.Document doc, {
    required Map<String, dynamic>? best,
    required Map<String, dynamic>? baseline,
    required GoalSeekNumberFormatter formatNumber,
    required GoalSeekParameterLabelBuilder parameterLabelBuilder,
    required GoalSeekConstraintLabelBuilder constraintLabelBuilder,
  }) {
    doc.addPage(
      _buildPortraitPage(
        title: 'Result Summary',
        description:
            'Summary of the reported baseline and best feasible results.',
        children: [
          _panel(
            title: 'Objective Summary',
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _summaryValueCard(
                    title: 'Baseline',
                    value: baseline == null
                        ? 'Not recorded'
                        : formatNumber(baseline['display_objective_value']),
                    accent: _accent,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _summaryValueCard(
                    title: 'Best feasible',
                    value: best == null
                        ? 'No feasible point found'
                        : formatNumber(best['display_objective_value']),
                    accent: _success,
                  ),
                ),
              ],
            ),
          ),
          if (best == null)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _warningSoft,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _line),
              ),
              child: pw.Text(
                'The optimiser did not produce a feasible point. All evaluations remain available in the appendix for diagnosis.',
                style: _bodyStyle(),
              ),
            ),
        ],
      ),
    );

    if (best == null) return;

    final parameterRows = [
      for (final parameter in _listOfMaps(best['parameters']))
        [parameterLabelBuilder(parameter), formatNumber(parameter['value'])],
    ];
    final scoreRows = _bestScoreRows(best, formatNumber);
    final constraintRows = [
      for (final constraint in _listOfMaps(best['constraints']))
        [
          constraintLabelBuilder(constraint),
          formatNumber(constraint['value']),
          constraint['satisfied'] == true ? 'Pass' : 'Miss',
        ],
    ];

    _addPortraitTableSeries(
      doc,
      title: 'Best Point Parameters',
      description: 'Parameter values for the best feasible optimisation result.',
      panelTitle: 'Parameter values',
      headers: const ['Parameter', 'Value'],
      rows: parameterRows,
      emptyHint: 'No best-point parameter values were recorded.',
    );
    _addPortraitTableSeries(
      doc,
      title: 'Best Point Scores',
      description: 'Indicator scores for the best feasible optimisation result.',
      panelTitle: 'Indicator scores',
      headers: const ['Indicator', 'Value'],
      rows: scoreRows,
      emptyHint: 'No indicator scores were recorded for the best point.',
    );
    _addPortraitTableSeries(
      doc,
      title: 'Best Point Constraints',
      description: 'Constraint pass or miss status for the best feasible point.',
      panelTitle: 'Constraint checks',
      headers: const ['Constraint', 'Value', 'Status'],
      rows: constraintRows,
      emptyHint: 'No constraint checks were recorded for the best point.',
    );
  }

  static void _addPortraitTableSeries(
    pw.Document doc, {
    required String title,
    required String description,
    required String panelTitle,
    required List<String> headers,
    required List<List<String>> rows,
    required String emptyHint,
  }) {
    final batches = rows.isEmpty ? [<List<String>>[]] : _chunk(rows, _portraitTableRows);
    for (var i = 0; i < batches.length; i += 1) {
      doc.addPage(
        _buildPortraitPage(
          title: batches.length == 1 ? title : '$title ${i + 1}/${batches.length}',
          description: description,
          children: [
            _panel(
              title: panelTitle,
              child: _textTable(
                headers: headers,
                rows: batches[i],
                emptyHint: emptyHint,
              ),
            ),
          ],
        ),
      );
    }
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

  static pw.Page _buildCoverPage({
    required pw.MemoryImage? logo,
    required DateTime generatedAt,
    required String status,
    required String productSystemName,
    required String goalModeLabel,
    required String objectiveSummary,
    required String selectedImpactMethodSummary,
    required int evaluationCount,
    required int feasibleCount,
    required int warningCount,
    required String toolName,
    required Map<String, dynamic>? best,
    required Map<String, dynamic>? baseline,
    required Map<String, dynamic>? solverInitial,
    required GoalSeekNumberFormatter formatNumber,
  }) {
    final heroSubtitle = productSystemName.trim().isEmpty
        ? 'Optimisation route'
        : productSystemName.trim();
    final bestObjective =
        best == null
            ? 'No feasible solution found'
            : formatNumber(best['display_objective_value']);
    final referenceTitle = baseline != null
        ? 'Baseline objective'
        : solverInitial != null
        ? 'Solver initial objective'
        : 'Reference objective';
    final referenceEvaluation = baseline ?? solverInitial;
    final referenceObjective = referenceEvaluation == null
        ? 'Not recorded'
        : formatNumber(referenceEvaluation['display_objective_value']);
    final resultHeadline = best == null
        ? 'No feasible solution was found.'
        : 'Best feasible solution found.';

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border(
                top: pw.BorderSide(color: _brand, width: 3),
                bottom: pw.BorderSide(color: _line, width: 1),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null)
                      pw.SizedBox(width: 36, height: 36, child: pw.Image(logo)),
                    if (logo != null) pw.SizedBox(width: 14),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _title,
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            heroSubtitle,
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _statusPill(status),
                  ],
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  resultHeadline,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _brandDark,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  objectiveSummary,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Generated ${_formatDateTime(generatedAt)}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          _panel(
            title: 'Overview',
            child: _kvTable([
              ['Tool', toolName],
              ['Mode', goalModeLabel],
              [
                'Impact method',
                selectedImpactMethodSummary.trim().isEmpty
                    ? 'Not resolved'
                    : selectedImpactMethodSummary.trim(),
              ],
              ['Recorded runs', '$evaluationCount'],
              ['Feasible runs', '$feasibleCount'],
              ['Warnings', '$warningCount'],
              [referenceTitle, referenceObjective],
              ['Best feasible objective', bestObjective],
            ]),
          ),
          pw.SizedBox(height: 10),
          _buildFooter(context.pageNumber),
        ],
      ),
    );
  }

  static pw.Page _buildPortraitPage({
    required String title,
    required String description,
    required List<pw.Widget> children,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: pw.BoxDecoration(
              color: _surfaceStrong,
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: _buildSectionHeader(
              title: title,
              description: description,
            ),
          ),
          pw.SizedBox(height: 12),
          ..._withSpacing(children, gap: 10),
          pw.Spacer(),
          _buildFooter(context.pageNumber),
        ],
      ),
    );
  }

  static pw.Widget _buildRunDetailsCard({
    required String status,
    required String toolName,
    required String productSystemName,
    required String goalModeLabel,
    required String objectiveSummary,
    required String selectedImpactMethodSummary,
    required List<Map<String, dynamic>> evaluations,
    required int feasibleCount,
    required GoalSeekNumberFormatter formatNumber,
    required Map<String, dynamic>? baseline,
    required Map<String, dynamic>? solverInitial,
    required Map<String, dynamic>? best,
    required DateTime generatedAt,
    required Map<String, dynamic> job,
    required Map<String, dynamic>? optimizer,
  }) {
    final objectiveLabel = _asString(
      baseline?['objective_label'] ??
          solverInitial?['objective_label'] ??
          best?['objective_label'],
    );
    final startedAt = _toDateTime(job['started_at']);
    final completedAt = _toDateTime(job['completed_at']);
    final referenceTitle = baseline != null
        ? 'Baseline objective'
        : solverInitial != null
        ? 'Solver initial objective'
        : 'Reference objective';
    final referenceEvaluation = baseline ?? solverInitial;
    final solverSettings =
        optimizer == null ? null : _mapOrNull(optimizer['solver_settings']);
    return _panel(
      title: 'Run Details',
      child: _kvTable([
        ['Status', status],
        ['Tool', toolName],
        [
          'Product system',
          productSystemName.trim().isEmpty ? 'Not selected' : productSystemName.trim(),
        ],
        ['Mode', goalModeLabel],
        ['Objective', objectiveSummary],
        [
          'LCIA method(s)',
          selectedImpactMethodSummary.trim().isEmpty
              ? 'Not resolved'
              : selectedImpactMethodSummary.trim(),
        ],
        ['Generated', _formatDateTime(generatedAt)],
        ['Started', startedAt == null ? 'Not recorded' : _formatDateTime(startedAt)],
        [
          'Completed',
          completedAt == null ? 'Not recorded' : _formatDateTime(completedAt),
        ],
        ['Runtime', _formatDuration(startedAt, completedAt)],
        ['Recorded evaluations', '${evaluations.length}'],
        ['Feasible evaluations', '$feasibleCount'],
        if (optimizer != null)
          ['Stop reason', _humanizeStopReason(_asString(optimizer['stop_reason']))],
        if (optimizer != null)
          ['Solver method', _asString(optimizer['method'], fallback: 'Not recorded')],
        if (solverSettings != null)
          [
            'Solver settings',
            _solverSettingsSummary(solverSettings),
          ],
        if (objectiveLabel.isNotEmpty) ['Objective label', objectiveLabel],
        if (referenceEvaluation != null)
          [referenceTitle, formatNumber(referenceEvaluation['display_objective_value'])],
        if (best != null)
          ['Best feasible objective', formatNumber(best['display_objective_value'])],
      ]),
    );
  }

  static pw.Widget _buildConfigurationCard({
    required List<GoalSeekReportVariable> variables,
    required List<GoalSeekReportConstraint> constraints,
  }) {
    return _panel(
      title: 'Optimisation Setup',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Variable bounds',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 6),
          _textTable(
            headers: const ['Variable', 'Lower bound', 'Upper bound'],
            rows: [
              for (final variable in variables)
                [variable.label, variable.lower, variable.upper],
            ],
            emptyHint: 'No optimisation variables were defined.',
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Constraint targets',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 6),
          _textTable(
            headers: const ['Constraint', 'Operator', 'Target'],
            rows: [
              for (final constraint in constraints)
                [constraint.label, constraint.operator, constraint.target],
            ],
            emptyHint: 'No LCIA constraints were defined.',
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildResultSummaryCard({
    required Map<String, dynamic>? best,
    required Map<String, dynamic>? baseline,
    required Map<String, dynamic>? solverInitial,
    required GoalSeekNumberFormatter formatNumber,
    required GoalSeekParameterLabelBuilder parameterLabelBuilder,
    required GoalSeekConstraintLabelBuilder constraintLabelBuilder,
  }) {
    final referenceTitle = baseline != null
        ? 'Baseline'
        : solverInitial != null
        ? 'Solver initial point'
        : 'Reference';
    final referenceEvaluation = baseline ?? solverInitial;
    return _panel(
      title: 'Result Summary',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _summaryValueCard(
                  title: referenceTitle,
                  value: referenceEvaluation == null
                      ? 'Not recorded'
                      : formatNumber(referenceEvaluation['display_objective_value']),
                  accent: _accent,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _summaryValueCard(
                  title: 'Best feasible',
                  value: best == null
                      ? 'No feasible point found'
                      : formatNumber(best['display_objective_value']),
                  accent: _success,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          if (best == null)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _warningSoft,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: _line),
              ),
              child: pw.Text(
                'The optimiser did not produce a feasible solution that satisfied all recorded constraints.',
                style: _bodyStyle(),
              ),
            )
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: _successSoft,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: _line),
                  ),
                  child: pw.Text(
                    'Reported result is the best feasible solution found from the recorded evaluations. This wording does not claim a proven global optimum.',
                    style: _bodyStyle(color: _success),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Best feasible parameter values',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 6),
                _textTable(
                  headers: const ['Parameter', 'Value'],
                  rows: [
                    for (final parameter in _listOfMaps(best['parameters']))
                      [
                        parameterLabelBuilder(parameter),
                        formatNumber(parameter['value']),
                      ],
                  ],
                  emptyHint: 'No best-point parameter values were recorded.',
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Indicator scores at the best feasible point',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 6),
                _textTable(
                  headers: const ['Indicator', 'Value'],
                  rows: _bestScoreRows(best, formatNumber),
                  emptyHint: 'No indicator scores were recorded for the best point.',
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Constraint checks at the best feasible point',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 6),
                _textTable(
                  headers: const ['Constraint', 'Value', 'Status'],
                  rows: [
                    for (final constraint in _listOfMaps(best['constraints']))
                      [
                        constraintLabelBuilder(constraint),
                        formatNumber(constraint['value']),
                        constraint['satisfied'] == true ? 'Pass' : 'Miss',
                      ],
                  ],
                  emptyHint: 'No constraint checks were recorded for the best point.',
                ),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildTextCard(
    String title,
    String body, {
    bool preserveWhitespace = false,
  }) {
    return _panel(
      title: title,
      child: pw.Text(
        preserveWhitespace ? _cleanPromptText(body) : _cleanText(body),
        style: _bodyStyle(),
      ),
    );
  }

  static pw.Widget _buildAlertCard(String title, String body) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _dangerSoft,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromHex('#F4B4AE')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _danger,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(_cleanText(body), style: _bodyStyle(color: _danger)),
        ],
      ),
    );
  }

  static String _solverSettingsSummary(Map<String, dynamic> settings) {
    final parts = <String>[];
    final n = settings['n'];
    final iters = settings['iters'];
    final samplingMethod = _asString(settings['sampling_method']);
    final localMinimizer = _asString(settings['local_minimizer']);
    if (n != null) parts.add('n=$n');
    if (iters != null) parts.add('iters=$iters');
    if (samplingMethod.isNotEmpty) parts.add('sampling=$samplingMethod');
    if (localMinimizer.isNotEmpty) parts.add('local=$localMinimizer');
    return parts.isEmpty ? 'Not recorded' : parts.join(', ');
  }

  static String _humanizeStopReason(String stopReason) {
    if (stopReason.trim().isEmpty) return 'Not recorded';
    return stopReason
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static void _addEvaluationOverviewPages(
    pw.Document doc,
    List<_PreparedEvaluation> evaluations, {
    required String objectiveSummary,
  }) {
    final rows = [
      for (final evaluation in evaluations)
        [
          evaluation.indexLabel,
          evaluation.objectiveValue,
          evaluation.feasibleLabel,
          '${evaluation.parameterValues.length}',
          '${evaluation.constraintValues.length}',
          '${evaluation.warningCount}',
          evaluation.isBest ? 'Best feasible' : '',
        ],
    ];

    for (final batch in _chunk(rows, 26)) {
      doc.addPage(
        _buildLandscapeTablePage(
          sectionTitle: 'Evaluation Overview',
          sectionDescription:
              'Every optimiser run is listed here. Detailed parameter and constraint values follow in the matrix appendix.',
          objectiveSummary: objectiveSummary,
          headers: const [
            'Eval',
            'Objective',
            'Status',
            'Params',
            'Constraints',
            'Warnings',
            'Flag',
          ],
          rows: batch,
          columnWidths: const {
            0: pw.FixedColumnWidth(42),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FixedColumnWidth(58),
            3: pw.FixedColumnWidth(48),
            4: pw.FixedColumnWidth(72),
            5: pw.FixedColumnWidth(55),
            6: pw.FixedColumnWidth(76),
          },
        ),
      );
    }
  }

  static void _addParameterMatrixPages(
    pw.Document doc,
    List<_PreparedEvaluation> evaluations,
    List<_MatrixColumn> columns, {
    required String objectiveSummary,
  }) {
    if (columns.isEmpty) return;
    const rowsPerPage = 24;
    const columnsPerPage = 6;
    for (final columnBatch in _chunk(columns, columnsPerPage)) {
      final legendRows = [
        for (final column in columnBatch) [column.code, column.label],
      ];
      for (final rowBatch in _chunk(evaluations, rowsPerPage)) {
        doc.addPage(
          _buildLandscapeTablePage(
            sectionTitle: 'Parameter Matrix',
            sectionDescription:
                'Full parameter values for each recorded evaluation. Column legends are shown above the table to keep the matrix readable.',
            objectiveSummary: objectiveSummary,
            headers: [
              'Eval',
              'Objective',
              'Status',
              for (final column in columnBatch) column.code,
            ],
            rows: [
              for (final evaluation in rowBatch)
                [
                  evaluation.indexLabel,
                  evaluation.objectiveValue,
                  evaluation.feasibleLabel,
                  for (final column in columnBatch)
                    evaluation.parameterValues[column.key] ?? '-',
                ],
            ],
            legendRows: legendRows,
            columnWidths: {
              0: const pw.FixedColumnWidth(42),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FixedColumnWidth(58),
              for (var i = 0; i < columnBatch.length; i++)
                i + 3: const pw.FlexColumnWidth(1.1),
            },
          ),
        );
      }
    }
  }

  static void _addConstraintMatrixPages(
    pw.Document doc,
    List<_PreparedEvaluation> evaluations,
    List<_MatrixColumn> columns, {
    required String objectiveSummary,
  }) {
    if (columns.isEmpty) return;
    const rowsPerPage = 24;
    const columnsPerPage = 4;
    for (final columnBatch in _chunk(columns, columnsPerPage)) {
      final legendRows = [
        for (final column in columnBatch) [column.code, column.label],
      ];
      for (final rowBatch in _chunk(evaluations, rowsPerPage)) {
        doc.addPage(
          _buildLandscapeTablePage(
            sectionTitle: 'Constraint Matrix',
            sectionDescription:
                'Each cell records the matched value and pass or miss status for the corresponding constraint in that evaluation.',
            objectiveSummary: objectiveSummary,
            headers: [
              'Eval',
              'Objective',
              'Status',
              for (final column in columnBatch) column.code,
            ],
            rows: [
              for (final evaluation in rowBatch)
                [
                  evaluation.indexLabel,
                  evaluation.objectiveValue,
                  evaluation.feasibleLabel,
                  for (final column in columnBatch)
                    evaluation.constraintValues[column.key] ?? '-',
                ],
            ],
            legendRows: legendRows,
            columnWidths: {
              0: const pw.FixedColumnWidth(42),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FixedColumnWidth(58),
              for (var i = 0; i < columnBatch.length; i++)
                i + 3: const pw.FlexColumnWidth(1.4),
            },
          ),
        );
      }
    }
  }

  static void _addEventTimelinePages(
    pw.Document doc,
    List<Map<String, dynamic>> events,
  ) {
    final rows = [
      for (final event in events)
        [
          _formatEventTime(event['timestamp']),
          _asString(event['stage'], fallback: '-'),
          _cleanText(_asString(event['message'], fallback: '-')),
        ],
    ];
    for (final batch in _chunk(rows, 28)) {
      doc.addPage(
        _buildLandscapeTablePage(
          sectionTitle: 'Execution Timeline',
          sectionDescription:
              'Chronological event log captured during the optimiser run.',
          objectiveSummary: '',
          headers: const ['Time', 'Stage', 'Message'],
          rows: batch,
          columnWidths: const {
            0: pw.FixedColumnWidth(62),
            1: pw.FixedColumnWidth(90),
            2: pw.FlexColumnWidth(4),
          },
        ),
      );
    }
  }

  static pw.Page _buildLandscapeTablePage({
    required String sectionTitle,
    required String sectionDescription,
    required String objectiveSummary,
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, pw.TableColumnWidth> columnWidths,
    List<List<String>> legendRows = const [],
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: pw.BoxDecoration(
              color: _surfaceStrong,
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  sectionTitle,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  sectionDescription,
                  style: _bodyStyle(color: _muted, fontSize: 9),
                ),
                if (objectiveSummary.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    objectiveSummary,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _brand,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (legendRows.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _textTable(
              headers: const ['Code', 'Meaning'],
              rows: legendRows,
              columnWidths: const {
                0: pw.FixedColumnWidth(42),
                1: pw.FlexColumnWidth(5),
              },
              fontSize: 7.2,
              headerFontSize: 7.8,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 3,
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          _textTable(
            headers: headers,
            rows: rows,
            columnWidths: columnWidths,
            fontSize: 7.5,
            headerFontSize: 8.2,
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4,
            ),
          ),
          pw.Spacer(),
          _buildFooter(context.pageNumber),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionHeader({
    required String title,
    required String description,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _cleanText(description),
          style: _bodyStyle(color: _muted),
        ),
      ],
    );
  }

  static pw.Widget _summaryValueCard({
    required String title,
    required String value,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: _line),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: _bodyStyle(color: _muted, fontSize: 9)),
          pw.SizedBox(height: 6),
          pw.Container(
            width: 32,
            height: 4,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(99),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            _cleanText(value),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _panel({
    required String title,
    required pw.Widget child,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: _line),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  static pw.Widget _statusPill(String status) {
    final normalized = status.trim().toLowerCase();
    final passed = normalized == 'completed';
    final background = passed ? _successSoft : _warningSoft;
    final foreground = passed ? _success : _ink;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(999),
      ),
      child: pw.Text(
        _cleanText(status.isEmpty ? 'unknown' : status),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }

  static pw.Widget _legendChip(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(999),
        border: pw.Border.all(color: _line),
      ),
      child: pw.Text(
        _cleanText(text),
        style: _bodyStyle(fontSize: 7.8, color: _ink),
      ),
    );
  }

  static pw.Widget _kvTable(List<List<String>> rows) {
    return _textTable(
      headers: const ['Field', 'Value'],
      rows: rows,
      columnWidths: const {
        0: pw.FlexColumnWidth(1.3),
        1: pw.FlexColumnWidth(2.7),
      },
    );
  }

  static pw.Widget _textTable({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.TableColumnWidth>? columnWidths,
    String? emptyHint,
    double fontSize = 8.6,
    double headerFontSize = 9,
    pw.EdgeInsets cellPadding = const pw.EdgeInsets.symmetric(
      horizontal: 6,
      vertical: 5,
    ),
  }) {
    if (rows.isEmpty) {
      return pw.Text(
        emptyHint ?? 'No rows recorded.',
        style: _bodyStyle(color: _muted),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: headers.map(_cleanText).toList(),
      data: [
        for (final row in rows) row.map(_cleanText).toList(),
      ],
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: _line, width: 0.55),
      headerDecoration: pw.BoxDecoration(color: _surfaceStrong),
      headerStyle: pw.TextStyle(
        fontSize: headerFontSize,
        fontWeight: pw.FontWeight.bold,
        color: _ink,
      ),
      cellStyle: pw.TextStyle(fontSize: fontSize, color: _ink),
      cellPadding: cellPadding,
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static pw.Widget _buildFooter(int pageNumber) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Page $pageNumber',
        style: _bodyStyle(color: _muted, fontSize: 8.5),
      ),
    );
  }

  static pw.TextStyle _bodyStyle({
    PdfColor? color,
    double fontSize = 9.2,
  }) {
    return pw.TextStyle(
      fontSize: fontSize,
      color: color ?? _ink,
    );
  }

  static List<_PreparedEvaluation> _prepareEvaluations({
    required List<Map<String, dynamic>> evaluations,
    required Map<String, dynamic>? best,
    required GoalSeekNumberFormatter formatNumber,
  }) {
    final bestIndex = best?['index'];
    return [
      for (final evaluation in evaluations)
        _PreparedEvaluation(
          indexLabel: '#${_asString(evaluation['index'], fallback: '?')}',
          objectiveValue: formatNumber(evaluation['display_objective_value']),
          feasibleLabel: evaluation['feasible'] == true ? 'Pass' : 'Miss',
          warningCount:
              _listOfDynamic(evaluation['warnings']).whereType<String>().length,
          isBest: bestIndex != null && bestIndex == evaluation['index'],
          parameterValues: {
            for (final parameter in _listOfMaps(evaluation['parameters']))
              _parameterKey(parameter): formatNumber(parameter['value']),
          },
          constraintValues: {
            for (final constraint in _listOfMaps(evaluation['constraints']))
              _constraintKey(constraint):
                  '${formatNumber(constraint['value'])} | ${constraint['satisfied'] == true ? 'Pass' : 'Miss'}',
          },
        ),
    ];
  }

  static List<List<String>> _bestScoreRows(
    Map<String, dynamic> best,
    GoalSeekNumberFormatter formatNumber,
  ) {
    final scoreItems = _listOfMaps(best['score_items']);
    if (scoreItems.isNotEmpty) {
      return [
        for (final item in scoreItems)
          [
            _scoreLabel(item),
            _scoreValue(item, formatNumber),
          ],
      ];
    }
    final scores = best['scores'];
    if (scores is Map) {
      return [
        for (final entry in scores.entries)
          [entry.key.toString(), formatNumber(entry.value)],
      ];
    }
    return const [];
  }

  static List<_MatrixColumn> _collectParameterColumns(
    List<Map<String, dynamic>> evaluations,
    GoalSeekParameterLabelBuilder parameterLabelBuilder,
  ) {
    final columns = <_MatrixColumn>[];
    final seen = <String>{};
    var index = 1;
    for (final evaluation in evaluations) {
      for (final parameter in _listOfMaps(evaluation['parameters'])) {
        final key = _parameterKey(parameter);
        if (!seen.add(key)) continue;
        columns.add(
          _MatrixColumn(
            key: key,
            code: 'P$index',
            label: parameterLabelBuilder(parameter),
          ),
        );
        index += 1;
      }
    }
    return columns;
  }

  static List<_MatrixColumn> _collectConstraintColumns(
    List<Map<String, dynamic>> evaluations,
    GoalSeekConstraintLabelBuilder constraintLabelBuilder,
  ) {
    final columns = <_MatrixColumn>[];
    final seen = <String>{};
    var index = 1;
    for (final evaluation in evaluations) {
      for (final constraint in _listOfMaps(evaluation['constraints'])) {
        final key = _constraintKey(constraint);
        if (!seen.add(key)) continue;
        columns.add(
          _MatrixColumn(
            key: key,
            code: 'C$index',
            label: constraintLabelBuilder(constraint),
          ),
        );
        index += 1;
      }
    }
    return columns;
  }

  static String _parameterKey(Map<String, dynamic> parameter) {
    return '${_asString(parameter['field'])}|${_asString(parameter['process_id'])}';
  }

  static String _constraintKey(Map<String, dynamic> constraint) {
    return [
      _asString(constraint['impact_method_id']),
      _asString(constraint['impact_method_name']),
      _asString(constraint['impact_category_id']),
      _asString(constraint['indicator']),
      _asString(constraint['operator']),
      _asString(constraint['target']),
    ].join('|');
  }

  static String _scoreLabel(Map<String, dynamic> item) {
    final method = _asString(item['impact_method_name']);
    final indicator = _asString(
      item['indicator'],
      fallback: _asString(item['impact_category_id'], fallback: 'impact score'),
    );
    if (method.isEmpty) return indicator;
    return '$method / $indicator';
  }

  static String _scoreValue(
    Map<String, dynamic> item,
    GoalSeekNumberFormatter formatNumber,
  ) {
    final value = formatNumber(item['value']);
    final unit = _asString(item['unit']);
    return unit.isEmpty ? value : '$value $unit';
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic value) {
    return value is List
        ? value.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList()
        : const [];
  }

  static List<dynamic> _listOfDynamic(dynamic value) {
    return value is List ? value : const [];
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static List<List<T>> _chunk<T>(List<T> values, int size) {
    if (values.isEmpty) return const [];
    final out = <List<T>>[];
    for (var i = 0; i < values.length; i += size) {
      out.add(values.sublist(i, i + size > values.length ? values.length : i + size));
    }
    return out;
  }

  static String _asString(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static List<String> _chunkText(String text, int maxChars) {
    final normalized = _cleanText(text);
    if (normalized.isEmpty) return const [];

    final paragraphs = normalized.split('\n\n');
    final chunks = <String>[];
    var current = '';

    void flush() {
      final out = current.trim();
      if (out.isNotEmpty) chunks.add(out);
      current = '';
    }

    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > maxChars) {
        if (current.isNotEmpty) flush();
        for (var i = 0; i < trimmed.length; i += maxChars) {
          final end = i + maxChars > trimmed.length ? trimmed.length : i + maxChars;
          chunks.add(trimmed.substring(i, end).trim());
        }
        continue;
      }

      final candidate = current.isEmpty ? trimmed : '${current.trim()}\n\n$trimmed';
      if (candidate.length > maxChars && current.isNotEmpty) {
        flush();
      }
      current = current.isEmpty ? trimmed : '${current.trim()}\n\n$trimmed';
    }

    if (current.isNotEmpty) flush();
    return chunks;
  }

  static List<String> _chunkPromptText(String text, int maxChars) {
    final normalized = _cleanPromptText(text);
    if (normalized.trim().isEmpty) return const [];

    final chunks = <String>[];
    var current = StringBuffer();

    void flush() {
      final out = current.toString();
      if (out.isNotEmpty) chunks.add(out);
      current = StringBuffer();
    }

    final lines = normalized.split('\n');
    for (var i = 0; i < lines.length; i += 1) {
      final segment = i == lines.length - 1 ? lines[i] : '${lines[i]}\n';
      if (segment.length > maxChars) {
        if (current.isNotEmpty) flush();
        for (var start = 0; start < segment.length; start += maxChars) {
          final end = start + maxChars > segment.length
              ? segment.length
              : start + maxChars;
          chunks.add(segment.substring(start, end));
        }
        continue;
      }
      if (current.isNotEmpty && current.length + segment.length > maxChars) {
        flush();
      }
      current.write(segment);
    }

    if (current.isNotEmpty) flush();
    return chunks;
  }

  static List<pw.Widget> _withSpacing(List<pw.Widget> children, {double gap = 8}) {
    final out = <pw.Widget>[];
    for (var i = 0; i < children.length; i += 1) {
      out.add(children[i]);
      if (i != children.length - 1) {
        out.add(pw.SizedBox(height: gap));
      }
    }
    return out;
  }

  static String _cleanText(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _cleanPromptText(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static DateTime? _toDateTime(dynamic secondsValue) {
    final seconds = (secondsValue as num?)?.toDouble();
    if (seconds == null || !seconds.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: false,
    );
  }

  static String _formatDateTime(DateTime value) {
    final two = (int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static String _formatDuration(DateTime? startedAt, DateTime? completedAt) {
    if (startedAt == null) return 'n/a';
    final end = completedAt ?? DateTime.now();
    final seconds = end.difference(startedAt).inSeconds;
    if (seconds < 60) return '${seconds.clamp(0, 999999)}s';
    final minutes = seconds ~/ 60;
    final remSeconds = seconds % 60;
    if (minutes < 60) {
      return '${minutes}m ${remSeconds.toString().padLeft(2, '0')}s';
    }
    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;
    return '${hours}h ${remMinutes.toString().padLeft(2, '0')}m';
  }

  static String _formatEventTime(dynamic rawTimestamp) {
    final date = _toDateTime(rawTimestamp);
    if (date == null) return '-';
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }
}

class _PreparedEvaluation {
  final String indexLabel;
  final String objectiveValue;
  final String feasibleLabel;
  final int warningCount;
  final bool isBest;
  final Map<String, String> parameterValues;
  final Map<String, String> constraintValues;

  const _PreparedEvaluation({
    required this.indexLabel,
    required this.objectiveValue,
    required this.feasibleLabel,
    required this.warningCount,
    required this.isBest,
    required this.parameterValues,
    required this.constraintValues,
  });
}

class _MatrixColumn {
  final String key;
  final String code;
  final String label;

  const _MatrixColumn({
    required this.key,
    required this.code,
    required this.label,
  });
}
