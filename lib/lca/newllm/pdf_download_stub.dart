import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<void> downloadFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) async {
  Directory? directory = await getDownloadsDirectory();
  directory ??= await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
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
