import 'dart:typed_data';

import 'pdf_download_stub.dart' if (dart.library.html) 'pdf_download_web.dart'
    as download_impl;

Future<void> downloadFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  return download_impl.downloadFile(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
  );
}

Future<void> downloadPdf({
  required Uint8List bytes,
  required String filename,
}) {
  return downloadFile(
    bytes: bytes,
    filename: filename,
    mimeType: 'application/pdf',
  );
}
