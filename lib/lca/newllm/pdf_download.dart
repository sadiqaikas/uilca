import 'dart:typed_data';

import 'pdf_download_stub.dart' if (dart.library.html) 'pdf_download_web.dart'
    as download_impl;

Future<void> downloadPdf({
  required Uint8List bytes,
  required String filename,
}) {
  return download_impl.downloadPdf(bytes: bytes, filename: filename);
}
