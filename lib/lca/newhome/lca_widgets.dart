


// File: lib/lca/lca_widgets.dart
//
// Reusable UI widgets for the LCA canvas and dialogs.
// - ProcessNodeWidget: the process card used on the canvas.
// - Adds collapsible mode (name only) and scientific notation with superscript.
// - Backwards compatible: default props keep current behaviour.
//
// British English copy in visible strings.

import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

import 'lca_models.dart';

class ProcessNodeWidget extends StatelessWidget {
  final ProcessNode node;
  final double heightScale;

  /// When true, shows a tiny badge next to amounts that originate
  /// from an expression (amountExpr not null). Default false keeps
  /// visuals identical to your current app.
  final bool showAmountExprBadge;

  /// When true, the card renders in a compact form that shows only the name.
  /// Default false keeps current behaviour.
  final bool collapsed;

  /// Optional toggle handler. If provided, a small button appears in the header
  /// to let the user collapse or expand the card.
  final VoidCallback? onToggleCollapse;

  const ProcessNodeWidget({
    super.key,
    required this.node,
    this.heightScale = 1.0,
    this.showAmountExprBadge = false,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textSecondary = Color(0xFF334155);
  static const Color _brandTeal = Color(0xFF0B6E63);
  static const Color _functionalGreen = Color(0xFF15803D);
  static const Color _cardBase = Color(0xFFFDFEFF);
  static const Color _cardSurfaceTint = Color(0xFFE8F4F1);

  /// Computes the card size based on the node contents, scaled by heightScale.
  /// Collapsed cards use a compact width and height.
  static Size sizeFor(
    ProcessNode n, {
    double heightScale = 1.0,
    bool collapsed = false,
  }) {
    if (collapsed) {
      // Compact footprint: just a header row
      final compactHeight = (56.0 * heightScale);
      return Size(140.0, compactHeight < 44.0 ? 44.0 : compactHeight);
    }

    const lineHeight = 18.0, padding = 16.0;
    int lines = 1; // title
    if (n.inputs.isNotEmpty) lines += 1 + n.inputs.length;   // header + items
    if (n.outputs.isNotEmpty) lines += 1 + n.outputs.length; // header + items
    // emissions section intentionally omitted to match current UI
    final height = (padding + lines * lineHeight) * heightScale;
    return Size(240.0, height < 80 ? 80 : height);
  }

  // Format as mantissa × 10^exp for very small/large values; otherwise a tidy decimal.
  ({String mantissa, int? exp}) _sciParts(double v) {
    if (v == 0) return (mantissa: '0', exp: null);
    final absV = v.abs();
    if (absV < 1e-3 || absV >= 1e3) {
      // 2 significant figures similar to openLCA
      final expStr = v.toStringAsExponential(2); // e.g. "-3.09e-07"
      final parts = expStr.split('e');
      final mantissa = parts[0];
      final e = int.parse(parts[1]); // handles +/- and leading zeros
      return (mantissa: mantissa, exp: e);
    }
    // 4 dp, trim trailing zeros and any trailing decimal point
    final s = v.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
    return (mantissa: s, exp: null);
  }

  // Build an InlineSpan "mantissa × 10^exp" with a true superscript exponent.
  InlineSpan _amountSpan(double value, String unit, {bool small = false}) {
    final parts = _sciParts(value);
    final baseStyle = TextStyle(
      fontSize: small ? 12 : 13,
      color: _textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (parts.exp == null) {
      return TextSpan(text: '${parts.mantissa} $unit', style: baseStyle);
    }

    final expStr = parts.exp!.toString();
    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: parts.mantissa),
        const TextSpan(text: ' × 10'),
        // superscript exponent
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Transform.translate(
            offset: const Offset(0, -4),
            child: Text(
              expStr,
              style: TextStyle(fontSize: (small ? 12 : 13) * 0.8),
            ),
          ),
        ),
        TextSpan(text: ' $unit'),
      ],
    );
  }

  Widget _flowRow(FlowValue f) {
    return Row(
      children: [
        Expanded(
          child: Text(
            truncateText(f.name, kNodeFlowNameMaxChars),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RichText(
              textAlign: TextAlign.right,
              text: _amountSpan(f.amount, f.unit),
            ),
            if (showAmountExprBadge && (f.amountExpr != null && f.amountExpr!.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: const Icon(Icons.functions, size: 14, color: _brandTeal),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sz = sizeFor(node, heightScale: heightScale, collapsed: collapsed);

    // Header row used by both collapsed and expanded modes
    Widget header() {
      return Row(
        children: [
          Expanded(
            child: Text(
              node.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: _textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (node.isFunctional) const Icon(Icons.flag, size: 16, color: _functionalGreen),
          if (onToggleCollapse != null)
            IconButton(
              tooltip: collapsed ? 'Expand' : 'Collapse',
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onToggleCollapse,
              icon: Icon(collapsed ? Icons.unfold_more : Icons.unfold_less),
            ),
        ],
      );
    }

    if (collapsed) {
      // Compact card: name row only
      return Card(
        elevation: 6,
        color: _cardBase,
        surfaceTintColor: _cardSurfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Container(
          width: sz.width,
          height: sz.height,
          padding: const EdgeInsets.all(8),
          decoration: node.isFunctional
              ? BoxDecoration(border: Border.all(color: _functionalGreen, width: 2))
              : null,
          child: Align(alignment: Alignment.centerLeft, child: header()),
        ),
      );
    }

    // Expanded card: full details
    return Card(
      elevation: 6,
      color: _cardBase,
      surfaceTintColor: _cardSurfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: sz.width,
        height: sz.height, // fixed to make resize effective; inner scroll if needed
        padding: const EdgeInsets.all(8),
        decoration: node.isFunctional
            ? BoxDecoration(border: Border.all(color: _functionalGreen, width: 2))
            : null,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 13, color: _textPrimary),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header(),
                if (node.inputs.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Inputs:',
                    style: TextStyle(fontWeight: FontWeight.w600, color: _textSecondary),
                  ),
                  ...node.inputs.map(_flowRow),
                ],
                if (node.outputs.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Outputs:',
                    style: TextStyle(fontWeight: FontWeight.w600, color: _textSecondary),
                  ),
                  ...node.outputs.map(_flowRow),
                ],
                // emissions section intentionally not shown to preserve current UI
              ],
            ),
          ),
        ),
      ),
    );
  }
}
