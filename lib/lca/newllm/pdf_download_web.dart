// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
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
