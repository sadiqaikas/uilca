import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> downloadPdf({
  required Uint8List bytes,
  required String filename,
}) async {
  try {
    await Printing.sharePdf(
      bytes: bytes,
      filename: filename,
    );
  } catch (_) {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: filename,
    );
  }
}
