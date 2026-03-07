

// File: lib/lca/lca_models.dart
//
// Domain models, constants, helpers, and a safe parameter engine.
// Backwards compatible with your existing JSON.
//
// Additions for parameter-driven flows:
//  - FlowValue.boundParam  -> serialised as "amount_param"
//  - FlowValue.amountExpr  -> serialised as "amount_expr"
//  - Helpers to evaluate expressions with global and per-process parameters.

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// ===== Constants kept from the original file =====

const List<String> kFlowUnits = [
  'kg', 'MW', 'units', 'L', 'm³', 'm',
  'Km', 'KWh', 'g', 'MJ', 'kJ', 'm²',
  'hours', 'days','tKm'
];

// UI constraints (still referenced by widgets or painters)
const int kNodeFlowNameMaxChars = 18; // in-node truncated name length
const int kEdgeLabelMaxChars = 24;    // connection label truncated length

/// ===== Public helpers (were private in the monolithic file) =====

String truncateText(String s, int max) {
  if (s.length <= max) return s;
  if (max <= 1) return s.substring(0, max);
  return s.substring(0, max - 1) + '…';
}

String fmtAmount(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final asStr = v.toStringAsFixed(4);
  return asStr.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// ===== FlowValue with optional amount expression or parameter binding =====
/// Backwards compatible: `amount` stays numeric. If user typed a formula or
/// bound to a parameter, we keep the text in `amountExpr` or `boundParam` and
/// also store the last evaluated number in `amount`.
class FlowValue {
  final String name;
  final double amount;
  final String unit;
  final String? flowUuid;    // biosphere3 UUID for emissions
  final String? amountExpr;  // textual expression if provided
  final String? boundParam;  // simple binding to a parameter name

  const FlowValue({
    required this.name,
    required this.amount,
    required this.unit,
    this.flowUuid,
    this.amountExpr,
    this.boundParam,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
        if (flowUuid != null) 'flow_uuid': flowUuid,
        if (_hasText(amountExpr)) 'amount_expr': amountExpr,
        if (_hasText(boundParam)) 'amount_param': boundParam,
      };

  factory FlowValue.fromJson(Map<String, dynamic> json) => FlowValue(
        name: json['name'] as String,
        amount: (json['amount'] as num).toDouble(),
        unit: json['unit'] as String,
        flowUuid: json['flow_uuid'] as String?,
        amountExpr: _clean(json['amount_expr']),
        boundParam: _clean(json['amount_param']),
      );

  FlowValue copyWith({
    String? name,
    double? amount,
    String? unit,
    String? flowUuid,
    String? amountExpr,
    String? boundParam,
  }) {
    return FlowValue(
      name: name ?? this.name,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      flowUuid: flowUuid ?? this.flowUuid,
      amountExpr: amountExpr ?? this.amountExpr,
      boundParam: boundParam ?? this.boundParam,
    );
  }
}

/// ===== ProcessNode with optional parameter list =====
class ProcessNode {
  final String id;
  final String name;
  final List<FlowValue> inputs;
  final List<FlowValue> outputs;
  final List<FlowValue> emissions;
  final Offset position;
  final bool isFunctional;

  /// Optional local parameters for this process.
  final List<Parameter> parameters;

  const ProcessNode({
    required this.id,
    required this.name,
    required this.inputs,
    required this.outputs,
    required this.emissions,
    required this.position,
    this.isFunctional = false,
    this.parameters = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'inputs': inputs.map((f) => f.toJson()).toList(),
        'outputs': outputs.map((f) => f.toJson()).toList(),
        'emissions': emissions.map((f) => f.toJson()).toList(),
        'position': {'x': position.dx, 'y': position.dy},
        'isFunctional': isFunctional,
        if (parameters.isNotEmpty) 'parameters': parameters.map((p) => p.toJson()).toList(),
      };

  factory ProcessNode.fromJson(Map<String, dynamic> json) => ProcessNode(
        id: json['id'] as String,
        name: json['name'] as String,
        inputs: (json['inputs'] as List)
            .map((e) => FlowValue.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputs: (json['outputs'] as List)
            .map((e) => FlowValue.fromJson(e as Map<String, dynamic>))
            .toList(),
        emissions: (json['emissions'] as List)
            .map((e) => FlowValue.fromJson(e as Map<String, dynamic>))
            .toList(),
        position: Offset(
          (json['position']['x'] as num).toDouble(),
          (json['position']['y'] as num).toDouble(),
        ),
        isFunctional: json['isFunctional'] as bool? ?? false,
        parameters: (json['parameters'] as List?)
                ?.map((e) => Parameter.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  ProcessNode copyWith({Offset? position, bool? isFunctional}) => ProcessNode(
        id: id,
        name: name,
        inputs: inputs,
        outputs: outputs,
        emissions: emissions,
        position: position ?? this.position,
        isFunctional: isFunctional ?? this.isFunctional,
        parameters: parameters,
      );

  ProcessNode copyWithFields({
    String? name,
    List<FlowValue>? inputs,
    List<FlowValue>? outputs,
    List<FlowValue>? emissions,
    Offset? position,
    bool? isFunctional,
    List<Parameter>? parameters,
  }) =>
      ProcessNode(
        id: id,
        name: name ?? this.name,
        inputs: inputs ?? this.inputs,
        outputs: outputs ?? this.outputs,
        emissions: emissions ?? this.emissions,
        position: position ?? this.position,
        isFunctional: isFunctional ?? this.isFunctional,
        parameters: parameters ?? this.parameters,
      );
}

/// ===== Parameter model =====

enum ParameterScope { global, process }

class Parameter {
  final String name;
  final double? value;     // concrete number if not a formula
  final String? formula;   // textual expression, optional
  final ParameterScope scope;
  final String? unit;      // optional, for display only
  final String? note;      // optional annotation

  const Parameter({
    required this.name,
    this.value,
    this.formula,
    this.scope = ParameterScope.process,
    this.unit,
    this.note,
  });

  bool get isFormula => _hasText(formula);

  Map<String, dynamic> toJson() => {
        'name': name,
        if (value != null) 'value': value,
        if (_hasText(formula)) 'formula': formula,
        'scope': scope.name,
        if (unit != null) 'unit': unit,
        if (note != null) 'note': note,
      };

  factory Parameter.fromJson(Map<String, dynamic> json) => Parameter(
        name: json['name'] as String,
        value: (json['value'] as num?)?.toDouble(),
        formula: _clean(json['formula']),
        scope: _parseScope(json['scope'] as String?),
        unit: json['unit'] as String?,
        note: json['note'] as String?,
      );

  Parameter copyWith({
    String? name,
    double? value,
    String? formula,
    ParameterScope? scope,
    String? unit,
    String? note,
  }) =>
      Parameter(
        name: name ?? this.name,
        value: value ?? this.value,
        formula: formula ?? this.formula,
        scope: scope ?? this.scope,
        unit: unit ?? this.unit,
        note: note ?? this.note,
      );

  static ParameterScope _parseScope(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'global':
        return ParameterScope.global;
      case 'process':
      default:
        return ParameterScope.process;
    }
  }
}

/// Collection of parameters split into global and per-process sets.
/// JSON shape is flat and explicit for clarity in export files.
class ParameterSet {
  final List<Parameter> global;                     // scope == global
  final Map<String, List<Parameter>> perProcess;    // processId -> parameters (scope == process)

  const ParameterSet({
    this.global = const [],
    this.perProcess = const {},
  });

  bool get isEmpty => global.isEmpty && perProcess.isEmpty;

  Map<String, dynamic> toJson() => {
        if (global.isNotEmpty) 'global_parameters': global.map((p) => p.toJson()).toList(),
        if (perProcess.isNotEmpty)
          'process_parameters': perProcess.map(
            (k, v) => MapEntry(k, v.map((p) => p.toJson()).toList()),
          ),
      };

  factory ParameterSet.fromJson(Map<String, dynamic> json) {
    final g = (json['global_parameters'] as List?)
            ?.map((e) => Parameter.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <Parameter>[];
    final ppRaw = (json['process_parameters'] as Map?) ?? const {};
    final pp = <String, List<Parameter>>{};
    for (final entry in ppRaw.entries) {
      final list = (entry.value as List)
          .map((e) => Parameter.fromJson(e as Map<String, dynamic>))
          .toList();
      pp[entry.key as String] = list;
    }
    return ParameterSet(global: g, perProcess: pp);
  }

  /// Finds process parameters using exact id first, then case-insensitive match.
  List<Parameter> processParamsFor(String processId) {
    final exact = perProcess[processId];
    if (exact != null) return exact;

    final needle = processId.trim().toLowerCase();
    for (final entry in perProcess.entries) {
      if (entry.key.trim().toLowerCase() == needle) {
        return entry.value;
      }
    }
    return const <Parameter>[];
  }

  /// Returns evaluated symbols for a given process id.
  /// Global parameters are evaluated first, then process-level which may
  /// reference globals or other process parameters.
  ///
  /// Errors are thrown as ParameterEvaluationException with details.
  Map<String, double> evaluateSymbolsForProcess(String processId) {
    final engine = ParameterEngine();
    final globalVals = engine.evaluateParameterList(global, allowedOuter: const {});
    final local = processParamsFor(processId);
    final localVals = engine.evaluateParameterList(local, allowedOuter: globalVals);
    // Precedence: local shadows global
    return {...globalVals, ...localVals};
  }

  /// Lenient symbol resolution used by editors/previews.
  /// It keeps numeric values and evaluates only resolvable formulas.
  Map<String, double> evaluateGlobalSymbolsLenient() {
    return _evaluateParameterListLenient(global, const <String, double>{});
  }

  /// Lenient symbol resolution for one process.
  /// This avoids wiping all symbols when a single formula is unresolved.
  Map<String, double> evaluateSymbolsForProcessLenient(String processId) {
    final globalVals = evaluateGlobalSymbolsLenient();
    final local = processParamsFor(processId);
    final localVals = _evaluateParameterListLenient(local, globalVals);
    return {...globalVals, ...localVals};
  }

  /// Convenience: evaluate an expression with the symbols for a process.
  double evaluateExprForProcess(String processId, String expression) {
    final symbols = evaluateSymbolsForProcess(processId);
    return ParameterEngine().evaluateExpression(expression, symbols);
  }

  Map<String, double> _evaluateParameterListLenient(
    List<Parameter> params,
    Map<String, double> allowedOuter,
  ) {
    final out = <String, double>{};
    final engine = ParameterEngine();

    // Seed numeric values first.
    for (final p in params) {
      final key = p.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (p.value != null) out[key] = p.value!;
    }

    // Iteratively evaluate formulas where dependencies are available.
    final pending = params
        .where((p) => (p.formula ?? '').trim().isNotEmpty)
        .toList(growable: true);

    bool progressed;
    do {
      progressed = false;
      final symbols = <String, double>{...allowedOuter, ...out};

      final resolvedThisPass = <Parameter>[];
      for (final p in pending) {
        final expr = (p.formula ?? '').trim();
        final key = p.name.trim().toLowerCase();
        if (expr.isEmpty || key.isEmpty) {
          resolvedThisPass.add(p);
          continue;
        }
        try {
          final v = engine.evaluateExpression(expr, symbols);
          out[key] = v;
          resolvedThisPass.add(p);
          progressed = true;
        } catch (_) {
          // Keep pending; unresolved formulas are skipped in lenient mode.
        }
      }
      pending.removeWhere((p) => resolvedThisPass.contains(p));
    } while (progressed && pending.isNotEmpty);

    return out;
  }
}

/// ===== Parameter engine: parsing, validation, evaluation =====

/// Exception that carries user-friendly messages for UI display.
class ParameterEvaluationException implements Exception {
  final String message;
  final List<String> details;
  ParameterEvaluationException(this.message, [List<String>? details])
      : details = details ?? const [];
  @override
  String toString() => '$message${details.isEmpty ? '' : ': ${details.join('; ')}'}';
}

/// A small expression in Reverse Polish Notation with identifier list.
/// Parsing uses a shunting-yard algorithm. Supported:
/// - Operators: + - * / ^
/// - Parentheses: ( )
/// - Commas for function arg separation
/// - Functions: min, max, abs, round, ceil, floor
/// - Identifiers: [A-Za-z_][A-Za-z0-9_]*
/// - Numbers: decimal, exponent forms
class Expression {
  final List<_Token> rpn;
  final Set<String> identifiers;
  Expression(this.rpn, this.identifiers);
}

class ParameterEngine {
  // Operator precedence and associativity
  static const Map<String, int> _prec = {
    '^': 4,
    '*': 3,
    '/': 3,
    '+': 2,
    '-': 2,
  };
  static const Set<String> _rightAssoc = {'^'};

  static const Set<String> _funcs = {
    'min', 'max', 'abs', 'round', 'ceil', 'floor',
  };

  /// Parse a textual expression into RPN and collect identifiers.
  Expression parse(String expr) {
    final tokens = _lex(expr);
    final output = <_Token>[];
    final ops = <_Token>[];
    final ids = <String>{};

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      switch (t.type) {
        case _TokenType.number:
          output.add(t);
          break;
        case _TokenType.identifier:
          final name = t.text!;
          if (_funcs.contains(name.toLowerCase())) {
            ops.add(t.copyAs(_TokenType.function));
          } else {
            output.add(t);
            ids.add(name);
          }
          break;
        case _TokenType.comma:
          while (ops.isNotEmpty && ops.last.type != _TokenType.lparen) {
            output.add(ops.removeLast());
          }
          if (ops.isEmpty) {
            throw ParameterEvaluationException('Comma misplaced in expression');
          }
          break;
        case _TokenType.operator_:
          while (
              ops.isNotEmpty &&
              ops.last.type == _TokenType.operator_ &&
              ((_prec[ops.last.text] ?? 0) > (_prec[t.text] ?? 0) ||
                  ((_prec[ops.last.text] ?? 0) == (_prec[t.text] ?? 0) &&
                      !_rightAssoc.contains(t.text)))) {
            output.add(ops.removeLast());
          }
          ops.add(t);
          break;
        case _TokenType.lparen:
          ops.add(t);
          break;
        case _TokenType.rparen:
          while (ops.isNotEmpty && ops.last.type != _TokenType.lparen) {
            output.add(ops.removeLast());
          }
          if (ops.isEmpty) {
            throw ParameterEvaluationException('Mismatched parentheses');
          }
          ops.removeLast(); // pop '('
          if (ops.isNotEmpty && ops.last.type == _TokenType.function) {
            output.add(ops.removeLast()); // pop fn to output
          }
          break;
        default:
          throw ParameterEvaluationException('Unexpected token');
      }
    }
    while (ops.isNotEmpty) {
      final t = ops.removeLast();
      if (t.type == _TokenType.lparen || t.type == _TokenType.rparen) {
        throw ParameterEvaluationException('Mismatched parentheses');
      }
      output.add(t);
    }
    return Expression(output, ids.map((s) => s.toLowerCase()).toSet());
  }

  /// Evaluate an already-parsed expression with given symbols.
  double _evalRpn(List<_Token> rpn, Map<String, double> symbols) {
    final st = <double>[];
    for (final t in rpn) {
      switch (t.type) {
        case _TokenType.number:
          st.add(t.number!);
          break;
        case _TokenType.identifier:
          final key = t.text!.toLowerCase();
          final v = symbols[key];
          if (v == null) {
            throw ParameterEvaluationException('Unknown symbol "$key"');
          }
          st.add(v);
          break;
        case _TokenType.operator_:
          if (st.length < 2) throw ParameterEvaluationException('Malformed expression');
          final b = st.removeLast();
          final a = st.removeLast();
          switch (t.text) {
            case '+':
              st.add(a + b);
              break;
            case '-':
              st.add(a - b);
              break;
            case '*':
              st.add(a * b);
              break;
            case '/':
              st.add(a / b);
              break;
            case '^':
              st.add(math.pow(a, b).toDouble());
              break;
            default:
              throw ParameterEvaluationException('Unknown operator "${t.text}"');
          }
          break;
        case _TokenType.function:
          final name = t.text!.toLowerCase();
          switch (name) {
            case 'abs':
            case 'round':
            case 'ceil':
            case 'floor':
              if (st.isEmpty) throw ParameterEvaluationException('Function "$name" missing argument');
              final x = st.removeLast();
              switch (name) {
                case 'abs':
                  st.add(x.abs());
                  break;
                case 'round':
                  st.add(x.roundToDouble());
                  break;
                case 'ceil':
                  st.add(x.ceilToDouble());
                  break;
                case 'floor':
                  st.add(x.floorToDouble());
                  break;
              }
              break;
            case 'min':
            case 'max':
              if (st.length < 2) throw ParameterEvaluationException('Function "$name" needs two arguments');
              final b = st.removeLast();
              final a = st.removeLast();
              st.add(name == 'min' ? math.min(a, b) : math.max(a, b));
              break;
            default:
              throw ParameterEvaluationException('Unknown function "$name"');
          }
          break;
        default:
          throw ParameterEvaluationException('Unexpected token during evaluation');
      }
    }
    if (st.length != 1) throw ParameterEvaluationException('Malformed expression');
    return st.single;
  }

  /// Evaluate a string expression with a symbol table.
  double evaluateExpression(String expr, Map<String, double> symbols) {
    final parsed = parse(expr);
    return _evalRpn(parsed.rpn, symbols);
  }

  /// Evaluate a list of parameters with dependency checking.
  /// - `allowedOuter` provides pre-known symbols (for example global when evaluating process).
  /// - Cycles or unknown symbols raise ParameterEvaluationException with details.
  Map<String, double> evaluateParameterList(
    List<Parameter> list, {
    required Map<String, double> allowedOuter,
  }) {
    // Build maps and dependency graph
    final nameToParam = <String, Parameter>{};
    for (final p in list) {
      final key = p.name.toLowerCase().trim();
      if (key.isEmpty) continue;
      nameToParam[key] = p;
    }

    final deps = <String, Set<String>>{}; // name -> set of names it depends on
    final parsedCache = <String, Expression>{};

    for (final entry in nameToParam.entries) {
      final name = entry.key;
      final p = entry.value;
      if (p.isFormula) {
        final exp = parse(p.formula!);
        parsedCache[name] = exp;
        final needs = exp.identifiers
            .where((id) => !_funcs.contains(id))
            .where((id) => id != name) // trivial self
            .toSet();
        deps[name] = needs;
      } else {
        deps[name] = {};
      }
    }

    // Validate: unknown symbols must exist in either locals or allowedOuter
    final unknowns = <String, List<String>>{}; // param -> missing symbols
    deps.forEach((param, needs) {
      final missing = needs.where(
        (s) => !nameToParam.containsKey(s) && !allowedOuter.containsKey(s),
      );
      if (missing.isNotEmpty) {
        unknowns[param] = missing.toList();
      }
    });
    if (unknowns.isNotEmpty) {
      final details = unknowns.entries
          .map((e) => '${e.key} missing: ${e.value.join(', ')}')
          .toList();
      throw ParameterEvaluationException('Unresolved symbols in parameters', details);
    }

    // Topological sort with cycle detection
    final tempMark = <String>{};
    final permMark = <String>{};
    final order = <String>[];
    void visit(String n) {
      if (permMark.contains(n)) return;
      if (tempMark.contains(n)) {
        throw ParameterEvaluationException('Cyclic dependency detected', [n]);
      }
      tempMark.add(n);
      for (final m in deps[n]!) {
        if (nameToParam.containsKey(m)) visit(m);
      }
      tempMark.remove(n);
      permMark.add(n);
      order.add(n);
    }

    for (final n in deps.keys) {
      if (!permMark.contains(n)) visit(n);
    }

    // Evaluate in order
    final symbols = <String, double>{...allowedOuter};
    for (final name in order) {
      final p = nameToParam[name]!;
      if (p.isFormula) {
        final exp = parsedCache[name]!;
        symbols[name] = _evalRpn(exp.rpn, symbols);
      } else {
        final v = p.value;
        if (v == null) {
          throw ParameterEvaluationException('Parameter "$name" has no value or formula');
        }
        symbols[name] = v;
      }
    }
    return {for (final e in nameToParam.entries) e.key: symbols[e.key]!};
  }

  /// ----- Lexer -----
  List<_Token> _lex(String expr) {
    final s = expr.trim();
    final tokens = <_Token>[];
    int i = 0;

    bool isIdentStart(int c) =>
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        c == 0x5F; // _

    bool isIdentPart(int c) => isIdentStart(c) || (c >= 0x30 && c <= 0x39); // + 0-9

    void pushNumber(String txt) {
      final n = double.tryParse(txt);
      if (n == null) {
        throw ParameterEvaluationException('Invalid number "$txt"');
      }
      tokens.add(_Token.number(n));
    }

    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      final c = String.fromCharCode(ch);
      // Skip spaces
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      // Numbers (support leading dot and exponent)
      if ((c == '.' && i + 1 < s.length && isDigit(s.codeUnitAt(i + 1))) ||
          isDigit(ch)) {
        int j = i + 1;
        bool hasDot = (c == '.');
        while (j < s.length) {
          final cj = s.codeUnitAt(j);
          if (cj == 0x2E) {
            if (hasDot) break;
            hasDot = true;
            j++;
            continue;
          }
          if (!isDigit(cj)) break;
          j++;
        }
        // exponent?
        if (j < s.length && (s[j] == 'e' || s[j] == 'E')) {
          int k = j + 1;
          if (k < s.length && (s[k] == '+' || s[k] == '-')) k++;
          bool any = false;
          while (k < s.length && isDigit(s.codeUnitAt(k))) {
            any = true;
            k++;
          }
          if (any) j = k;
        }
        pushNumber(s.substring(i, j));
        i = j;
        continue;
      }

      // Identifiers or functions
      if (isIdentStart(ch)) {
        int j = i + 1;
        while (j < s.length && isIdentPart(s.codeUnitAt(j))) j++;
        final name = s.substring(i, j);
        tokens.add(_Token.identifier(name));
        i = j;
        continue;
      }

      // Operators and punctuation
      switch (c) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '^':
          tokens.add(_Token.operatorToken(c));
          i++;
          continue;
        case '(':
          tokens.add(_Token.lparen());
          i++;
          continue;
        case ')':
          tokens.add(_Token.rparen());
          i++;
          continue;
        case ',':
          tokens.add(_Token.comma());
          i++;
          continue;
        default:
          throw ParameterEvaluationException('Unsupported character "$c"');
      }
    }
    return tokens;
  }

  bool isDigit(int code) => code >= 0x30 && code <= 0x39;
}

/// ----- Token support types -----

enum _TokenType { number, identifier, operator_, lparen, rparen, comma, function }

class _Token {
  final _TokenType type;
  final String? text;
  final double? number;
  const _Token._(this.type, this.text, this.number);

  _Token copyAs(_TokenType t) => _Token._(t, text, number);

  factory _Token.number(double n) => _Token._(_TokenType.number, null, n);
  factory _Token.identifier(String s) => _Token._(_TokenType.identifier, s, null);
  factory _Token.operatorToken(String s) => _Token._(_TokenType.operator_, s, null);
  factory _Token.lparen() => const _Token._(_TokenType.lparen, '(', null);
  factory _Token.rparen() => const _Token._(_TokenType.rparen, ')', null);
  factory _Token.comma() => const _Token._(_TokenType.comma, ',', null);
}

/// ===== Convenience helpers for using parameters with flows =====

bool _hasText(String? s) => s != null && s.trim().isNotEmpty;
String? _clean(dynamic v) {
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  return null;
}

/// Evaluate a FlowValue's amount from either a bound parameter or an expression,
/// using the provided symbol map. Returns a new FlowValue with `amount` updated.
/// If there is nothing to evaluate, returns the original.
FlowValue evaluateFlowAmount(FlowValue f, Map<String, double> symbols, {ParameterEngine? engine}) {
  final e = engine ?? ParameterEngine();
  // Simple binding takes the name as the expression
  final expr = _hasText(f.amountExpr) ? f.amountExpr : (_hasText(f.boundParam) ? f.boundParam : null);
  if (expr == null) return f;
  final evaluated = e.evaluateExpression(expr, symbols);
  return f.copyWith(amount: evaluated);
}

/// Apply evaluated parameter symbols to all flows of a process node.
/// This does not mutate the input node; it returns an updated copy.
ProcessNode evaluateProcessFlows(ProcessNode node, Map<String, double> symbols, {ParameterEngine? engine}) {
  FlowValue _eval(FlowValue f) => evaluateFlowAmount(f, symbols, engine: engine);
  return node.copyWithFields(
    inputs: node.inputs.map(_eval).toList(),
    outputs: node.outputs.map(_eval).toList(),
    emissions: node.emissions.map(_eval).toList(),
  );
}
